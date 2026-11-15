import Foundation
import COpenVPNBridge

func require(_ ok: @autoclosure () -> Bool, _ text: String) {
    if !ok() { fatalError(text) }
}

require(mycodex_bridge_core_linked() == 1, "Native OpenVPN Core is absent")
require(mycodex_external_tun_factory_compiled() == 1, "ExternalTun is absent")
print("SWIFT_NATIVE_SETTINGS_ACK_CORE_LINKED=1")

let client = try OpenVPNClient()
let profile = try OpenVPNProfile(ovpnText: "client\nremote example.invalid 1194\nproto udp\n")
try client.configure(profile)
let queue = try MYCODEXPacketBridge(maxPackets: 8, maxBytes: 8192)
let socket = try MYCODEXTunSocketTransport(bridge: queue)
try client.attachTunSocket(socket)
print("SWIFT_NATIVE_SETTINGS_ACK_FD_STAGED=1")

do {
    try client.acknowledgeTunSettings(generation: 44, applied: true)
    fatalError("ACK without pending generation was accepted")
} catch MYCODEXTunFDAcknowledgementError.invalidState {
    print("SWIFT_NATIVE_SETTINGS_ACK_STALE_REJECTED=1")
}

try client.cancelTunHandoff()
try client.cancelTunHandoff()
do {
    try client.attachTunSocket(socket)
    fatalError("Cancelled TUN accepted FD attachment")
} catch MYCODEXTunFDAcknowledgementError.invalidState {
    print("SWIFT_NATIVE_SETTINGS_ACK_CANCELLED=1")
}

require(!OpenVPNClient.isTunnelAdapterAvailable, "Unverified VPN adapter enabled")
do {
    try client.start()
    fatalError("Core connection unexpectedly enabled")
} catch OpenVPNClientError.tunnelUnavailable {
    print("SWIFT_NATIVE_SETTINGS_ACK_START_GUARDED=1")
}
try socket.close()
try queue.close()
print("MYCODEX_NATIVE_SETTINGS_ACK_PROBE_PASSED")
