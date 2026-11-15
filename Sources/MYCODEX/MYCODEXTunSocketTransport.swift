import Foundation
import COpenVPNBridge

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A POSIX datagram socketpair adapter for the existing bounded packet queues.
/// This is not a NetworkExtension or a connected VPN.
public enum MYCODEXTunSocketError: Error, Sendable, Equatable {
    case unsupported
    case invalidArgument
    case closed
    case invalidPacket
    case ioFailure
    case queueFailure
    case unexpectedStatus(Int32)
}

public struct MYCODEXTunSocketProgress: Sendable, Equatable {
    public let intoCore: UInt32
    public let intoSystem: UInt32
}

/// Controls a native socketpair; preserves IP packet boundaries (SOCK_DGRAM).
///
/// Owns its socketpair; strongly retains the packet queue, which must outlive
/// any native pump. Not Sendable: the owner must serialize lifetime and close.
/// No background polling thread is created. An external wakeup mechanism is
/// required to drive pump() when the queues or the Core FD become readable.
public final class MYCODEXTunSocketTransport {
    private let bridge: MYCODEXPacketBridge
    private let handle: OpaquePointer

    public init(bridge: MYCODEXPacketBridge) throws {
        #if os(Windows)
        throw MYCODEXTunSocketError.unsupported
        #else
        guard let handle = bridge.withNativeHandle({ mycodex_tun_socket_create($0) }) else {
            throw MYCODEXTunSocketError.ioFailure
        }
        self.bridge = bridge
        self.handle = handle
        #endif
    }

    deinit { mycodex_tun_socket_destroy(handle) }

    /// Duplicates the socket endpoint for the future Core TUN consumer.
    /// The caller owns the returned descriptor and MUST close it. Do not
    /// enable OpenVPNClient.start() merely because this descriptor exists.
    public func duplicateCoreFileDescriptor() throws -> Int32 {
        let result = mycodex_tun_socket_dup_core_fd(handle)
        if result >= 0 { return result }
        throw Self.error(result)
    }

    /// Returns a caller-owned POSIX FD for observing the native pump socket.
    /// Only use with readiness monitors. NEVER recv/send on this duplicate:
    /// those operations must be performed exclusively by pump().
    public func duplicateMonitorFileDescriptor() throws -> Int32 {
        let result = mycodex_tun_socket_dup_monitor_fd(handle)
        if result >= 0 { return result }
        if result == -2 { throw MYCODEXTunSocketError.unsupported }
        throw Self.error(result)
    }

    /// True when the native pump retains a datagram that could not be sent.
    /// This is distinct from the toCore staging queue statistics.
    public func hasPendingCoreWrite() throws -> Bool {
        let result = mycodex_tun_socket_core_write_pending(handle)
        if result == 1 { return true }
        if result == 0 { return false }
        if result == -2 { throw MYCODEXTunSocketError.unsupported }
        throw Self.error(result)
    }

    /// Moves at most `maxPerDirection` packets from Core->system and
    /// system->Core. No busy-waiting; no implicit background loop.
    /// A full queue retains its pending datagram until a later pump().
    public func pump(maxPerDirection: UInt32 = 32) throws -> MYCODEXTunSocketProgress {
        var core: UInt32 = 0
        var system: UInt32 = 0
        let result = mycodex_tun_socket_pump(handle, maxPerDirection, &core, &system)
        guard result == 0 else { throw Self.error(result) }
        return MYCODEXTunSocketProgress(intoCore: core, intoSystem: system)
    }

    public func close() throws {
        let result = mycodex_tun_socket_close(handle)
        guard result == 0 else { throw Self.error(result) }
    }

    private static func error(_ value: Int32) -> MYCODEXTunSocketError {
        switch value {
        case -1: return .invalidArgument
        case -2: return .invalidPacket
        case -3: return .closed
        case -4: return .ioFailure
        case -5: return .queueFailure
        default: return .unexpectedStatus(value)
        }
    }
}
