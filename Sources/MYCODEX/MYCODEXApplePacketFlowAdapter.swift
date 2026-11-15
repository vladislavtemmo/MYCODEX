#if canImport(NetworkExtension)
import Foundation
import NetworkExtension

/// Обёртка над реальным NEPacketTunnelFlow, вызываемая ТОЛЬКО внутри
/// подписанного NEPacketTunnelProvider ПОСЛЕ setTunnelNetworkSettings.
/// Система -> staging queue и staging queue -> система; OpenVPN Core
/// к этим очередям пока не подключён, поэтому start VPN не разрешён.
///
/// Все публичные методы изолированы MainActor. Разбор данных из системных
/// callback'ов переводится на MainActor без передачи NSNumber между потоками.
@MainActor
public final class MYCODEXApplePacketFlowAdapter {
    private let flow: NEPacketTunnelFlow
    private let coordinator: MYCODEXPacketFlowCoordinator
    private let onFailure: @MainActor (any Error) -> Void
    private var active = false
    private var readInFlight = false

    /// The owning transport driver can subscribe to *newly staged* packets.
    /// Callbacks are MainActor-isolated. Do not pump from inside readPackets.
    public var onIngressStaged: (@MainActor () -> Void)?

    public init(flow: NEPacketTunnelFlow,
                bridge: MYCODEXPacketBridge,
                onFailure: @escaping @MainActor (any Error) -> Void) {
        self.flow = flow
        self.coordinator = MYCODEXPacketFlowCoordinator(bridge: bridge)
        self.onFailure = onFailure
    }

    /// Вызывать только после успешного setTunnelNetworkSettings в Provider.
    /// Важно: само по себе начало чтения пакетов НЕ запускает OpenVPN Core.
    public func beginReading() {
        guard !active else { return }
        active = true
        readNextIfPossible()
    }

    /// Потребитель toCore должен вызывать после освобождения места в очереди.
    /// До этого новые системные readPackets намеренно НЕ регистрируются.
    public func ingressQueueDidDrain() {
        guard active else { return }
        do {
            let before = coordinator.hasPendingIngress
            if try coordinator.resumeIncoming() {
                if before { onIngressStaged?() }
                readNextIfPossible()
            } else if before { onIngressStaged?() }
        } catch { fail(error) }
    }

    /// Вызывать по сигналу Core->system producer или по безопасному
    /// расписанию Provider; автоматический polling здесь не включён.
    /// false = writePackets вернул false, партия сохранена для повтора.
    @discardableResult
    public func flushCoreToSystem(maxBatch: Int = 32) throws -> Bool {
        guard active else { throw MYCODEXPacketFlowError.closed }
        return try coordinator.flushOutgoing(maxBatch: maxBatch) { [flow] packets in
            flow.writePackets(packets.map(\.data), withProtocols: packets.map {
                NSNumber(value: $0.kind.protocolFamily)
            })
        }
    }

    /// Не отменяет уже начатый readPackets. Запоздалый callback игнорируется.
    public func stop() {
        guard active else { return }
        active = false
        do { try coordinator.close() } catch { onFailure(error) }
    }

    private func readNextIfPossible() {
        guard active, !readInFlight, !coordinator.hasPendingIngress else { return }
        readInFlight = true
        flow.readPackets { [weak self] packets, protocols in
            // NSNumber -> Int32 на потоке callback; Task переносит только
            // Sendable-данные [Data] и [Int32]. Никаких IP payload логов.
            let families = protocols.map { $0.int32Value }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.readInFlight = false
                guard self.active else { return }
                do {
                    let batch = try MYCODEXPacketFlowCoordinator.classify(packets,
                                                            protocolFamilies: families)
                    let canContinue = try self.coordinator.stageIncoming(batch)
                    if !batch.isEmpty { self.onIngressStaged?() }
                    if canContinue { self.readNextIfPossible() }
                } catch { self.fail(error) }
            }
        }
    }

    private func fail(_ error: any Error) {
        guard active else { return }
        active = false
        do { try coordinator.close() } catch { /* Original error retained. */ }
        onFailure(error)
    }
}
#endif
