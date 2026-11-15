import Foundation
import COpenVPNBridge
import Darwin

func require(_ value: Bool, _ message: String) {
    if !value { fatalError(message) }
}

let queue = try MYCODEXPacketBridge(maxPackets: 2, maxBytes: 1024)
let socket = try MYCODEXTunSocketTransport(bridge: queue)
let core = try socket.duplicateCoreFileDescriptor()
let monitor = try socket.duplicateMonitorFileDescriptor()
defer { _ = close(core); _ = close(monitor) }

require(mycodex_bridge_core_linked() == 1, "OpenVPN3 Core not linked")
print("SWIFT_PACKET_WAKE_CORE_LINKED=1")

var event = pollfd(fd: monitor, events: Int16(POLLIN), revents: 0)
require(poll(&event, 1, 0) == 0, "unexpected initial read readiness")
let packet = try MYCODEXPacket(data: Data([0x45] + Array(repeating: 0x52, count: 19)))
let n = packet.data.withUnsafeBytes { send(core, $0.baseAddress, $0.count, Int32(MSG_DONTWAIT)) }
require(n == packet.data.count, "core send failed")
require(poll(&event, 1, 100) == 1 && (event.revents & Int16(POLLIN)) != 0,
        "native pump descriptor did not signal readable")
print("SWIFT_PACKET_WAKE_READ_READY=1")
require(try socket.pump().intoSystem == 1, "readiness did not deliver packet")
require(try queue.dequeue(direction: .toSystem) == packet, "packet changed")
require(poll(&event, 1, 0) == 0, "readiness not cleared after drain")
print("SWIFT_PACKET_WAKE_NO_CONSUMPTION=1")

require(try !socket.hasPendingCoreWrite(), "unexpected pending datagram")
require(try queue.enqueue(packet, direction: .toCore), "failed to enqueue ingress")
require(try socket.pump().intoCore == 1, "ingress not pumped")
var output = [UInt8](repeating: 0, count: 64)
let r = output.withUnsafeMutableBufferPointer { recv(core, $0.baseAddress, $0.count, Int32(MSG_DONTWAIT)) }
require(r == packet.data.count && Data(output.prefix(r)) == packet.data, "ingress corrupted")
print("SWIFT_PACKET_WAKE_WRITE_READY=1")

try socket.close()
do {
    _ = try socket.duplicateMonitorFileDescriptor()
    fatalError("closed socket exposed readiness FD")
} catch MYCODEXTunSocketError.closed { }
print("SWIFT_PACKET_WAKE_CLOSE=1")
require(mycodex_client_tunnel_available() == 0, "VPN guard unexpectedly disabled")
print("SWIFT_PACKET_WAKE_VPN_GUARDED=1")
print("MYCODEX_PACKET_WAKEUP_PROBE_PASSED")
