import Foundation
import COpenVPNBridge

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
require(mycodex_bridge_core_linked() == 1, "OpenVPN Core absent")
require(mycodex_external_tun_factory_compiled() == 1, "ExternalTun factory absent")
print("SWIFT_TUN_FD_EXTERNAL_FACTORY=1")

let profile = "client\nremote example.invalid 1194\nproto udp\n"
guard let handle = mycodex_client_create() else { fatalError("No client") }
defer { mycodex_client_destroy(handle) }
let configured = profile.withCString { mycodex_client_configure(handle, $0, profile.utf8.count) }
require(configured == 0, "Client configure failed: \(configured)")

#if MYCODEX_TUN_FD_TESTING
require(mycodex_client_tun_fd_test_fixture(handle) == 0, "TunBuilderBase handoff fixture failed")
print("SWIFT_TUN_FD_BUILDER_ACK=1")
print("SWIFT_TUN_FD_DATAGRAM_ROUNDTRIP=1")
print("SWIFT_TUN_FD_STALE_ACK_REJECTED=1")
#else
fatalError("Test-only native fixture is missing")
#endif

require(mycodex_client_tunnel_available() == 0, "VPN incorrectly available")
require(mycodex_client_start(handle) == -6, "Core incorrectly allowed to connect")
print("SWIFT_TUN_FD_VPN_STILL_GUARDED=1")
print("MYCODEX_TUN_FD_HANDOFF_PROBE_PASSED")
