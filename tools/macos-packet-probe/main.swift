import Foundation

let queue = try MYCODEXPacketBridge(maxPackets: 1, maxBytes: 1024)
let packet = try MYCODEXPacket(data: Data([0x45] + Array(repeating: 0, count: 19)))
guard try queue.enqueue(packet, direction: .toCore) else { fatalError("First packet rejected") }
print("SWIFT_PACKET_INGRESS=1")
guard try !queue.enqueue(packet, direction: .toCore) else { fatalError("Queue overflow was accepted") }
print("SWIFT_PACKET_BACKPRESSURE=1")
guard try queue.statistics(direction: .toCore).packets == 1 else { fatalError("Incorrect stats") }
guard try queue.dequeue(direction: .toCore) == packet else { fatalError("Packet bytes changed") }
print("SWIFT_PACKET_ROUNDTRIP=1")
guard try queue.enqueue(packet, direction: .toSystem) else { fatalError("Egress rejected") }
guard try queue.dequeue(direction: .toSystem) == packet else { fatalError("Egress bytes changed") }
print("SWIFT_PACKET_EGRESS=1")
try queue.close()
do {
    _ = try queue.enqueue(packet, direction: .toCore)
    fatalError("Closed queue accepted a packet")
} catch MYCODEXPacketBridgeError.closed {
    print("SWIFT_PACKET_CLOSE=1")
}
print("MYCODEX_PACKET_BRIDGE_PASSED")
