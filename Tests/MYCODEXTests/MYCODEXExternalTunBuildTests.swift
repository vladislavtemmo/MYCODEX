import XCTest
import COpenVPNBridge
@testable import MYCODEX

final class MYCODEXExternalTunBuildTests: XCTestCase {
    func testSwiftPMFallbackNeverAdvertisesExternalTun() {
        // Standard SwiftPM builds do not link the native OpenVPN Core or
        // compile its experimental ExternalTun::Factory integration.
        XCTAssertEqual(mycodex_external_tun_factory_compiled(), 0)
        XCTAssertFalse(OpenVPNClient.isTunnelAdapterAvailable)
    }
}
