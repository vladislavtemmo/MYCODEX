import COpenVPNBridge

/// Результат подготовки OpenVPN 3 Core клиента. Реальное соединение пока недоступно.
public enum OpenVPNClientError: Error, Equatable, Sendable {
    case coreUnavailable
    case invalidProfile
    case invalidArgument
    case nativeError
    case invalidState
    case credentialsRejected
    case tunnelUnavailable
    case unexpectedStatus(Int32)
}

/// Именованное событие Core без потенциально чувствительного поля `info`.
public struct OpenVPNClientEvent: Equatable, Sendable {
    public let name: String
    public let isError: Bool
    public let isFatal: Bool
}

/// Состояние рабочего потока Core, не состояние VPN-туннеля.
public enum OpenVPNClientRunState: Int32, Sendable, Equatable {
    case initial = 0
    case configured = 1
    case starting = 2
    case running = 3
    case stopping = 4
    case stopped = 5
    case failed = 6
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

    /// Реальный Tunnel Adapter ещё не реализован, поэтому start пока
    /// обязательно возвращает tunnelUnavailable. Это безопаснее, чем
    /// выдавать null-TUN тест за настоящее VPN-подключение.
    public static var isTunnelAdapterAvailable: Bool {
        mycodex_client_tunnel_available() == 1
    }

    public var runState: OpenVPNClientRunState {
        get throws {
            let value = mycodex_client_run_state(handle)
            if let state = OpenVPNClientRunState(rawValue: value) { return state }
            throw Self.lifecycleError(value)
        }
    }

    public func start() throws {
        try Self.checkLifecycle(mycodex_client_start(handle))
    }

    /// Асинхронно запрашивает остановку Core. Не блокирует ожидая завершения.
    public func requestStop() throws {
        try Self.checkLifecycle(mycodex_client_request_stop(handle))
    }

    public func pause() throws {
        try Self.checkLifecycle(mycodex_client_pause(handle))
    }

    public func resume() throws {
        try Self.checkLifecycle(mycodex_client_resume(handle))
    }

    public func reconnect(afterSeconds seconds: Int32) throws {
        try Self.checkLifecycle(mycodex_client_reconnect(handle, seconds))
    }

    /// Блокирует текущий поток до завершения worker. Не вызывайте на MainActor.
    public func waitForWorker() throws {
        try Self.checkLifecycle(mycodex_client_wait(handle))
    }

    private static func checkLifecycle(_ status: Int32) throws {
        if status != 0 { throw lifecycleError(status) }
    }

    private static func lifecycleError(_ status: Int32) -> OpenVPNClientError {
        switch status {
        case -1: return .invalidArgument
        case -2: return .coreUnavailable
        case -3: return .nativeError
        case -4: return .invalidState
        case -6: return .tunnelUnavailable
        default: return .unexpectedStatus(status)
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
