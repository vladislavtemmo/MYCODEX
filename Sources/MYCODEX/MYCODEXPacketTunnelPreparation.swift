/// Подготовка Packet Tunnel на control plane. Не создаёт и не подтверждает VPN.
/// Объект не Sendable; его владелец обязан сериализовать все вызовы.
public enum MYCODEXPacketTunnelPreparationState: Equatable, Sendable {
    case idle
    case applyingSettings
    case settingsApplied
    case coreTransportReady
    case failed
    case stopped
}

public enum MYCODEXPacketTunnelPreparationError: Error, Equatable, Sendable {
    case invalidState
    case staleCallback
    case networkSettingsRejected
    case nativeTransportUnavailable
    case cancelled
    case providerUnavailable
}

/// Жизненный цикл асинхронного применения сетевых настроек.
/// Токен не даёт запоздалому callback после stop() изменить состояние.
public final class MYCODEXPacketTunnelPreparation {
    public private(set) var state: MYCODEXPacketTunnelPreparationState = .idle
    private var generation: UInt64 = 0

    public init() {}

    /// Разрешён однократно для одного запуска Packet Tunnel Provider.
    @discardableResult
    public func beginSettingsApplication() throws -> UInt64 {
        guard state == .idle else { throw MYCODEXPacketTunnelPreparationError.invalidState }
        generation &+= 1
        state = .applyingSettings
        return generation
    }

    /// Успешный setTunnelNetworkSettings означает только готовность маршрутизации,
    /// а НЕ VPN CONNECTED. При отказе состояние становится failed.
    public func settingsDidComplete(token: UInt64, accepted: Bool) throws {
        guard state == .applyingSettings, generation == token else {
            throw MYCODEXPacketTunnelPreparationError.staleCallback
        }
        if accepted {
            state = .settingsApplied
        } else {
            state = .failed
            throw MYCODEXPacketTunnelPreparationError.networkSettingsRejected
        }
    }

    /// Проверка реальной интеграции native TUN adapter. Никаких test/null TUN.
    /// Даже положительный результат НЕ означает завершения TLS или CONNECTED.
    public func checkNativeTransport(isAvailable: Bool) throws {
        guard state == .settingsApplied else {
            throw MYCODEXPacketTunnelPreparationError.invalidState
        }
        guard isAvailable else {
            state = .failed
            throw MYCODEXPacketTunnelPreparationError.nativeTransportUnavailable
        }
        state = .coreTransportReady
    }

    /// Идемпотентная отмена. Параллельный сетевой callback после этого устаревает.
    public func stop() {
        guard state != .stopped else { return }
        generation &+= 1
        state = .stopped
    }
}
