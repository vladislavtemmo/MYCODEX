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

extension OpenVPNProfileInspectorTests {
    func testConnectionBlockTransportOverridesGlobal() throws {
        let profile = try OpenVPNProfile(ovpnText: """
        client
        proto udp
        remote nl.example.com 1194
        <connection>
        remote backup.example.com 443
        proto tcp-client
        </connection>
        remote fr.example.com 53
        """)
        let endpoints = try OpenVPNProfileInspector.remoteEndpoints(in: profile)
        XCTAssertEqual(endpoints.map(\.hostname), [
            "nl.example.com", "backup.example.com", "fr.example.com"
        ])
        XCTAssertEqual(endpoints.map(\.transport), [.udp, .tcp, .udp])
    }

    func testRemoteWithoutPortWithTransport() throws {
        let profile = try OpenVPNProfile(ovpnText: "remote example.com tcp-client")
        let endpoints = try OpenVPNProfileInspector.remoteEndpoints(in: profile)
        XCTAssertEqual(endpoints.first?.port, 1194)
        XCTAssertEqual(endpoints.first?.transport, .tcp)
    }

    func testCertificatesNestedInsideConnectionNotParsed() throws {
        let profile = try OpenVPNProfile(ovpnText: """
        <connection>
        <cert>
        remote fake.example.org 1000
        </cert>
        remote valid.example.org 443 tcp-client
        </connection>
        """)
        let endpoints = try OpenVPNProfileInspector.remoteEndpoints(in: profile)
        XCTAssertEqual(endpoints.map(\.hostname), ["valid.example.org"])
    }

    func testMalformedBlockFailsExplicitly() throws {
        let profile = try OpenVPNProfile(ovpnText: """
        <connection>
        remote valid.example.org 443
        """)
        XCTAssertThrowsError(try OpenVPNProfileInspector.remoteEndpoints(in: profile)) { error in
            XCTAssertEqual(error as? OpenVPNInspectionError, .unclosedBlock)
        }
        let extraClosing = try OpenVPNProfile(ovpnText: "</connection>\nremote valid.example.org")
        XCTAssertThrowsError(try OpenVPNProfileInspector.remoteEndpoints(in: extraClosing))
    }
}
