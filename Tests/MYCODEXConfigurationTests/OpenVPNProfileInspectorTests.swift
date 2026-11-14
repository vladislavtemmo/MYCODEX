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

extension OpenVPNProfileInspectorTests {
    func testQuotedHostAndProtoAreParsed() throws {
        let profile = try OpenVPNProfile(ovpnText: """
        client
        proto "tcp-client"
        remote 'vpn.example.org' "443" # remote ignored.example 53
        """)
        let endpoints = try OpenVPNProfileInspector.remoteEndpoints(in: profile)
        XCTAssertEqual(endpoints.count, 1)
        XCTAssertEqual(endpoints[0].hostname, "vpn.example.org")
        XCTAssertEqual(endpoints[0].port, 443)
        XCTAssertEqual(endpoints[0].transport, .tcp)
    }

    func testCommentMarkersInInlineCertificateAreIgnored() throws {
        let profile = try OpenVPNProfile(ovpnText: """
        <tls-crypt>
        # remote fake.example.org 1194
        remote fake.example.net 555
        </tls-crypt>
        remote vpn.example.org 1194 ; comment
        """)
        XCTAssertEqual(try OpenVPNProfileInspector.remoteEndpoints(in: profile).map(\.hostname), ["vpn.example.org"])
    }

    func testMalformedQuotedDirectiveFailsWithoutExposingSecret() throws {
        let profile = try OpenVPNProfile(ovpnText: "remote 'vpn.example.org 1194")
        XCTAssertThrowsError(try OpenVPNProfileInspector.remoteEndpoints(in: profile)) { error in
            XCTAssertEqual(error as? OpenVPNInspectionError, .malformedDirective(line: 1))
            XCTAssertFalse(String(describing: error).contains("vpn.example.org"))
        }
    }

    func testUnknownClosingBlockFails() throws {
        let profile = try OpenVPNProfile(ovpnText: "</cert>\nremote vpn.example.org 1194")
        XCTAssertThrowsError(try OpenVPNProfileInspector.remoteEndpoints(in: profile)) { error in
            XCTAssertEqual(error as? OpenVPNInspectionError, .invalidBlock(line: 1))
        }
    }

    func testDoubleQuotedHostnameAndInlineComment() throws {
        let profile = try OpenVPNProfile(ovpnText: "remote \"vpn.example.org\" 443 tcp-client ; disabled endpoint follows")
        let endpoints = try OpenVPNProfileInspector.remoteEndpoints(in: profile)
        XCTAssertEqual(endpoints.map(\.hostname), ["vpn.example.org"])
    }
}
