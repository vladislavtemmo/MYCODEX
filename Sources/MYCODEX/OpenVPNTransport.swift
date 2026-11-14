/// The underlying OpenVPN transport. A future engine adapter is responsible for
/// selecting exact IPv4/IPv6 address families and implementing connections.
public enum OpenVPNTransport: String, Codable, Hashable, Sendable {
    case udp
    case tcp
}
