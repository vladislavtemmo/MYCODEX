import XCTest
@testable import MYCODEX

final class MYCODEXTunSettingsCaptureTests: XCTestCase {
    private func sample() -> [MYCODEXTunSetting] {
        [
            .init(kind: .remote, value: "198.51.100.10"),
            .init(kind: .ipv4Address, value: "10.8.0.2", prefix: 24),
            .init(kind: .ipv6Address, value: "2001:db8::2", prefix: 64),
            .init(kind: .ipv4Route, value: "172.16.0.0", prefix: 12),
            .init(kind: .ipv4Exclude, value: "192.168.0.0", prefix: 16),
            .init(kind: .ipv4DefaultRoute, value: ""),
            .init(kind: .ipv6DefaultRoute, value: ""),
            .init(kind: .dnsAddress, value: "1.1.1.1"),
            .init(kind: .mtu, value: "", prefix: 1400)
        ]
    }

    func testCapturedSettingsTranslateToAppleNetworkModel() throws {
        let config = try MYCODEXTunSettingsAssembler.configuration(from: sample())
        XCTAssertEqual(config.remoteAddress, "198.51.100.10")
        XCTAssertEqual(config.ipv4Addresses.first?.subnetMask, "255.255.255.0")
        XCTAssertEqual(config.ipv6Addresses.first?.prefixLength, 64)
        XCTAssertEqual(config.includedIPv4Routes.first?.subnetMask, "255.240.0.0")
        XCTAssertEqual(config.excludedIPv4Routes.first?.subnetMask, "255.255.0.0")
        XCTAssertTrue(config.routeAllIPv4)
        XCTAssertTrue(config.routeAllIPv6)
        XCTAssertEqual(config.dnsServers, ["1.1.1.1"])
        XCTAssertTrue(config.routeAllDNS)
        XCTAssertEqual(config.mtu, 1400)
    }

    func testIncompleteCaptureRejected() {
        XCTAssertThrowsError(try MYCODEXTunSettingsAssembler.configuration(from: [])) {
            XCTAssertEqual($0 as? MYCODEXTunCaptureError, .incompleteCapture)
        }
        XCTAssertThrowsError(try MYCODEXTunSettingsAssembler.configuration(
            from: [.init(kind: .ipv4Address, value: "10.8.0.2", prefix: 24)]))
    }

    func testInvalidPrefixAndDuplicateRemoteRejected() {
        var records = sample()
        records[1] = .init(kind: .ipv4Address, value: "10.8.0.2", prefix: 33)
        XCTAssertThrowsError(try MYCODEXTunSettingsAssembler.configuration(from: records)) {
            XCTAssertEqual($0 as? MYCODEXTunCaptureError, .invalidRecord)
        }
        records = sample()
        records.append(.init(kind: .remote, value: "203.0.113.1"))
        XCTAssertThrowsError(try MYCODEXTunSettingsAssembler.configuration(from: records)) {
            XCTAssertEqual($0 as? MYCODEXTunCaptureError, .duplicateRemote)
        }
    }

    func testRejectsInvalidDNSAndMTU() {
        var records = sample()
        records[7] = .init(kind: .dnsAddress, value: "not-an-ip")
        XCTAssertThrowsError(try MYCODEXTunSettingsAssembler.configuration(from: records))
        records = sample()
        records[8] = .init(kind: .mtu, value: "", prefix: 100)
        XCTAssertThrowsError(try MYCODEXTunSettingsAssembler.configuration(from: records))
        records = sample()
        records.append(.init(kind: .mtu, value: "", prefix: 1500))
        XCTAssertThrowsError(try MYCODEXTunSettingsAssembler.configuration(from: records)) {
            XCTAssertEqual($0 as? MYCODEXTunCaptureError, .duplicateMTU)
        }
    }

    func testIpv4ZeroPrefixProducesZeroMask() throws {
        let config = try MYCODEXTunSettingsAssembler.configuration(from: [
            .init(kind: .remote, value: "198.51.100.10"),
            .init(kind: .ipv4Address, value: "10.0.0.2", prefix: 0),
            .init(kind: .ipv4Route, value: "0.0.0.0", prefix: 0)
        ])
        XCTAssertEqual(config.includedIPv4Routes[0].subnetMask, "0.0.0.0")
    }
}
