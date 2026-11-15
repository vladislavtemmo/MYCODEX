import Foundation
import XCTest
@testable import MYCODEX
#if canImport(NetworkExtension)
import NetworkExtension
#endif

final class AppleTunnelNetworkSettingsTests: XCTestCase {
    func testIPv4ConfigurationAndRoutes() throws {
        let address = try MYCODEXIPv4InterfaceAddress(address: "10.8.0.2", subnetMask: "255.255.255.0")
        let route = try MYCODEXIPv4Route(destination: "172.16.0.0", subnetMask: "255.240.0.0")
        let config = try MYCODEXTunnelNetworkConfiguration(
            remoteAddress: "198.51.100.10", ipv4Addresses: [address],
            includedIPv4Routes: [route], routeAllIPv4: true,
            dnsServers: ["1.1.1.1"], routeAllDNS: true, mtu: 1400)
        XCTAssertEqual(config.ipv4Addresses.first, address)
        XCTAssertEqual(config.includedIPv4Routes, [route])
        XCTAssertEqual(config.mtu, 1400)
        #if canImport(NetworkExtension)
        let settings = MYCODEXAppleTunnelSettings.make(from: config)
        XCTAssertEqual(settings.ipv4Settings?.addresses, ["10.8.0.2"])
        XCTAssertEqual(settings.ipv4Settings?.subnetMasks, ["255.255.255.0"])
        XCTAssertEqual(settings.ipv4Settings?.includedRoutes?.count, 2)
        XCTAssertEqual(settings.dnsSettings?.servers, ["1.1.1.1"])
        XCTAssertEqual(settings.dnsSettings?.matchDomains, [""])
        XCTAssertEqual(settings.mtu?.intValue, 1400)
        #endif
    }

    func testIPv6Configuration() throws {
        let address = try MYCODEXIPv6InterfaceAddress(address: "2001:db8::2", prefixLength: 64)
        let config = try MYCODEXTunnelNetworkConfiguration(
            remoteAddress: "2001:db8::1", ipv6Addresses: [address],
            routeAllIPv6: true, dnsServers: ["2606:4700:4700::1111"], mtu: 1280)
        XCTAssertEqual(config.ipv6Addresses.first, address)
        #if canImport(NetworkExtension)
        let settings = MYCODEXAppleTunnelSettings.make(from: config)
        XCTAssertEqual(settings.ipv6Settings?.addresses, ["2001:db8::2"])
        XCTAssertEqual(settings.ipv6Settings?.networkPrefixLengths.first?.intValue, 64)
        XCTAssertEqual(settings.ipv6Settings?.includedRoutes?.count, 1)
        #endif
    }

    func testRejectsInvalidNetworkSettings() throws {
        XCTAssertThrowsError(try MYCODEXIPv4InterfaceAddress(address: "256.1.1.1", subnetMask: "255.255.255.0"))
        XCTAssertThrowsError(try MYCODEXIPv4InterfaceAddress(address: "10.0.0.1", subnetMask: "255.0.255.0"))
        XCTAssertThrowsError(try MYCODEXIPv6InterfaceAddress(address: "2001:db8::1", prefixLength: 129))
        let address = try MYCODEXIPv4InterfaceAddress(address: "10.8.0.2", subnetMask: "255.255.255.0")
        XCTAssertThrowsError(try MYCODEXTunnelNetworkConfiguration(remoteAddress: "vpn.example.com", ipv4Addresses: [address]))
        XCTAssertThrowsError(try MYCODEXTunnelNetworkConfiguration(remoteAddress: "198.51.100.10"))
        XCTAssertThrowsError(try MYCODEXTunnelNetworkConfiguration(remoteAddress: "198.51.100.10", ipv4Addresses: [address], dnsServers: ["dns.example.com"]))
        XCTAssertThrowsError(try MYCODEXTunnelNetworkConfiguration(remoteAddress: "198.51.100.10", ipv4Addresses: [address], mtu: 500))
        XCTAssertThrowsError(try MYCODEXTunnelNetworkConfiguration(remoteAddress: "198.51.100.10", ipv4Addresses: [address], routeAllIPv6: true))
    }

    func testPacketProtocolKindUsesIPHeader() {
        XCTAssertNil(MYCODEXIPPacketKind.detect(Data()))
        XCTAssertNil(MYCODEXIPPacketKind.detect(Data([0x45])))
        XCTAssertNil(MYCODEXIPPacketKind.detect(Data(repeating: 0, count: 40)))
        XCTAssertNil(MYCODEXIPPacketKind.detect(Data([0x44] + Array(repeating: 0, count: 19))))
        XCTAssertEqual(MYCODEXIPPacketKind.detect(Data([0x45] + Array(repeating: 0, count: 19))), .ipv4)
        XCTAssertEqual(MYCODEXIPPacketKind.detect(Data([0x60] + Array(repeating: 0, count: 39))), .ipv6)
        XCTAssertNotEqual(MYCODEXIPPacketKind.ipv4.protocolFamily, MYCODEXIPPacketKind.ipv6.protocolFamily)
    }
}
