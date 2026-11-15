import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(NetworkExtension)
import NetworkExtension
#endif

/// Ошибки входных данных для будущего Packet Tunnel Provider.
/// Эти модели не подтверждают, что Core уже установил TUN.
public enum MYCODEXTunnelSettingsError: Error, Equatable, Sendable {
    case invalidRemoteAddress
    case invalidIPv4Address
    case invalidIPv4Mask
    case invalidIPv6Address
    case invalidIPv6Prefix
    case invalidDNSAddress
    case invalidMTU
    case missingTunnelAddress
}

private enum MYCODEXIPValidation {
    static func isIPv4(_ address: String) -> Bool {
        var parsed = in_addr()
        return address.withCString { inet_pton(AF_INET, $0, &parsed) == 1 }
    }

    static func isIPv6(_ address: String) -> Bool {
        var parsed = in6_addr()
        return address.withCString { inet_pton(AF_INET6, $0, &parsed) == 1 }
    }

    static func validMask(_ mask: String) -> Bool {
        guard isIPv4(mask) else { return false }
        let parts = mask.split(separator: ".")
        guard parts.count == 4 else { return false }
        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part) else { return false }
            value = (value << 8) | UInt32(octet)
        }
        let inverted = ~value
        return (inverted & (inverted &+ 1)) == 0
    }
}

public struct MYCODEXIPv4InterfaceAddress: Sendable, Equatable {
    public let address: String
    public let subnetMask: String

    public init(address: String, subnetMask: String) throws {
        guard MYCODEXIPValidation.isIPv4(address) else { throw MYCODEXTunnelSettingsError.invalidIPv4Address }
        guard MYCODEXIPValidation.validMask(subnetMask) else { throw MYCODEXTunnelSettingsError.invalidIPv4Mask }
        self.address = address
        self.subnetMask = subnetMask
    }
}

public struct MYCODEXIPv6InterfaceAddress: Sendable, Equatable {
    public let address: String
    public let prefixLength: Int

    public init(address: String, prefixLength: Int) throws {
        guard MYCODEXIPValidation.isIPv6(address) else { throw MYCODEXTunnelSettingsError.invalidIPv6Address }
        guard (0...128).contains(prefixLength) else { throw MYCODEXTunnelSettingsError.invalidIPv6Prefix }
        self.address = address
        self.prefixLength = prefixLength
    }
}

public struct MYCODEXIPv4Route: Sendable, Equatable {
    public let destination: String
    public let subnetMask: String

    public init(destination: String, subnetMask: String) throws {
        guard MYCODEXIPValidation.isIPv4(destination) else { throw MYCODEXTunnelSettingsError.invalidIPv4Address }
        guard MYCODEXIPValidation.validMask(subnetMask) else { throw MYCODEXTunnelSettingsError.invalidIPv4Mask }
        self.destination = destination
        self.subnetMask = subnetMask
    }
}

public struct MYCODEXIPv6Route: Sendable, Equatable {
    public let destination: String
    public let prefixLength: Int

    public init(destination: String, prefixLength: Int) throws {
        guard MYCODEXIPValidation.isIPv6(destination) else { throw MYCODEXTunnelSettingsError.invalidIPv6Address }
        guard (0...128).contains(prefixLength) else { throw MYCODEXTunnelSettingsError.invalidIPv6Prefix }
        self.destination = destination
        self.prefixLength = prefixLength
    }
}

/// Структура настроек виртуального TUN-интерфейса для Apple NetworkExtension.
/// Значения должны поступать из проверенной конфигурации, полученной от Core,
/// а не из жёстко заданного тестового IP. Применять настройки может только
/// подписанный Packet Tunnel Provider после согласования с OpenVPN 3 Core.
public struct MYCODEXTunnelNetworkConfiguration: Sendable, Equatable {
    public let remoteAddress: String
    public let ipv4Addresses: [MYCODEXIPv4InterfaceAddress]
    public let ipv6Addresses: [MYCODEXIPv6InterfaceAddress]
    public let includedIPv4Routes: [MYCODEXIPv4Route]
    public let excludedIPv4Routes: [MYCODEXIPv4Route]
    public let includedIPv6Routes: [MYCODEXIPv6Route]
    public let excludedIPv6Routes: [MYCODEXIPv6Route]
    public let routeAllIPv4: Bool
    public let routeAllIPv6: Bool
    public let dnsServers: [String]
    public let routeAllDNS: Bool
    public let mtu: Int

    public init(remoteAddress: String,
                ipv4Addresses: [MYCODEXIPv4InterfaceAddress] = [],
                ipv6Addresses: [MYCODEXIPv6InterfaceAddress] = [],
                includedIPv4Routes: [MYCODEXIPv4Route] = [],
                excludedIPv4Routes: [MYCODEXIPv4Route] = [],
                includedIPv6Routes: [MYCODEXIPv6Route] = [],
                excludedIPv6Routes: [MYCODEXIPv6Route] = [],
                routeAllIPv4: Bool = false,
                routeAllIPv6: Bool = false,
                dnsServers: [String] = [],
                routeAllDNS: Bool = false,
                mtu: Int = 1500) throws {
        guard MYCODEXIPValidation.isIPv4(remoteAddress) || MYCODEXIPValidation.isIPv6(remoteAddress) else {
            throw MYCODEXTunnelSettingsError.invalidRemoteAddress
        }
        guard !ipv4Addresses.isEmpty || !ipv6Addresses.isEmpty else {
            throw MYCODEXTunnelSettingsError.missingTunnelAddress
        }
        guard mtu >= (ipv6Addresses.isEmpty ? 576 : 1280) && mtu <= 9000 else {
            throw MYCODEXTunnelSettingsError.invalidMTU
        }
        guard dnsServers.allSatisfy({ MYCODEXIPValidation.isIPv4($0) || MYCODEXIPValidation.isIPv6($0) }) else {
            throw MYCODEXTunnelSettingsError.invalidDNSAddress
        }
        guard !routeAllDNS || !dnsServers.isEmpty else { throw MYCODEXTunnelSettingsError.invalidDNSAddress }
        guard (!routeAllIPv4 || !ipv4Addresses.isEmpty) && (!routeAllIPv6 || !ipv6Addresses.isEmpty) else {
            throw MYCODEXTunnelSettingsError.missingTunnelAddress
        }
        guard (includedIPv4Routes.isEmpty && excludedIPv4Routes.isEmpty) || !ipv4Addresses.isEmpty else {
            throw MYCODEXTunnelSettingsError.missingTunnelAddress
        }
        guard (includedIPv6Routes.isEmpty && excludedIPv6Routes.isEmpty) || !ipv6Addresses.isEmpty else {
            throw MYCODEXTunnelSettingsError.missingTunnelAddress
        }
        self.remoteAddress = remoteAddress
        self.ipv4Addresses = ipv4Addresses
        self.ipv6Addresses = ipv6Addresses
        self.includedIPv4Routes = includedIPv4Routes
        self.excludedIPv4Routes = excludedIPv4Routes
        self.includedIPv6Routes = includedIPv6Routes
        self.excludedIPv6Routes = excludedIPv6Routes
        self.routeAllIPv4 = routeAllIPv4
        self.routeAllIPv6 = routeAllIPv6
        self.dnsServers = dnsServers
        self.routeAllDNS = routeAllDNS
        self.mtu = mtu
    }
}

/// Сопоставление IP-пакета с типом протокола, без аллокаций и копирования Data.
/// Это лишь проверка минимальной длины и версии — не полный разбор заголовка.
public enum MYCODEXIPPacketKind: Equatable, Sendable {
    case ipv4
    case ipv6

    public static func detect(_ bytes: Data) -> Self? {
        guard let first = bytes.first else { return nil }
        switch first >> 4 {
        case 4: return bytes.count >= 20 && (first & 0x0F) >= 5 ? .ipv4 : nil
        case 6: return bytes.count >= 40 ? .ipv6 : nil
        default: return nil
        }
    }

    public var protocolFamily: Int32 {
        switch self {
        case .ipv4: return Int32(AF_INET)
        case .ipv6: return Int32(AF_INET6)
        }
    }
}

#if canImport(NetworkExtension)
/// Фабрика настроек Apple; не вызывает setTunnelNetworkSettings и не создаёт туннель.
/// Вызов setTunnelNetworkSettings принадлежит NEPacketTunnelProvider.
public enum MYCODEXAppleTunnelSettings {
    public static func make(from config: MYCODEXTunnelNetworkConfiguration) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: config.remoteAddress)
        settings.mtu = NSNumber(value: config.mtu)

        if !config.ipv4Addresses.isEmpty {
            let ipv4 = NEIPv4Settings(addresses: config.ipv4Addresses.map(\.address),
                                       subnetMasks: config.ipv4Addresses.map(\.subnetMask))
            var included = config.includedIPv4Routes.map {
                NEIPv4Route(destinationAddress: $0.destination, subnetMask: $0.subnetMask)
            }
            if config.routeAllIPv4 {
                included.insert(NEIPv4Route(destinationAddress: "0.0.0.0", subnetMask: "0.0.0.0"), at: 0)
            }
            ipv4.includedRoutes = included
            ipv4.excludedRoutes = config.excludedIPv4Routes.map {
                NEIPv4Route(destinationAddress: $0.destination, subnetMask: $0.subnetMask)
            }
            settings.ipv4Settings = ipv4
        }

        if !config.ipv6Addresses.isEmpty {
            let ipv6 = NEIPv6Settings(addresses: config.ipv6Addresses.map(\.address),
                                       networkPrefixLengths: config.ipv6Addresses.map { NSNumber(value: $0.prefixLength) })
            var included = config.includedIPv6Routes.map {
                NEIPv6Route(destinationAddress: $0.destination, networkPrefixLength: NSNumber(value: $0.prefixLength))
            }
            if config.routeAllIPv6 {
                included.insert(NEIPv6Route(destinationAddress: "::", networkPrefixLength: NSNumber(value: 0)), at: 0)
            }
            ipv6.includedRoutes = included
            ipv6.excludedRoutes = config.excludedIPv6Routes.map {
                NEIPv6Route(destinationAddress: $0.destination, networkPrefixLength: NSNumber(value: $0.prefixLength))
            }
            settings.ipv6Settings = ipv6
        }

        if !config.dnsServers.isEmpty {
            let dns = NEDNSSettings(servers: config.dnsServers)
            if config.routeAllDNS { dns.matchDomains = [""] }
            settings.dnsSettings = dns
        }
        return settings
    }
}
#endif
