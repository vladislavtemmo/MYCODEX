import COpenVPNBridge

/// Результат подготовки OpenVPN 3 Core клиента. Реальное соединение пока недоступно.
public enum OpenVPNClientError: Error, Equatable, Sendable {
    case coreUnavailable
    case invalidProfile
    case invalidArgument
    case nativeError
    case invalidState
    case unexpectedStatus(Int32)
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
