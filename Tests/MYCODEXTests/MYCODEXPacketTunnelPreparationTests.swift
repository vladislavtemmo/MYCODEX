import XCTest
@testable import MYCODEX

final class MYCODEXPacketTunnelPreparationTests: XCTestCase {
    func testSettingsAcknowledgementDoesNotMeanConnected() throws {
        let machine = MYCODEXPacketTunnelPreparation()
        let token = try machine.beginSettingsApplication()
        XCTAssertEqual(machine.state, .applyingSettings)
        try machine.settingsDidComplete(token: token, accepted: true)
        XCTAssertEqual(machine.state, .settingsApplied)
        XCTAssertThrowsError(try machine.checkNativeTransport(isAvailable: false)) {
            XCTAssertEqual($0 as? MYCODEXPacketTunnelPreparationError, .nativeTransportUnavailable)
        }
        XCTAssertEqual(machine.state, .failed)
    }

    func testSettingsErrorDoesNotAdvanceState() throws {
        let machine = MYCODEXPacketTunnelPreparation()
        let token = try machine.beginSettingsApplication()
        XCTAssertThrowsError(try machine.settingsDidComplete(token: token, accepted: false)) {
            XCTAssertEqual($0 as? MYCODEXPacketTunnelPreparationError, .networkSettingsRejected)
        }
        XCTAssertEqual(machine.state, .failed)
        XCTAssertThrowsError(try machine.beginSettingsApplication())
    }

    func testCancelInvalidatesCallbackAndCannotRestart() throws {
        let machine = MYCODEXPacketTunnelPreparation()
        let token = try machine.beginSettingsApplication()
        machine.stop()
        machine.stop()
        XCTAssertEqual(machine.state, .stopped)
        XCTAssertThrowsError(try machine.settingsDidComplete(token: token, accepted: true)) {
            XCTAssertEqual($0 as? MYCODEXPacketTunnelPreparationError, .staleCallback)
        }
        XCTAssertEqual(machine.state, .stopped)
        XCTAssertThrowsError(try machine.beginSettingsApplication())
    }

    func testWrongTokenNeverConfirmsSettings() throws {
        let machine = MYCODEXPacketTunnelPreparation()
        let token = try machine.beginSettingsApplication()
        XCTAssertThrowsError(try machine.settingsDidComplete(token: token &+ 1, accepted: true))
        XCTAssertEqual(machine.state, .applyingSettings)
        try machine.settingsDidComplete(token: token, accepted: true)
        XCTAssertEqual(machine.state, .settingsApplied)
    }

    func testNativeCapabilityIsNotVPNConnectionEvent() throws {
        let machine = MYCODEXPacketTunnelPreparation()
        XCTAssertThrowsError(try machine.checkNativeTransport(isAvailable: true))
        let token = try machine.beginSettingsApplication()
        try machine.settingsDidComplete(token: token, accepted: true)
        try machine.checkNativeTransport(isAvailable: true)
        XCTAssertEqual(machine.state, .coreTransportReady)
        XCTAssertThrowsError(try machine.checkNativeTransport(isAvailable: true))
    }
}
