import XCTest
@testable import MYCODEX

final class OpenVPNClientPreparationTests: XCTestCase {
    func testUnavailableCoreDoesNotPretendClientIsUsable() {
        XCTAssertFalse(OpenVPNNativeBridge.isOpenVPNCoreLinked)
        XCTAssertThrowsError(try OpenVPNClient()) { error in
            XCTAssertEqual(error as? OpenVPNClientError, .coreUnavailable)
        }
    }
}
