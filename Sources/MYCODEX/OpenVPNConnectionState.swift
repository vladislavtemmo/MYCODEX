/// Состояния будущего VPN-туннеля. Сам движок пока не подключён.
public enum OpenVPNConnectionState: String, Codable, Hashable, Sendable {
    case idle
    case preparing
    case connecting
    case connected
    case reconnecting
    case disconnecting
    case failed
}
