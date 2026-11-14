import Foundation

/// An opaque validated container for .ovpn UTF-8 text.
///
/// IMPORTANT: This type does NOT validate OpenVPN directives or authenticate
/// certificates. A profile may contain embedded private keys or credentials:
/// never print its raw contents or persist them in plaintext.
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

    /// Use only for forwarding configuration to a trusted parser/engine; do not log.
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
