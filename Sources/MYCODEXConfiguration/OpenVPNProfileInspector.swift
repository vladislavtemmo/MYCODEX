import Foundation
import MYCODEX

/// Extracts *top-level remote endpoints only* from common .ovpn text.
///
/// This is deliberately NOT a complete OpenVPN configuration parser. It does
/// not process includes, nested <connection> blocks, inline key material or
/// the full OpenVPN directive grammar. Never use it as a security validator.
public enum OpenVPNProfileInspector {
    public static func remoteEndpoints(in profile: OpenVPNProfile) throws -> [OpenVPNEndpoint] {
        try profile.withRawConfiguration { text in
            var proto: OpenVPNTransport = .udp
            var remotes: [(hostname: String, port: UInt16, override: OpenVPNTransport?, line: Int)] = []
            var embeddedBlock: String?

            for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
                let lineNumber = index + 1
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }

                // Skip inline content (certificates and key blocks). Connection
                // blocks are also skipped rather than partially interpreted.
                if let block = embeddedBlock {
                    if line.lowercased() == "</\(block)>" { embeddedBlock = nil }
                    continue
                }
                if line.hasPrefix("<"), line.hasSuffix(">"), !line.hasPrefix("</") {
                    let name = String(line.dropFirst().dropLast()).lowercased()
                    if !name.isEmpty { embeddedBlock = name; continue }
                }

                let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                let clean = Array(tokens.prefix(while: { !$0.hasPrefix("#") && !$0.hasPrefix(";") }))
                guard let directive = clean.first?.lowercased() else { continue }

                switch directive {
                case "proto":
                    guard clean.count == 2, let parsed = parseTransport(clean[1]) else {
                        throw OpenVPNInspectionError.invalidTransport(line: lineNumber)
                    }
                    proto = parsed
                case "remote":
                    guard (2...4).contains(clean.count) else {
                        throw OpenVPNInspectionError.invalidRemote(line: lineNumber)
                    }
                    let hostname = clean[1]
                    let port: UInt16
                    if clean.count >= 3 {
                        guard let parsed = UInt16(clean[2]), parsed != 0 else {
                            throw OpenVPNInspectionError.invalidRemote(line: lineNumber)
                        }
                        port = parsed
                    } else {
                        port = 1194
                    }
                    let override: OpenVPNTransport?
                    if clean.count == 4 {
                        guard let parsed = parseTransport(clean[3]) else {
                            throw OpenVPNInspectionError.invalidTransport(line: lineNumber)
                        }
                        override = parsed
                    } else {
                        override = nil
                    }
                    remotes.append((hostname, port, override, lineNumber))
                default:
                    // Preserve unknown directives for the full engine; do not
                    // claim they are valid or supported.
                    break
                }
            }

            guard !remotes.isEmpty else { throw OpenVPNInspectionError.noTopLevelRemote }
            return try remotes.map { remote in
                do {
                    return try OpenVPNEndpoint(
                        hostname: remote.hostname,
                        port: remote.port,
                        transport: remote.override ?? proto
                    )
                } catch {
                    throw OpenVPNInspectionError.invalidRemote(line: remote.line)
                }
            }
        }
    }

    private static func parseTransport(_ raw: String) -> OpenVPNTransport? {
        switch raw.lowercased() {
        case "udp", "udp4", "udp6": return .udp
        case "tcp", "tcp-client", "tcp4-client", "tcp6-client": return .tcp
        default: return nil
        }
    }
}

/// Line numbers are 1-based in the original profile.
public enum OpenVPNInspectionError: Error, Equatable, Sendable {
    case noTopLevelRemote
    case invalidRemote(line: Int)
    case invalidTransport(line: Int)
}
