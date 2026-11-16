#if canImport(NetworkExtension) && canImport(Darwin)
import Foundation
import NetworkExtension

/// Граница для проверок порядка событий. Production-реализация ниже владеет
/// Core handle, очередями, socketpair, ACK, PacketFlow и DispatchSource.
@MainActor
public protocol MYCODEXAppleTunnelSessionRuntime: AnyObject, Sendable {
    func start() throws
    func waitForPendingTunSettings() async throws -> UInt64?
    func applyPendingTunSettings(generation: UInt64) async -> Bool
    func startPacketTransport() throws
    func pollEvent() throws -> OpenVPNClientEvent?
    func workerState() throws -> OpenVPNClientRunState
    func requestStop() throws
    func joinWorker() async throws
    func releaseResources() async
}

public struct MYCODEXAppleTunnelCredentials: Sendable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

/// Состояние, опубликованное для хоста только через результат start/stop.
/// Все решения о CONNECTED принимает существующий lifecycle по событию Core.
@MainActor
public final class MYCODEXApplePacketTunnelSessionController {
    public typealias RuntimeFactory = @MainActor @Sendable (
        OpenVPNProfile, MYCODEXAppleTunnelCredentials?, UInt64
    ) async throws -> any MYCODEXAppleTunnelSessionRuntime

    public private(set) var lifecycle = MYCODEXPacketTunnelSessionLifecycle()
    public var phase: MYCODEXPacketTunnelSessionPhase { lifecycle.phase }

    private let makeRuntime: RuntimeFactory
    private let onDisconnection: @MainActor @Sendable (MYCODEXPacketTunnelSessionError) -> Void
    private var activeGeneration: UInt64?
    private var lastNativeGeneration: UInt64?
    private var runtime: (any MYCODEXAppleTunnelSessionRuntime)?
    private var preparation: Task<any MYCODEXAppleTunnelSessionRuntime, Error>?
    private var monitor: Task<Void, Never>?
    private var cleanup: Task<Void, Never>?

    public init(makeRuntime: @escaping RuntimeFactory,
                onDisconnection: @escaping @MainActor @Sendable (MYCODEXPacketTunnelSessionError) -> Void) {
        self.makeRuntime = makeRuntime
        self.onDisconnection = onDisconnection
    }

    /// Profile и credentials передаются только в памяти через options.
    /// Пустой/невалидный профиль не создаёт native client.
    public func start(profileText: String?, credentials: MYCODEXAppleTunnelCredentials?,
                      completion: @escaping @MainActor (Result<Void, MYCODEXPacketTunnelSessionError>) -> Void) {
        guard let generation = lifecycle.begin(completion: completion,
                                               onDisconnection: onDisconnection) else { return }
        activeGeneration = generation
        lastNativeGeneration = nil
        guard let profileText, let profile = try? OpenVPNProfile(ovpnText: profileText) else {
            fail(generation: generation, reason: .coreConnectionFailed)
            return
        }
        preparation = Task { [makeRuntime] in
            try await makeRuntime(profile, credentials, generation)
        }
        Task { [weak self] in await self?.finishPreparation(generation: generation) }
    }

    private func finishPreparation(generation: UInt64) async {
        guard let preparation else { return }
        let result = await preparation.result
        guard activeGeneration == generation else { return }
        switch result {
        case .failure:
            fail(generation: generation, reason: .coreConnectionFailed)
        case .success(let prepared):
            runtime = prepared
            do {
                try prepared.start() // C ABI создаёт worker без блокирующего join.
            } catch {
                fail(generation: generation, reason: .nativeTunnelUnavailable)
                return
            }
            monitor = Task { [weak self] in await self?.monitorCore(generation: generation) }
        }
    }

    private func monitorCore(generation: UInt64) async {
        while activeGeneration == generation && !Task.isCancelled {
            guard let runtime else { return }
            do {
                if let nativeGeneration = try await runtime.waitForPendingTunSettings() {
                    guard activeGeneration == generation else { return }
                    if lastNativeGeneration != nativeGeneration {
                        lastNativeGeneration = nativeGeneration
                        let accepted = await runtime.applyPendingTunSettings(generation: nativeGeneration)
                        guard activeGeneration == generation else { return }
                        guard accepted else {
                            fail(generation: generation, reason: .networkSettingsRejected)
                            return
                        }
                        guard lifecycle.networkSettingsDidComplete(generation: generation, accepted: true) else { return }
                        do {
                            try runtime.startPacketTransport()
                        } catch {
                            fail(generation: generation, reason: .packetTransportUnavailable)
                            return
                        }
                        guard activeGeneration == generation else { return }
                        guard lifecycle.packetTransportDidStart(generation: generation) else { return }
                    }
                }
                while let event = try runtime.pollEvent() {
                    guard activeGeneration == generation else { return }
                    _ = lifecycle.receiveCoreEvent(event, generation: generation)
                    if lifecycle.phase == .failed {
                        stop(completion: {})
                        return
                    }
                }
                switch try runtime.workerState() {
                case .failed, .stopped:
                    let reason: MYCODEXPacketTunnelSessionError =
                        lifecycle.phase == .connected(generation) ? .coreDisconnected : .coreConnectionFailed
                    fail(generation: generation, reason: reason)
                    return
                default: break
                }
                try await Task.sleep(for: .milliseconds(50))
            } catch is CancellationError {
                return
            } catch {
                fail(generation: generation, reason: .coreConnectionFailed)
                return
            }
        }
    }

    public func transportDidFail(generation: UInt64) {
        fail(generation: generation, reason: .packetTransportUnavailable)
    }

    private func fail(generation: UInt64, reason: MYCODEXPacketTunnelSessionError) {
        guard activeGeneration == generation else { return }
        _ = lifecycle.fail(generation: generation, reason: reason)
        stop(completion: {})
    }

    /// Первым действием инвалидирует generation. Повторные stop только
    /// добавляют callback; ресурсы освобождаются после фонового join.
    public func stop(completion: @escaping @MainActor () -> Void) {
        guard let token = lifecycle.requestStop(completion: completion) else { return }
        activeGeneration = nil
        lastNativeGeneration = nil
        preparation?.cancel()
        monitor?.cancel()
        try? runtime?.requestStop() // cancel handoff -> Core stop; join ниже.
        cleanup = Task { await self.finishStop(token: token) }
    }

    private func finishStop(token: UInt64) async {
        if let preparation {
            let result = await preparation.result
            if runtime == nil, case .success(let staleRuntime) = result {
                try? staleRuntime.requestStop()
                // Never destroy an opaque client if native join did not confirm.
                do { try await staleRuntime.joinWorker() } catch { return }
                await staleRuntime.releaseResources()
            }
        }
        if let monitor { await monitor.value }
        if let runtime {
            do { try await runtime.joinWorker() } catch { return }
        }
        guard lifecycle.coreWorkerDidJoin(stopToken: token) else { return }
        await runtime?.releaseResources()
        runtime = nil
        preparation = nil
        monitor = nil
        _ = lifecycle.resourcesDidRelease(stopToken: token)
        cleanup = nil
    }
}

/// Передаётся с фоновой очереди на MainActor однократно до Core start.
/// @unchecked нужен только для передачи владения; после передачи все обычные
/// операции с handle выполняются через MainActor.
private final class PreparedNativeResources: @unchecked Sendable {
    let client: OpenVPNClient
    let bridge: MYCODEXPacketBridge
    let socket: MYCODEXTunSocketTransport

    init(profile: OpenVPNProfile, credentials: MYCODEXAppleTunnelCredentials?) throws {
        client = try OpenVPNClient()
        try client.configure(profile)
        if let credentials {
            try client.provideCredentials(username: credentials.username, password: credentials.password)
        }
        bridge = try MYCODEXPacketBridge()
        socket = try MYCODEXTunSocketTransport(bridge: bridge)
        try client.attachTunSocket(socket)
    }
}

/// Фоновое ожидание удерживает клиент до возврата wait. Владелец не
/// освобождает Core handle, пока monitor и join не завершены.
private final class NativeWaitLease: @unchecked Sendable {
    let client: OpenVPNClient
    init(_ client: OpenVPNClient) { self.client = client }
}

@MainActor
public final class MYCODEXAppleOpenVPNRuntime: MYCODEXAppleTunnelSessionRuntime {
    private var native: PreparedNativeResources?
    private var handoff: MYCODEXAppleTunFDSettingsHandoff?
    private var packetFlow: MYCODEXApplePacketFlowAdapter?
    private var driver: MYCODEXApplePacketTransportDriver?

    public static func prepare(profile: OpenVPNProfile,
                               credentials: MYCODEXAppleTunnelCredentials?,
                               provider: NEPacketTunnelProvider,
                               onFailure: @escaping @MainActor () -> Void) async throws -> MYCODEXAppleOpenVPNRuntime {
        let prepared = try await Task.detached(priority: .userInitiated) {
            try PreparedNativeResources(profile: profile, credentials: credentials)
        }.value
        return try MYCODEXAppleOpenVPNRuntime(prepared: prepared, provider: provider, onFailure: onFailure)
    }

    private init(prepared: PreparedNativeResources, provider: NEPacketTunnelProvider,
                 onFailure: @escaping @MainActor () -> Void) throws {
        native = prepared
        handoff = MYCODEXAppleTunFDSettingsHandoff(provider: provider, nativeClient: prepared.client)
        let flow = MYCODEXApplePacketFlowAdapter(flow: provider.packetFlow, bridge: prepared.bridge) { _ in
            onFailure()
        }
        packetFlow = flow
        driver = try MYCODEXApplePacketTransportDriver(bridge: prepared.bridge,
                                                       transport: prepared.socket,
                                                       packetFlow: flow) { _ in onFailure() }
    }

    public func start() throws { try native?.client.start() }

    public func waitForPendingTunSettings() async throws -> UInt64? {
        guard let client = native?.client else { return nil }
        let lease = NativeWaitLease(client)
        return try await Task.detached {
            try lease.client.waitForPendingTunSettings(timeoutMilliseconds: 250)
        }.value
    }

    public func applyPendingTunSettings(generation: UInt64) async -> Bool {
        guard let handoff else { return false }
        return await withCheckedContinuation { continuation in
            handoff.applyPending(generation: generation) { result in
                if case .success = result { continuation.resume(returning: true) }
                else { continuation.resume(returning: false) }
            }
        }
    }

    public func startPacketTransport() throws {
        guard let driver else { throw MYCODEXPacketTunnelSessionError.packetTransportUnavailable }
        driver.startMonitoring()
    }

    public func pollEvent() throws -> OpenVPNClientEvent? { try native?.client.pollEvent() }
    public func workerState() throws -> OpenVPNClientRunState { try native?.client.runState ?? .stopped }

    public func requestStop() throws {
        handoff?.cancel()
        let cancellation = Result { try native?.client.cancelTunHandoff() }
        let stopping = Result { try native?.client.requestStop() }
        try cancellation.get()
        try stopping.get()
    }

    public func joinWorker() async throws {
        guard let client = native?.client else { return }
        let lease = NativeWaitLease(client)
        try await Task.detached { try lease.client.waitForWorker() }.value
    }

    public func releaseResources() async {
        await driver?.stopMonitoringAndWait()
        driver = nil
        packetFlow = nil
        handoff = nil
        try? native?.socket.close()
        try? native?.bridge.close()
        native = nil
    }
}
#endif
