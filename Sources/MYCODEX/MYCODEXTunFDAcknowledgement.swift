import Foundation
import COpenVPNBridge
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Failure codes for the guarded native TunBuilder FD handoff.
/// This does not indicate an established VPN connection.
public enum MYCODEXTunFDAcknowledgementError: Error, Equatable, Sendable {
    case invalidGeneration
    case invalidState
    case unavailable
    case cancelled
    case nativeFailure
    case invalidFileDescriptor
    case blockingOnMainThread
    case unexpectedStatus(Int32)
}

/// All calls share the OpenVPNClient lifetime. In particular, no call may
/// overlap deinit; cancel, join the Core worker, then release the client.
/// `waitForPendingTunSettings` is BLOCKING: use a dedicated background worker
/// and never call it on the Provider's main actor or main thread.
extension OpenVPNClient {
    public func attachTunSocket(_ socket: MYCODEXTunSocketTransport) throws {
        #if os(Windows)
        throw MYCODEXTunFDAcknowledgementError.unavailable
        #else
        let fd = try socket.duplicateCoreFileDescriptor()
        defer { _ = close(fd) }  // Native handoff borrows and duplicates the FD.
        switch mycodex_client_tun_attach_fd(handleForTunCapture, fd) {
        case 0: return
        case -1: throw MYCODEXTunFDAcknowledgementError.invalidFileDescriptor
        case -2: throw MYCODEXTunFDAcknowledgementError.unavailable
        case -4: throw MYCODEXTunFDAcknowledgementError.invalidState
        case -3: throw MYCODEXTunFDAcknowledgementError.nativeFailure
        case let code: throw MYCODEXTunFDAcknowledgementError.unexpectedStatus(code)
        }
        #endif
    }

    /// Returns nil on timeout, generation on a pending Core establish request.
    /// Do not concurrently destroy the client, and do not block MainActor.
    public func waitForPendingTunSettings(timeoutMilliseconds: UInt32 = 1000) throws -> UInt64? {
        guard timeoutMilliseconds <= 30_000 else {
            throw MYCODEXTunFDAcknowledgementError.invalidState
        }
        guard !Thread.isMainThread else {
            throw MYCODEXTunFDAcknowledgementError.blockingOnMainThread
        }
        var generation: UInt64 = 0
        let result = mycodex_client_tun_wait_pending(handleForTunCapture,
                                                     timeoutMilliseconds, &generation)
        switch result {
        case 1:
            guard generation > 0 else { throw MYCODEXTunFDAcknowledgementError.nativeFailure }
            return generation
        case 0: return nil
        case -1: throw MYCODEXTunFDAcknowledgementError.invalidState
        case -2: throw MYCODEXTunFDAcknowledgementError.unavailable
        case -3: throw MYCODEXTunFDAcknowledgementError.cancelled
        case let code: throw MYCODEXTunFDAcknowledgementError.unexpectedStatus(code)
        }
    }

    public func acknowledgeTunSettings(generation: UInt64, applied: Bool) throws {
        guard generation > 0 else { throw MYCODEXTunFDAcknowledgementError.invalidGeneration }
        let result = mycodex_client_tun_ack_settings(handleForTunCapture,
                                                     generation, applied ? 1 : 0)
        switch result {
        case 0: return
        case -1: throw MYCODEXTunFDAcknowledgementError.invalidGeneration
        case -2: throw MYCODEXTunFDAcknowledgementError.unavailable
        case -3: throw MYCODEXTunFDAcknowledgementError.nativeFailure
        case -4: throw MYCODEXTunFDAcknowledgementError.invalidState
        case let code: throw MYCODEXTunFDAcknowledgementError.unexpectedStatus(code)
        }
    }

    public func cancelTunHandoff() throws {
        let result = mycodex_client_tun_cancel(handleForTunCapture)
        switch result {
        case 0: return
        case -1: throw MYCODEXTunFDAcknowledgementError.invalidState
        case -2: throw MYCODEXTunFDAcknowledgementError.unavailable
        case -3: throw MYCODEXTunFDAcknowledgementError.nativeFailure
        case let code: throw MYCODEXTunFDAcknowledgementError.unexpectedStatus(code)
        }
    }
}

/// Small, actor-isolated boundary used by the Apple settings coordinator.
/// Real clients implement this via the synchronous, guarded C ABI; tests use
/// a fake to prove ACK ordering without a VPN entitlement or server.
@MainActor
public protocol MYCODEXTunFDSettingsClient: AnyObject {
    func capturedTunnelConfiguration() throws -> MYCODEXTunnelNetworkConfiguration
    func acknowledgeTunSettings(generation: UInt64, applied: Bool) throws
    func cancelTunHandoff() throws
}

extension OpenVPNClient: MYCODEXTunFDSettingsClient {}

public enum MYCODEXTunFDSettingsState: Equatable, Sendable {
    case idle
    case applying(generation: UInt64)
    case acknowledged
    case rejected
    case cancelled
}

public enum MYCODEXTunFDSettingsError: Error, Equatable, Sendable {
    case invalidState
    case invalidGeneration
    case snapshotUnavailable
    case networkSettingsRejected
    case nativeAcknowledgementFailed
    case cancelled
}

/// Serialises snapshot -> OS settings callback -> native generation ACK.
/// A successful ACK means ONLY that Apple accepted routing settings, not TLS,
/// packet flow or VPN CONNECTED. The native generation is never guessed.
@MainActor
public final class MYCODEXTunFDSettingsCoordinator {
    private let native: any MYCODEXTunFDSettingsClient
    private var completion: (@MainActor (Result<Void, MYCODEXTunFDSettingsError>) -> Void)?
    public private(set) var state: MYCODEXTunFDSettingsState = .idle

    public init(native: any MYCODEXTunFDSettingsClient) {
        self.native = native
    }

    /// The generation MUST originate from a successful native wait_pending.
    /// `apply` must complete only after setTunnelNetworkSettings finishes.
    public func begin(
        generation: UInt64,
        apply: @escaping @MainActor (
            MYCODEXTunnelNetworkConfiguration,
            @escaping @MainActor (Bool) -> Void
        ) -> Void,
        completion: @escaping @MainActor (Result<Void, MYCODEXTunFDSettingsError>) -> Void
    ) {
        guard generation != 0 else {
            completion(.failure(.invalidGeneration))
            return
        }
        guard state == .idle else {
            completion(.failure(.invalidState))
            return
        }
        state = .applying(generation: generation)
        self.completion = completion

        let config: MYCODEXTunnelNetworkConfiguration
        do {
            config = try native.capturedTunnelConfiguration()
        } catch {
            // The Core worker must not wait for a callback that cannot arrive.
            rejectOnFailure(generation: generation, reason: .snapshotUnavailable)
            return
        }
        apply(config) { [weak self] accepted in
            self?.complete(generation: generation, accepted: accepted)
        }
    }

    /// Cancels the native pending establish even if Apple's callback is late.
    /// Call before releasing the client or its PacketFlow/socket resources.
    public func cancel() {
        guard state != .cancelled else { return }
        let wasApplying: Bool
        if case .applying = state { wasApplying = true } else { wasApplying = false }
        state = .cancelled
        let callback = completion
        completion = nil
        try? native.cancelTunHandoff()
        if wasApplying { callback?(.failure(.cancelled)) }
    }

    private func complete(generation: UInt64, accepted: Bool) {
        guard case .applying(let pending) = state, pending == generation else { return }
        let callback = completion
        completion = nil
        do {
            try native.acknowledgeTunSettings(generation: generation, applied: accepted)
            state = accepted ? .acknowledged : .rejected
            if accepted {
                callback?(.success(()))
            } else {
                callback?(.failure(.networkSettingsRejected))
            }
        } catch {
            state = .rejected
            try? native.cancelTunHandoff()
            callback?(.failure(.nativeAcknowledgementFailed))
        }
    }

    private func rejectOnFailure(generation: UInt64, reason: MYCODEXTunFDSettingsError) {
        guard case .applying(let pending) = state, pending == generation else { return }
        let callback = completion
        completion = nil
        do {
            try native.acknowledgeTunSettings(generation: generation, applied: false)
        } catch {
            try? native.cancelTunHandoff()
        }
        state = .rejected
        callback?(.failure(reason))
    }
}
