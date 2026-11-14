import XCTest
@testable import MYCODEX

final class OpenVPNFoundationTests: XCTestCase {
    func testEndpointAndTransport() throws {
        let endpoint = try OpenVPNEndpoint(hostname: "vpn.example.org", port: 443, transport: .tcp)
        XCTAssertEqual(endpoint.hostname, "vpn.example.org")
        XCTAssertEqual(endpoint.port, 443)
        XCTAssertEqual(endpoint.transport, .tcp)
    }

    func testInvalidEndpointRejected() {
        XCTAssertThrowsError(try OpenVPNEndpoint(hostname: "", port: 1194))
        XCTAssertThrowsError(try OpenVPNEndpoint(hostname: "bad host", port: 1194))
        XCTAssertThrowsError(try OpenVPNEndpoint(hostname: "ok.example", port: 0))
    }

    func testProfileValidationAndRedaction() throws {
        let profile = try OpenVPNProfile(ovpnText: "client\nremote vpn.example.org 1194")
        XCTAssertEqual(profile.description, "OpenVPNProfile(<redacted>)")
        XCTAssertThrowsError(try OpenVPNProfile(ovpnText: " \n"))
        XCTAssertThrowsError(try OpenVPNProfile(ovpnText: "client\0"))
        XCTAssertThrowsError(try OpenVPNProfile(ovpnText: String(repeating: "x", count: OpenVPNProfile.maximumByteCount + 1)))
    }

    func testLifecycleStatesAreExplicit() {
        XCTAssertNotEqual(OpenVPNConnectionState.connecting, .connected)
        XCTAssertEqual(OpenVPNConnectionState.reconnecting.rawValue, "reconnecting")
    }
}
