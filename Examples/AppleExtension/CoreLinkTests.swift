import XCTest
import MYCODEX

final class CoreLinkTests: XCTestCase {
    func testRealCoreConfigurationWithoutStartingVPN() throws {
        XCTAssertTrue(OpenVPNNativeBridge.isOpenVPNCoreLinked)
        XCTAssertTrue(OpenVPNNativeBridge.isExternalTunFactoryCompiled)
        let client = try OpenVPNClient()
        let profile = try OpenVPNProfile(ovpnText: "client\nremote example.invalid 1194\nproto udp\n")
        try client.configure(profile)
        XCTAssertEqual(try client.runState, .configured)
        XCTAssertFalse(OpenVPNClient.isTunnelAdapterAvailable)
        XCTAssertThrowsError(try client.start()) { error in
            XCTAssertEqual(error as? OpenVPNClientError, .tunnelUnavailable)
        }
    }
}
