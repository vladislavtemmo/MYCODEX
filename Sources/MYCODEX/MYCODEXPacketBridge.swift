import Foundation
import COpenVPNBridge

/// Packet flow direction. This is a staging queue, not a connected tunnel.
public enum MYCODEXPacketDirection: Int32, Sendable {
    case toCore = 1
    case toSystem = 2
}

public struct MYCODEXPacket: Sendable, Equatable {
    public let data: Data
    public let kind: MYCODEXIPPacketKind

    public init(data: Data) throws {
        guard data.count <= Int(MYCODEX_PACKET_MAX_LENGTH),
              let kind = MYCODEXIPPacketKind.detect(data) else {
            throw MYCODEXPacketBridgeError.invalidPacket
        }
        self.data = data
        self.kind = kind
    }
}

public enum MYCODEXPacketBridgeError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidPacket
    case closed
    case nativeFailure
    case bufferTooSmall
    case unexpectedStatus(Int32)
}

public struct MYCODEXPacketQueueStats: Sendable, Equatable {
    public let packets: UInt32
    public let bytes: Int
}

/// Bounded, mutex-protected native duplex queue for packet staging.
///
/// `true` from enqueue means accepted; `false` means backpressure and the
/// caller still owns the packet and MUST retry or stop reading upstream.
/// No packets are silently dropped on saturation.
///
/// This intentionally does NOT implement OpenVPN TunBuilderBase, connect to
/// NEPacketTunnelFlow, or create a VPN. Object is non-Sendable because native
/// `destroy` must never race with any operation; caller serializes lifetime.
public final class MYCODEXPacketBridge {
    private let handle: OpaquePointer

    public init(maxPackets: UInt32 = 64, maxBytes: Int = 1_048_576) throws {
        guard maxPackets > 0 && maxPackets <= 1024,
              maxBytes >= 1024 && maxBytes <= 8 * 1_048_576,
              let handle = mycodex_packet_bridge_create(maxPackets, maxBytes) else {
            throw MYCODEXPacketBridgeError.invalidConfiguration
        }
        self.handle = handle
    }

    deinit { mycodex_packet_bridge_destroy(handle) }

    @discardableResult
    public func enqueue(_ packet: MYCODEXPacket, direction: MYCODEXPacketDirection) throws -> Bool {
        let family: UInt32 = packet.kind == .ipv4 ? 4 : 6
        let code: Int32 = packet.data.withUnsafeBytes { raw in
            mycodex_packet_bridge_push(handle, direction.rawValue,
                                      raw.bindMemory(to: UInt8.self).baseAddress,
                                      raw.count, family)
        }
        switch code {
        case 1: return true
        case 0: return false
        case -2: throw MYCODEXPacketBridgeError.invalidPacket
        case -3: throw MYCODEXPacketBridgeError.closed
        case -1, -4: throw MYCODEXPacketBridgeError.nativeFailure
        default: throw MYCODEXPacketBridgeError.unexpectedStatus(code)
        }
    }

    /// Removes at most one packet, or returns nil if the queue is empty.
    /// The native read copies bytes to a caller-owned Data buffer once.
    public func dequeue(direction: MYCODEXPacketDirection) throws -> MYCODEXPacket? {
        var data = Data(count: Int(MYCODEX_PACKET_MAX_LENGTH))
        var actualLength: Int = 0
        var family: UInt32 = 0
        let code: Int32 = data.withUnsafeMutableBytes { raw in
            mycodex_packet_bridge_pop(handle, direction.rawValue,
                                     raw.bindMemory(to: UInt8.self).baseAddress,
                                     raw.count, &actualLength, &family)
        }
        switch code {
        case 0: return nil
        case 1:
            guard actualLength <= data.count, family == 4 || family == 6 else {
                throw MYCODEXPacketBridgeError.nativeFailure
            }
            data.removeSubrange(actualLength..<data.count)
            let packet = try MYCODEXPacket(data: data)
            guard (packet.kind == .ipv4 ? 4 : 6) == family else {
                throw MYCODEXPacketBridgeError.nativeFailure
            }
            return packet
        case -3: throw MYCODEXPacketBridgeError.closed
        case -5: throw MYCODEXPacketBridgeError.bufferTooSmall
        case -1, -4: throw MYCODEXPacketBridgeError.nativeFailure
        default: throw MYCODEXPacketBridgeError.unexpectedStatus(code)
        }
    }

    public func statistics(direction: MYCODEXPacketDirection) throws -> MYCODEXPacketQueueStats {
        var packets: UInt32 = 0
        var bytes: Int = 0
        let code = mycodex_packet_bridge_stats(handle, direction.rawValue, &packets, &bytes)
        guard code == 0 else { throw MYCODEXPacketBridgeError.nativeFailure }
        return MYCODEXPacketQueueStats(packets: packets, bytes: bytes)
    }

    /// Prevents further enqueues; already-queued packets remain drainable.
    public func close() throws {
        let code = mycodex_packet_bridge_close(handle)
        guard code == 0 else { throw MYCODEXPacketBridgeError.nativeFailure }
    }
}
