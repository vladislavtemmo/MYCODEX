import Foundation
import COpenVPNBridge

/// Captured settings come from OpenVPN TunBuilderBase callback values,
/// not from active Apple network settings or an established VPN session.
public struct MYCODEXTunSetting: Sendable, Equatable {
    public enum Kind: Int32, Sendable {
        case remote = 1
        case ipv4Address = 2
        case ipv6Address = 3
        case ipv4Route = 4
        case ipv6Route = 5
        case ipv4Exclude = 6
        case ipv6Exclude = 7
        case dnsAddress = 8
        case mtu = 9
        case ipv4DefaultRoute = 10
        case ipv6DefaultRoute = 11
    }

    public let kind: Kind
    public let value: String
    public let prefix: Int32

    public init(kind: Kind, value: String, prefix: Int32 = 0) {
        self.kind = kind
        self.value = value
        self.prefix = prefix
    }
}

public enum MYCODEXTunCaptureError: Error, Equatable, Sendable {
    case incompleteCapture
    case duplicateRemote
    case duplicateMTU
    case invalidRecord
    case nativeFailure
}

/// Converts a completed TunBuilderBase capture into the validated Apple model.
/// It does not call setTunnelNetworkSettings and cannot open a VPN tunnel.
public enum MYCODEXTunSettingsAssembler {
    public static func configuration(
        from records: [MYCODEXTunSetting]
    ) throws -> MYCODEXTunnelNetworkConfiguration {
        guard !records.isEmpty else { throw MYCODEXTunCaptureError.incompleteCapture }
        var remote: String?
        var ipv4: [MYCODEXIPv4InterfaceAddress] = []
        var ipv6: [MYCODEXIPv6InterfaceAddress] = []
        var included4: [MYCODEXIPv4Route] = []
        var excluded4: [MYCODEXIPv4Route] = []
        var included6: [MYCODEXIPv6Route] = []
        var excluded6: [MYCODEXIPv6Route] = []
        var dns: [String] = []
        var mtu: Int?
        var default4 = false
        var default6 = false

        for record in records {
            let prefix = Int(record.prefix)
            switch record.kind {
            case .remote:
                guard remote == nil && prefix == 0 else {
                    throw MYCODEXTunCaptureError.duplicateRemote
                }
                remote = record.value
            case .ipv4Address:
                ipv4.append(try MYCODEXIPv4InterfaceAddress(
                    address: record.value, subnetMask: try ipv4Mask(prefix)))
            case .ipv6Address:
                ipv6.append(try MYCODEXIPv6InterfaceAddress(
                    address: record.value, prefixLength: prefix))
            case .ipv4Route:
                included4.append(try MYCODEXIPv4Route(
                    destination: record.value, subnetMask: try ipv4Mask(prefix)))
            case .ipv6Route:
                included6.append(try MYCODEXIPv6Route(
                    destination: record.value, prefixLength: prefix))
            case .ipv4Exclude:
                excluded4.append(try MYCODEXIPv4Route(
                    destination: record.value, subnetMask: try ipv4Mask(prefix)))
            case .ipv6Exclude:
                excluded6.append(try MYCODEXIPv6Route(
                    destination: record.value, prefixLength: prefix))
            case .dnsAddress:
                guard prefix == 0 else { throw MYCODEXTunCaptureError.invalidRecord }
                dns.append(record.value)
            case .mtu:
                guard mtu == nil, record.value.isEmpty else {
                    throw MYCODEXTunCaptureError.duplicateMTU
                }
                mtu = prefix
            case .ipv4DefaultRoute:
                guard prefix == 0, record.value.isEmpty else {
                    throw MYCODEXTunCaptureError.invalidRecord
                }
                default4 = true
            case .ipv6DefaultRoute:
                guard prefix == 0, record.value.isEmpty else {
                    throw MYCODEXTunCaptureError.invalidRecord
                }
                default6 = true
            }
        }
        guard let remote else { throw MYCODEXTunCaptureError.incompleteCapture }
        return try MYCODEXTunnelNetworkConfiguration(
            remoteAddress: remote,
            ipv4Addresses: ipv4,
            ipv6Addresses: ipv6,
            includedIPv4Routes: included4,
            excludedIPv4Routes: excluded4,
            includedIPv6Routes: included6,
            excludedIPv6Routes: excluded6,
            routeAllIPv4: default4,
            routeAllIPv6: default6,
            dnsServers: dns,
            routeAllDNS: !dns.isEmpty,
            mtu: mtu ?? 1500)
    }

    private static func ipv4Mask(_ prefix: Int) throws -> String {
        guard (0...32).contains(prefix) else { throw MYCODEXTunCaptureError.invalidRecord }
        let mask: UInt32 = prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix)
        return [24, 16, 8, 0].map { shift in String((mask >> shift) & 255) }
            .joined(separator: ".")
    }
}

extension OpenVPNClient {
    /// Returns a deep-copied snapshot after Core has invoked its TunBuilder
    /// callbacks. No snapshot is available in the current null-TUN runtime
    /// unless the dedicated native test fixture explicitly invokes them.
    public func capturedTunnelConfiguration() throws -> MYCODEXTunnelNetworkConfiguration {
        guard let snapshot = mycodex_client_tun_snapshot_create(handleForTunCapture) else {
            throw MYCODEXTunCaptureError.incompleteCapture
        }
        defer { mycodex_tun_snapshot_destroy(snapshot) }
        let count = Int(mycodex_tun_snapshot_count(snapshot))
        guard count > 0 && count <= 128 else { throw MYCODEXTunCaptureError.invalidRecord }
        var records: [MYCODEXTunSetting] = []
        records.reserveCapacity(count)
        for index in 0..<count {
            var rawKind: Int32 = 0
            var prefix: Int32 = 0
            var value = [CChar](repeating: 0, count: 256)
            let status = value.withUnsafeMutableBufferPointer { buffer in
                mycodex_tun_snapshot_get(snapshot, index, &rawKind,
                                         &prefix, buffer.baseAddress, buffer.count)
            }
            guard status == 0, let kind = MYCODEXTunSetting.Kind(rawValue: rawKind) else {
                throw MYCODEXTunCaptureError.nativeFailure
            }
            guard let nul = value.firstIndex(of: 0),
                  let decoded = String(bytes: value[..<nul].map { UInt8(bitPattern: $0) },
                                       encoding: .utf8) else {
                throw MYCODEXTunCaptureError.nativeFailure
            }
            records.append(.init(kind: kind, value: decoded, prefix: prefix))
        }
        return try MYCODEXTunSettingsAssembler.configuration(from: records)
    }
}
