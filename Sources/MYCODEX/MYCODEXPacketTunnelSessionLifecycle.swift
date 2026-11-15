import Foundation

/// Жизненный цикл Provider на уровне управления. Он НЕ открывает VPN-соединение.
/// Только настоящий Core `CONNECTED` после настроек и запуска пакетного
/// транспорта разрешает владельцу завершить `startTunnel` без ошибки.
public enum MYCODEXPacketTunnelSessionPhase: Equatable, Sendable {
    case idle
    case awaitingNetworkSettings(UInt64)
    case awaitingPacketTransport(UInt64)
    case awaitingCoreConnection(UInt64)
    case connected(UInt64)
    case failed
    case stopping(UInt64)
    case releasingResources(UInt64)
    case stopped
}

public enum MYCODEXPacketTunnelSessionError: Error, Equatable, Sendable {
    case invalidState
    case networkSettingsRejected
    case packetTransportUnavailable
    case nativeTunnelUnavailable
    case coreConnectionFailed
    case coreDisconnected
    case cancelled
}

/// Все вызовы и callback'и проходят через MainActor. Долгий Core join
/// выполняет *владелец* на фоновом рабочем потоке; здесь фиксируется только
/// факт его завершения. Состояния запрещают освобождение C ABI до join.
@MainActor
public final class MYCODEXPacketTunnelSessionLifecycle {
    public private(set) var phase: MYCODEXPacketTunnelSessionPhase = .idle

    private var generation: UInt64 = 0
    private var startCompletion: (@MainActor (Result<Void, MYCODEXPacketTunnelSessionError>) -> Void)?
    private var onDisconnection: (@MainActor (MYCODEXPacketTunnelSessionError) -> Void)?
    private var stopCompletions: [@MainActor () -> Void] = []

    public init() {}

    /// Старт доступен только из idle/stopped. Повторный запуск требует
    /// завершённого stop: worker joined -> resources released.
    @discardableResult
    public func begin(
        completion: @escaping @MainActor (Result<Void, MYCODEXPacketTunnelSessionError>) -> Void,
        onDisconnection: @escaping @MainActor (MYCODEXPacketTunnelSessionError) -> Void
    ) -> UInt64? {
        guard phase == .idle || phase == .stopped else {
            completion(.failure(.invalidState))
            return nil
        }
        generation &+= 1
        if generation == 0 { generation = 1 }
        phase = .awaitingNetworkSettings(generation)
        startCompletion = completion
        self.onDisconnection = onDisconnection
        return generation
    }

    /// Вызывать только по завершении реального Apple setTunnelNetworkSettings
    /// и нативного generation ACK. В любом другом состоянии событие устарело.
    @discardableResult
    public func networkSettingsDidComplete(generation: UInt64, accepted: Bool) -> Bool {
        guard phase == .awaitingNetworkSettings(generation) else { return false }
        if accepted {
            phase = .awaitingPacketTransport(generation)
        } else {
            fail(generation: generation, reason: .networkSettingsRejected)
        }
        return true
    }

    /// Подтверждается владельцем после успешного запуска реального драйвера.
    /// Не подменять это событие созданием очереди или socketpair без PacketFlow.
    @discardableResult
    public func packetTransportDidStart(generation: UInt64) -> Bool {
        guard phase == .awaitingPacketTransport(generation) else { return false }
        phase = .awaitingCoreConnection(generation)
        return true
    }

    /// `CONNECTED` должен приходить из OpenVPNClient.pollEvent(), не из
    /// Swift fixture. RUNNING в состоянии потока Core не означает CONNECTED.
    @discardableResult
    public func receiveCoreEvent(_ event: OpenVPNClientEvent, generation: UInt64) -> Bool {
        if phase == .awaitingNetworkSettings(generation) ||
           phase == .awaitingPacketTransport(generation) ||
           phase == .awaitingCoreConnection(generation) {
            if event.isError || event.isFatal {
                fail(generation: generation, reason: .coreConnectionFailed)
                return true
            }
            if event.name == "CONNECTED" {
                guard phase == .awaitingCoreConnection(generation) else {
                    fail(generation: generation, reason: .invalidState)
                    return true
                }
                phase = .connected(generation)
                let callback = startCompletion
                startCompletion = nil
                callback?(.success(()))
                return true
            }
            return false
        }
        if phase == .connected(generation) {
            if event.isError || event.isFatal ||
               event.name == "DISCONNECTED" || event.name == "EXITING" {
                fail(generation: generation, reason: .coreDisconnected)
                return true
            }
        }
        return false
    }

    /// Явная ошибка настройки/транспорта/worker. Успешный start-completion
    /// не отменяется, но владелец получает termination callback после CONNECTED.
    @discardableResult
    public func fail(generation: UInt64, reason: MYCODEXPacketTunnelSessionError) -> Bool {
        let wasConnected = phase == .connected(generation)
        let isPreparing = phase == .awaitingNetworkSettings(generation) ||
                          phase == .awaitingPacketTransport(generation) ||
                          phase == .awaitingCoreConnection(generation)
        guard wasConnected || isPreparing else { return false }
        phase = .failed
        let start = startCompletion
        startCompletion = nil
        let disconnected = onDisconnection
        onDisconnection = nil
        if wasConnected {
            disconnected?(reason)
        } else {
            start?(.failure(reason))
        }
        return true
    }

    /// Начинает остановку и инвалидирует generation прежней попытки.
    /// Возвращает stop-token только первому вызывающему; повторные stop
    /// добавляют completion, но не должны повторно останавливать Core.
    @discardableResult
    public func requestStop(completion: @escaping @MainActor () -> Void) -> UInt64? {
        switch phase {
        case .idle, .stopped:
            phase = .stopped
            completion()
            return nil
        case .stopping, .releasingResources:
            stopCompletions.append(completion)
            return nil
        default:
            generation &+= 1
            if generation == 0 { generation = 1 }
            let stopToken = generation
            phase = .stopping(stopToken)
            let pending = startCompletion
            startCompletion = nil
            onDisconnection = nil
            stopCompletions = [completion]
            pending?(.failure(.cancelled))
            return stopToken
        }
    }

    /// Разрешает остановку GCD и PacketFlow после настоящего `waitForWorker()`.
    @discardableResult
    public func coreWorkerDidJoin(stopToken: UInt64) -> Bool {
        guard phase == .stopping(stopToken) else { return false }
        phase = .releasingResources(stopToken)
        return true
    }

    /// Вызывать только после stopMonitoring(), закрытия socketpair и очередей.
    /// Только здесь системному stopTunnel разрешается вызвать completionHandler.
    @discardableResult
    public func resourcesDidRelease(stopToken: UInt64) -> Bool {
        guard phase == .releasingResources(stopToken) else { return false }
        phase = .stopped
        let callbacks = stopCompletions
        stopCompletions = []
        callbacks.forEach { $0() }
        return true
    }
}
