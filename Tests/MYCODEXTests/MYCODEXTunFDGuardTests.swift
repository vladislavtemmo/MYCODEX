import XCTest
import COpenVPNBridge

final class MYCODEXTunFDGuardTests: XCTestCase {
    func testNullHandleCannotStartHandoff() {
        XCTAssertEqual(mycodex_client_tun_attach_fd(nil, 0), -1)
        var generation: UInt64 = 0
        XCTAssertEqual(mycodex_client_tun_wait_pending(nil, 0, &generation), -1)
        XCTAssertEqual(mycodex_client_tun_ack_settings(nil, 1, 1), -1)
        XCTAssertEqual(mycodex_client_tun_cancel(nil), -1)
    }

    func testFallbackCannotAcceptSocketHandoff() {
        // Fallback SwiftPM never has a true Core/TUN adapter. In a native Core
        // build, use the dedicated macOS test fixture instead.
        if mycodex_bridge_core_linked() == 0 {
            XCTAssertEqual(mycodex_client_tunnel_available(), 0)
            XCTAssertEqual(mycodex_client_tun_attach_fd(nil, -1), -1)
        }
    }
}
