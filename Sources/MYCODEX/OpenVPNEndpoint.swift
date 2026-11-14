import Foundation

/// A remote OpenVPN server endpoint extracted from a profile or supplied by a host app.
public struct OpenVPNEndpoint: Hashable, Sendable {
    public let hostname: String
    public let port: UInt16
    public let transport: OpenVPNTransport

    /// Rejects empty hostnames, whitespace/control characters, and port zero.
    /// This is minimal structural validation, not DNS resolution or TLS validation.
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
