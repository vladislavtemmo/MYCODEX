import Foundation
import COpenVPNBridge
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

func require(_ condition: @autoclosure () -> Bool, _ error: String) {
    if !condition() { fatalError(error) }
}

let bridge = try MYCODEXPacketBridge(maxPackets: 1, maxBytes: 1024)
let transport = try MYCODEXTunSocketTransport(bridge: bridge)
let coreFD = try transport.duplicateCoreFileDescriptor()
defer { _ = close(coreFD) }
let ipv4 = try MYCODEXPacket(data: Data([0x45] + Array(repeating: 0xAB, count: 19)))
let ipv6 = try MYCODEXPacket(data: Data([0x60] + Array(repeating: 0xBC, count: 39)))

// System -> Core
let accepted = try bridge.enqueue(ipv4, direction: .toCore)
require(accepted, "ingress enqueue failed")
let first = try transport.pump(maxPerDirection: 2)
require(first.intoCore == 1 && first.intoSystem == 0, "system -> Core pump failed")
var received = [UInt8](repeating: 0, count: 128)
let n = received.withUnsafeMutableBufferPointer { buffer in
    recv(coreFD, buffer.baseAddress, buffer.count, Int32(MSG_DONTWAIT))
}
require(n == ipv4.data.count, "datagram length changed")
require(Data(received.prefix(n)) == ipv4.data, "IP bytes changed")
print("SWIFT_SOCKETPAIR_TO_CORE=1")

// Core -> system (two datagrams; queue holds one, pump holds the second).
for packet in [ipv4, ipv6] {
    let sent = packet.data.withUnsafeBytes { raw in
        send(coreFD, raw.baseAddress, raw.count, Int32(MSG_DONTWAIT))
    }
    require(sent == packet.data.count, "core-side send failed")
}
let second = try transport.pump(maxPerDirection: 8)
require(second.intoSystem == 1, "initial core -> system packet missing")
let receivedFirst = try bridge.dequeue(direction: .toSystem)
require(receivedFirst == ipv4, "first packet mutated")
let third = try transport.pump(maxPerDirection: 8)
require(third.intoSystem == 1, "pending packet was lost on backpressure")
let receivedSecond = try bridge.dequeue(direction: .toSystem)
require(receivedSecond == ipv6, "second packet mutated")
print("SWIFT_SOCKETPAIR_TO_SYSTEM=1")
print("SWIFT_SOCKETPAIR_BACKPRESSURE=1")

let idle = try transport.pump()
require(idle == MYCODEXTunSocketProgress(intoCore: 0, intoSystem: 0), "idle pump not idle")
print("SWIFT_SOCKETPAIR_IDLE=1")
try transport.close()
try transport.close()
do {
    _ = try transport.pump()
    fatalError("closed transport allowed pump")
} catch MYCODEXTunSocketError.closed {
    print("SWIFT_SOCKETPAIR_CLOSE=1")
}
require(mycodex_client_tunnel_available() == 0, "unexpected VPN activation")
print("SWIFT_SOCKETPAIR_VPN_GUARDED=1")
print("MYCODEX_TUN_SOCKET_PROBE_PASSED")
