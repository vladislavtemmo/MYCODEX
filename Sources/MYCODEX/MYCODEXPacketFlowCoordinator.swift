import Foundation

/// Ошибка транспортного слоя, до подключения OpenVPN Core к Apple PacketFlow.
public enum MYCODEXPacketFlowError: Error, Equatable, Sendable {
    case pendingReadBatch
    case invalidReadBatch
    case protocolFamilyMismatch
    case packetExceedsQueueCapacity
    case invalidBatchLimit
    case closed
}

/// Сериализуемый вызывающим кодом координатор между системным PacketFlow и
/// нативной пакетной очередью. НЕ выполняет шифрование и НЕ подключён к Core.
///
/// Входящая партия удерживается полностью при backpressure: новая партия
/// не принимается до успешного переноса предыдущей в native queue.
/// Исходящая партия удерживается до подтверждения writer'ом. Внешняя система
/// должна сообщать об освобождении места в очереди и инициировать flush.
/// Не Sendable: все методы, включая закрытие, вызывать в одном контексте.
public final class MYCODEXPacketFlowCoordinator {
    private let bridge: MYCODEXPacketBridge
    private var pendingIngress: [MYCODEXPacket] = []
    private var ingressIndex: Int = 0
    private var pendingEgress: [MYCODEXPacket] = []
    private var closed = false

    public init(bridge: MYCODEXPacketBridge) {
        self.bridge = bridge
    }

    public var hasPendingIngress: Bool { ingressIndex < pendingIngress.count }
    public var hasPendingEgress: Bool { !pendingEgress.isEmpty }
    public var isClosed: Bool { closed }

    /// Сверяет значения AF_INET/AF_INET6 с IP-заголовками. Не копирует Data.
    public static func classify(_ data: [Data], protocolFamilies: [Int32]) throws -> [MYCODEXPacket] {
        guard data.count == protocolFamilies.count else { throw MYCODEXPacketFlowError.invalidReadBatch }
        return try zip(data, protocolFamilies).map { bytes, family in
            let packet = try MYCODEXPacket(data: bytes)
            guard packet.kind.protocolFamily == family else {
                throw MYCODEXPacketFlowError.protocolFamilyMismatch
            }
            return packet
        }
    }

    /// Принимает одну партию от системного TUN. false означает backpressure:
    /// партия сохранена внутри и должна быть передана через resumeIncoming().
    @discardableResult
    public func stageIncoming(_ packets: [MYCODEXPacket]) throws -> Bool {
        guard !closed else { throw MYCODEXPacketFlowError.closed }
        guard !hasPendingIngress else { throw MYCODEXPacketFlowError.pendingReadBatch }
        guard packets.allSatisfy({ $0.data.count <= bridge.maximumQueueBytes }) else {
            throw MYCODEXPacketFlowError.packetExceedsQueueCapacity
        }
        pendingIngress = packets
        ingressIndex = 0
        return try resumeIncoming()
    }

    /// Повторять после того, как потребитель освободил место в очереди toCore.
    /// true означает, что можно снова вызывать NEPacketTunnelFlow.readPackets.
    @discardableResult
    public func resumeIncoming() throws -> Bool {
        guard !closed else { throw MYCODEXPacketFlowError.closed }
        while ingressIndex < pendingIngress.count {
            if try !bridge.enqueue(pendingIngress[ingressIndex], direction: .toCore) {
                return false
            }
            ingressIndex += 1
        }
        pendingIngress.removeAll(keepingCapacity: false)
        ingressIndex = 0
        return true
    }

    /// Отправляет не более maxBatch пакетов из toSystem одним системным write.
    /// false означает, что writer не принял партию; все её пакеты сохраняются
    /// для повторной попытки. Не даёт гарантию exactly-once на стороне ОС.
    @discardableResult
    public func flushOutgoing(maxBatch: Int = 32,
                              writer: ([MYCODEXPacket]) -> Bool) throws -> Bool {
        guard !closed else { throw MYCODEXPacketFlowError.closed }
        guard (1...128).contains(maxBatch) else { throw MYCODEXPacketFlowError.invalidBatchLimit }
        if pendingEgress.isEmpty {
            for _ in 0..<maxBatch {
                guard let packet = try bridge.dequeue(direction: .toSystem) else { break }
                pendingEgress.append(packet)
            }
        }
        guard !pendingEgress.isEmpty else { return true }
        guard writer(pendingEgress) else { return false }
        pendingEgress.removeAll(keepingCapacity: false)
        return true
    }

    /// Вызывается только после прекращения системных read/write callback'ов.
    public func close() throws {
        guard !closed else { return }
        closed = true
        pendingIngress.removeAll()
        pendingEgress.removeAll()
        try bridge.close()
    }
}
