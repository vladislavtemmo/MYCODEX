import COpenVPNBridge

/// Результат подготовки OpenVPN 3 Core клиента. Реальное соединение пока недоступно.
public enum OpenVPNClientError: Error, Equatable, Sendable {
    case coreUnavailable
    case invalidProfile
    case invalidArgument
    case nativeError
    case invalidState
    case credentialsRejected
    case unexpectedStatus(Int32)
}

/// Именованное событие Core без потенциально чувствительного поля `info`.
public struct OpenVPNClientEvent: Equatable, Sendable {
    public let name: String
    public let isError: Bool
    public let isFatal: Bool
}

/// Владеет C++ OpenVPNClient через opaque C ABI handle.
/// Пока доступны только создание и настройка; VPN-туннель НЕ запускается.
/// Тип намеренно не Sendable: используйте экземпляр последовательно в одном контексте.
public final class OpenVPNClient {
    private let handle: OpaquePointer

    public init() throws {
        guard OpenVPNNativeBridge.isOpenVPNCoreLinked else {
            throw OpenVPNClientError.coreUnavailable
        }
        guard let handle = mycodex_client_create() else {
            throw OpenVPNClientError.nativeError
        }
        self.handle = handle
    }

    deinit {
        mycodex_client_destroy(handle)
    }

    /// Передаёт credentials после configure(). Core принимает их синхронно;
    /// Swift String не обеспечивает гарантированного стирания секретов из памяти.
    /// Не вызывайте параллельно с configure(), pollEvent() или deinit.
    public func provideCredentials(username: String, password: String) throws {
        let status: Int32 = username.withCString { user in
            password.withCString { pass in
                mycodex_client_provide_credentials(handle, user, username.utf8.count,
                                                   pass, password.utf8.count)
            }
        }
        switch status {
        case 0: return
        case -1: throw OpenVPNClientError.invalidArgument
        case -2: throw OpenVPNClientError.coreUnavailable
        case -3: throw OpenVPNClientError.nativeError
        case -4: throw OpenVPNClientError.invalidState
        case -5: throw OpenVPNClientError.credentialsRejected
        default: throw OpenVPNClientError.unexpectedStatus(status)
        }
    }

    /// Неблокирующее чтение события. До реализации connect() очередь пуста.
    /// События в Core ограничены 64 элементами; старые вытесняются новыми.
    public func pollEvent() throws -> OpenVPNClientEvent? {
        var eventName = [CChar](repeating: 0, count: 128)
        var flags: Int32 = 0
        let status: Int32 = eventName.withUnsafeMutableBufferPointer { buffer in
            mycodex_client_poll_event(handle, buffer.baseAddress, buffer.count, &flags)
        }
        switch status {
        case 0: return nil
        case 1:
            let name = eventName.withUnsafeBufferPointer { buffer in
                String(cString: buffer.baseAddress!)
            }
            return OpenVPNClientEvent(name: name,
                                      isError: (flags & 1) != 0,
                                      isFatal: (flags & 2) != 0)
        case -1: throw OpenVPNClientError.invalidArgument
        case -2: throw OpenVPNClientError.coreUnavailable
        case -3: throw OpenVPNClientError.nativeError
        default: throw OpenVPNClientError.unexpectedStatus(status)
        }
    }

    public func configure(_ profile: OpenVPNProfile) throws {
        let status: Int32 = profile.withRawConfiguration { configuration in
            configuration.withCString { pointer in
                mycodex_client_configure(handle, pointer, configuration.utf8.count)
            }
        }
        switch status {
        case 0: return
        case 1: throw OpenVPNClientError.invalidProfile
        case -1: throw OpenVPNClientError.invalidArgument
        case -2: throw OpenVPNClientError.coreUnavailable
        case -3: throw OpenVPNClientError.nativeError
        case -4: throw OpenVPNClientError.invalidState
        default: throw OpenVPNClientError.unexpectedStatus(status)
        }
    }
}
