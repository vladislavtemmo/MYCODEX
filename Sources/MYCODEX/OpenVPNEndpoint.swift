import Foundation

/// Адрес удалённого VPN-сервера из профиля или настроек приложения.
public struct OpenVPNEndpoint: Hashable, Sendable {
    public let hostname: String
    public let port: UInt16
    public let transport: OpenVPNTransport

    /// Запрещает пустой hostname, пробелы/управляющие символы и нулевой порт.
    /// Это только структурная проверка, без DNS и TLS.
    public init(hostname: String, port: UInt16 = 1194, transport: OpenVPNTransport = .udp) throws {
        guard !hostname.isEmpty,
              !hostname.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              port != 0 else {
            throw OpenVPNEndpointError.invalidEndpoint
        }
        self.hostname = hostname
        self.port = port
        self.transport = transport
    }
}

public enum OpenVPNEndpointError: Error, Equatable, Sendable {
    case invalidEndpoint
}
