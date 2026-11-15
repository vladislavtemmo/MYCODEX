import XCTest
@testable import MYCODEX

final class OpenVPNClientPreparationTests: XCTestCase {
    func testNativeRunStateDoesNotImplyVPNConnectivity() {
        XCTAssertEqual(OpenVPNClientRunState.configured.rawValue, 1)
        XCTAssertEqual(OpenVPNClientRunState.running.rawValue, 3)
        XCTAssertEqual(OpenVPNClientRunState.failed.rawValue, 6)
        XCTAssertFalse(OpenVPNClient.isTunnelAdapterAvailable)
    }

    func testNativeErrorSurfaceIsExplicit() {
        XCTAssertNotEqual(OpenVPNClientError.invalidState, .credentialsRejected)
        let e = OpenVPNClientEvent(name: "CONNECTED", isError: false, isFatal: false)
        XCTAssertEqual(e.name, "CONNECTED")
        XCTAssertFalse(e.isError)
        XCTAssertFalse(e.isFatal)
    }

    func testUnavailableCoreDoesNotPretendClientIsUsable() {
        XCTAssertFalse(OpenVPNNativeBridge.isOpenVPNCoreLinked)
        XCTAssertThrowsError(try OpenVPNClient()) { error in
            XCTAssertEqual(error as? OpenVPNClientError, .coreUnavailable)
        }
    }
}
