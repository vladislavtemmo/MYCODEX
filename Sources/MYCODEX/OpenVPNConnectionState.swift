/// A vocabulary for the future tunnel lifecycle. No tunnel engine is included.
public enum OpenVPNConnectionState: String, Codable, Hashable, Sendable {
    case idle
    case preparing
    case connecting
    case connected
    case reconnecting
    case disconnecting
    case failed
}
