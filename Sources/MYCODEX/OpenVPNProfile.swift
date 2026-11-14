import Foundation

/// Непрозрачный контейнер UTF-8 текста `.ovpn`.
///
/// ВАЖНО: тип не проверяет директивы OpenVPN и не подтверждает
/// подлинность сертификатов. В профиле могут быть закрытые ключи:
/// нельзя выводить исходное содержимое или хранить его открытым текстом.
public struct OpenVPNProfile: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let maximumByteCount = 1_048_576

    private let rawContent: String

    public init(ovpnText: String) throws {
        guard !ovpnText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenVPNProfileError.empty
        }
        guard ovpnText.utf8.count <= Self.maximumByteCount else {
            throw OpenVPNProfileError.tooLarge
        }
        guard !ovpnText.unicodeScalars.contains("\0") else {
            throw OpenVPNProfileError.containsNUL
        }
        self.rawContent = ovpnText
    }

    /// Передавать только проверенному парсеру/движку. Не логировать.
    public func withRawConfiguration<T>(_ body: (String) throws -> T) rethrows -> T {
        try body(rawContent)
    }

    public var description: String { "OpenVPNProfile(<redacted>)" }
    public var debugDescription: String { description }
}

public enum OpenVPNProfileError: Error, Equatable, Sendable {
    case empty
    case tooLarge
    case containsNUL
}
