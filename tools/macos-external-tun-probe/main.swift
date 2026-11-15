import Foundation
import COpenVPNBridge

guard mycodex_bridge_core_linked() == 1 else {
    fatalError("OpenVPN 3 Core not linked")
}
print("SWIFT_EXTERNAL_TUN_CORE_LINKED=1")
guard mycodex_external_tun_factory_compiled() == 1 else {
    fatalError("ExternalTun::Factory was not compiled into Core")
}
print("SWIFT_EXTERNAL_TUN_FACTORY_SELECTED=1")
guard let handle = mycodex_client_create() else {
    fatalError("Unable to instantiate OpenVPNClient")
}
defer { mycodex_client_destroy(handle) }
let ovpn = "client\nremote example.invalid 1194\nproto udp\n"
let configured = ovpn.withCString { pointer in
    mycodex_client_configure(handle, pointer, ovpn.utf8.count)
}
guard configured == 0 else { fatalError("Configuration rejected: \(configured)") }
#if MYCODEX_EXTERNAL_TUN_FACTORY_TESTING
let factory = mycodex_external_tun_factory_test_fixture(handle)
guard factory == 0 else { fatalError("Native ExternalTun factory fixture failed: \(factory)") }
print("SWIFT_EXTERNAL_TUN_FACTORY_CREATED=1")
#else
fatalError("Test-only factory fixture not enabled")
#endif
guard mycodex_client_tunnel_available() == 0 else {
    fatalError("ExternalTun factory was mistakenly reported as a live VPN")
}
guard mycodex_client_start(handle) == -6 else {
    fatalError("connect() was allowed without a PacketFlow transport")
}
print("SWIFT_EXTERNAL_TUN_START_GUARDED=1")
print("MYCODEX_EXTERNAL_TUN_FACTORY_PROBE_PASSED")
