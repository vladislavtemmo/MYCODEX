/// Используемый OpenVPN транспорт. Конкретные семейства адресов
/// IPv4/IPv6 и сетевое соединение реализует будущий движок.
public enum OpenVPNTransport: String, Codable, Hashable, Sendable {
    case udp
    case tcp
}
