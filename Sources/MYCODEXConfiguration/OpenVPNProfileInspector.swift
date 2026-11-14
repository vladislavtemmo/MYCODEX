import Foundation
import MYCODEX

/// Извлекает адреса серверов из распространённых форм `.ovpn`.
///
/// Поддерживаются верхнеуровневые `remote` и блоки `<connection>`, а также
/// объявления `proto` и индивидуальные переопределения транспорта.
/// Это НЕ полный парсер OpenVPN, НЕ проверка безопасности профиля и НЕ замена
/// функции `eval_config` настоящего OpenVPN 3 Core.
public enum OpenVPNProfileInspector {
    public static func remoteEndpoints(in profile: OpenVPNProfile) throws -> [OpenVPNEndpoint] {
        try profile.withRawConfiguration { text in
            struct PendingRemote {
                let hostname: String
                let port: UInt16
                let transport: OpenVPNTransport?
                let connectionID: Int?
                let line: Int
            }

            var defaultTransport: OpenVPNTransport = .udp
            var connectionTransports: [Int: OpenVPNTransport] = [:]
            var remotes: [PendingRemote] = []
            var connectionID: Int?
            var nextConnectionID = 0
            var embeddedBlock: String?

            for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
                let lineNumber = index + 1
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
                let lowercased = line.lowercased()

                // Не читаем сертификаты, закрытые ключи и другие inline-блоки.
                if let block = embeddedBlock {
                    if lowercased == "</\(block)>" { embeddedBlock = nil }
                    continue
                }

                if lowercased == "<connection>" {
                    guard connectionID == nil else {
                        throw OpenVPNInspectionError.invalidBlock(line: lineNumber)
                    }
                    nextConnectionID += 1
                    connectionID = nextConnectionID
                    continue
                }
                if lowercased == "</connection>" {
                    guard connectionID != nil else {
                        throw OpenVPNInspectionError.invalidBlock(line: lineNumber)
                    }
                    connectionID = nil
                    continue
                }

                if lowercased.hasPrefix("<"), lowercased.hasSuffix(">"),
                   !lowercased.hasPrefix("</") {
                    let name = String(lowercased.dropFirst().dropLast())
                    guard !name.isEmpty else {
                        throw OpenVPNInspectionError.invalidBlock(line: lineNumber)
                    }
                    embeddedBlock = name
                    continue
                }
                if lowercased.hasPrefix("</"), lowercased.hasSuffix(">") {
                    throw OpenVPNInspectionError.invalidBlock(line: lineNumber)
                }

                // Лексический разбор поддерживает аргументы в кавычках и
                // экранирование символов. Комментарий начинается вне кавычек
                // только с границы токена: не разбираем профиль через split().
                let tokens = try tokenize(line, lineNumber: lineNumber)
                guard let command = tokens.first?.lowercased() else { continue }

                switch command {
                case "proto":
                    guard tokens.count == 2,
                          let transport = parseTransport(tokens[1]) else {
                        throw OpenVPNInspectionError.invalidTransport(line: lineNumber)
                    }
                    if let connectionID {
                        connectionTransports[connectionID] = transport
                    } else {
                        defaultTransport = transport
                    }

                case "remote":
                    guard (2...4).contains(tokens.count) else {
                        throw OpenVPNInspectionError.invalidRemote(line: lineNumber)
                    }

                    let hostname = tokens[1]
                    var port: UInt16 = 1194
                    var transport: OpenVPNTransport?
                    if tokens.count >= 3 {
                        if let specifiedPort = UInt16(tokens[2]), specifiedPort != 0 {
                            port = specifiedPort
                        } else if tokens.count == 3,
                                  let parsed = parseTransport(tokens[2]) {
                            transport = parsed
                        } else {
                            throw OpenVPNInspectionError.invalidRemote(line: lineNumber)
                        }
                    }
                    if tokens.count == 4 {
                        guard let parsed = parseTransport(tokens[3]) else {
                            throw OpenVPNInspectionError.invalidTransport(line: lineNumber)
                        }
                        transport = parsed
                    }
                    remotes.append(PendingRemote(
                        hostname: hostname, port: port, transport: transport,
                        connectionID: connectionID, line: lineNumber
                    ))

                default:
                    // Неизвестные директивы анализирует только реальный движок.
                    break
                }
            }

            if embeddedBlock != nil || connectionID != nil {
                throw OpenVPNInspectionError.unclosedBlock
            }
            guard !remotes.isEmpty else { throw OpenVPNInspectionError.noRemote }

            return try remotes.map { remote in
                do {
                    return try OpenVPNEndpoint(
                        hostname: remote.hostname,
                        port: remote.port,
                        transport: remote.transport
                            ?? remote.connectionID.flatMap { connectionTransports[$0] }
                            ?? defaultTransport
                    )
                } catch {
                    throw OpenVPNInspectionError.invalidRemote(line: remote.line)
                }
            }
        }
    }

    /// Разбивает строку OpenVPN-конфигурации на токены без вывода сырого ввода.
    /// Не претендует на полноценное воспроизведение лексера OpenVPN 3 Core.
    private static func tokenize(_ line: String, lineNumber: Int) throws -> [String] {
        var tokens: [String] = []
        var token = ""
        var active = false
        var quotedBy: Character?
        var escaped = false

        for character in line {
            if escaped {
                token.append(character)
                active = true
                escaped = false
                continue
            }
            if character == "\\" {
                active = true
                escaped = true
                continue
            }
            if let quote = quotedBy {
                if character == quote {
                    quotedBy = nil
                } else {
                    token.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quotedBy = character
                active = true
                continue
            }
            if character.isWhitespace {
                if active {
                    tokens.append(token)
                    token = ""
                    active = false
                }
                continue
            }
            if (character == "#" || character == ";") && !active {
                break
            }
            token.append(character)
            active = true
        }
        guard quotedBy == nil && !escaped else {
            throw OpenVPNInspectionError.malformedDirective(line: lineNumber)
        }
        if active { tokens.append(token) }
        return tokens
    }

    private static func parseTransport(_ raw: String) -> OpenVPNTransport? {
        switch raw.lowercased() {
        case "udp", "udp4", "udp6": return .udp
        case "tcp", "tcp-client", "tcp4-client", "tcp6-client": return .tcp
        default: return nil
        }
    }
}

/// Номера строк начинаются с 1 в оригинальном `.ovpn`-профиле.
public enum OpenVPNInspectionError: Error, Equatable, Sendable {
    case noRemote
    case invalidRemote(line: Int)
    case invalidTransport(line: Int)
    case invalidBlock(line: Int)
    case malformedDirective(line: Int)
    case unclosedBlock
}
