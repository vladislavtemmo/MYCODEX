import XCTest
@testable import MYCODEX

final class OpenVPNNativeValidationTests: XCTestCase {
    func testCoreUnavailableInDefaultSwiftPMBuild() throws {
        let profile = try OpenVPNProfile(ovpnText: "client\nremote example.invalid 1194\nproto udp\n")
        XCTAssertFalse(OpenVPNNativeBridge.isOpenVPNCoreLinked)
        XCTAssertEqual(OpenVPNNativeBridge.validateProfile(profile), .coreUnavailable)
    }

    func testInvalidProfileContainerStillRejectsEmptyInput() {
        XCTAssertThrowsError(try OpenVPNProfile(ovpnText: ""))
        XCTAssertThrowsError(try OpenVPNProfile(ovpnText: "client\0"))
    }
}