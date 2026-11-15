import Foundation
import COpenVPNBridge

let profile = try OpenVPNProfile(ovpnText: "client\nremote example.invalid 1194\nproto udp\n")
let client = try OpenVPNClient()
try client.configure(profile)

do {
    _ = try client.capturedTunnelConfiguration()
    fatalError("A snapshot was published before TunBuilder callbacks")
} catch MYCODEXTunCaptureError.incompleteCapture {
    print("SWIFT_TUN_NO_PREMATURE_SNAPSHOT=1")
}

#if MYCODEX_TUN_CAPTURE_TESTING
let status = mycodex_client_tun_test_fixture(client.handleForTunCapture)
guard status == 0 else { fatalError("Native test callback fixture failed: \(status)") }
let config = try client.capturedTunnelConfiguration()
guard config.remoteAddress == "198.51.100.10",
      config.ipv4Addresses.first?.address == "10.8.0.2",
      config.ipv4Addresses.first?.subnetMask == "255.255.255.0",
      config.ipv6Addresses.first?.prefixLength == 64,
      config.includedIPv4Routes.first?.subnetMask == "255.240.0.0",
      config.excludedIPv4Routes.first?.subnetMask == "255.255.0.0",
      config.routeAllIPv4, config.routeAllIPv6,
      config.dnsServers == ["1.1.1.1"],
      config.mtu == 1400 else { fatalError("TunBuilder snapshot assembly mismatch") }
print("SWIFT_TUN_SETTINGS_CAPTURED=1")
print("SWIFT_TUN_IPV4_IPV6=1")
print("SWIFT_TUN_DNS_ROUTES_MTU=1")
#else
fatalError("Native test flag missing")
#endif

guard OpenVPNClient.isTunnelAdapterAvailable == false else {
    fatalError("Null-TUN must never be advertised as a VPN tunnel")
}
do {
    try client.start()
    fatalError("connect() was unexpectedly enabled")
} catch OpenVPNClientError.tunnelUnavailable {
    print("SWIFT_TUN_STILL_UNAVAILABLE=1")
}
print("MYCODEX_TUN_CAPTURE_PASSED")
