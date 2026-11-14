import XCTest
import MYCODEX
@testable import MYCODEXConfiguration

final class OpenVPNProfileInspectorTests: XCTestCase {
    func testExtractsMultipleRemotesAndTransport() throws {
        let profile = try OpenVPNProfile(ovpnText: """
        client
        proto tcp-client
        remote nl.example.org 443
        remote us.example.org 1194 udp
        """)
        let endpoints = try OpenVPNProfileInspector.remoteEndpoints(in: profile)
        XCTAssertEqual(endpoints.count, 2)
        XCTAssertEqual(endpoints[0].transport, .tcp)
        XCTAssertEqual(endpoints[1].transport, .udp)
        XCTAssertEqual(endpoints[1].port, 1194)
    }

    func testSkipsEmbeddedCertificateAndComments() throws {
        let profile = try OpenVPNProfile(ovpnText: """
        # remote not-a-server 1234
        <cert>
        remote fake.example.org 443
        </cert>
        remote real.example.org 1194 # comment
        """)
        let endpoints = try OpenVPNProfileInspector.remoteEndpoints(in: profile)
        XCTAssertEqual(endpoints.map(\.hostname), ["real.example.org"])
    }

    func testRejectsBadPortAndBadProto() throws {
        let badPort = try OpenVPNProfile(ovpnText: "remote example.org 99999")
        XCTAssertThrowsError(try OpenVPNProfileInspector.remoteEndpoints(in: badPort))
        let badProto = try OpenVPNProfile(ovpnText: "proto tcp-server\nremote example.org 443")
        XCTAssertThrowsError(try OpenVPNProfileInspector.remoteEndpoints(in: badProto))
    }

    func testRejectsMissingTopLevelRemote() throws {
        let profile = try OpenVPNProfile(ovpnText: "client\nproto udp")
        XCTAssertThrowsError(try OpenVPNProfileInspector.remoteEndpoints(in: profile))
    }
}
