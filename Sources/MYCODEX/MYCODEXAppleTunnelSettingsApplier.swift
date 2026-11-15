#if canImport(NetworkExtension)
import Foundation
import NetworkExtension

/// Контролируемое применение NEPacketTunnelNetworkSettings внутри расширения.
/// Требуется действительный подписанный NEPacketTunnelProvider. Этот объект
/// НЕ запускает OpenVPN и НЕ вызывает beginReading() у PacketFlow.
@MainActor
public final class MYCODEXAppleTunnelSettingsApplier {
    private weak var provider: NEPacketTunnelProvider?
    private let preparation = MYCODEXPacketTunnelPreparation()
    private var completion: ((Result<Void, MYCODEXPacketTunnelPreparationError>) -> Void)?

    public init(provider: NEPacketTunnelProvider) {
        self.provider = provider
    }

    public var state: MYCODEXPacketTunnelPreparationState { preparation.state }

    /// Callback вызывается один раз при успехе, отказе или отмене.
    /// Успех означает только подтверждение setTunnelNetworkSettings.
    public func apply(_ settings: MYCODEXTunnelNetworkConfiguration,
                      completion: @escaping (Result<Void, MYCODEXPacketTunnelPreparationError>) -> Void) {
        guard let provider else {
            completion(.failure(.providerUnavailable))
            return
        }
        let token: UInt64
        do {
            token = try preparation.beginSettingsApplication()
        } catch {
            completion(.failure(.invalidState))
            return
        }
        self.completion = completion
        provider.setTunnelNetworkSettings(MYCODEXAppleTunnelSettings.make(from: settings)) { [weak self] error in
            // Apple может вызвать completion с произвольного потока. Передаём на
            // MainActor только Bool и UInt64, без несендабельного NSError.
            let accepted = error == nil
            Task { @MainActor [weak self] in
                self?.finish(token: token, accepted: accepted)
            }
        }
    }

    /// Core/TUN ещё не подключены. Проверка запрещает выдавать settingsApplied
    /// за реальное VPN-соединение. Не вызывайте startTunnel completion(nil) здесь.
    public func checkCoreTransport() throws {
        try preparation.checkNativeTransport(isAvailable: OpenVPNClient.isTunnelAdapterAvailable)
    }

    /// При остановке или тайм-ауте Provider остановить прежде, чем освобождать
    /// нативные объекты. Запоздалый ответ Apple не оживит эту сессию.
    public func cancel() {
        preparation.stop()
        let callback = completion
        completion = nil
        callback?(.failure(.cancelled))
    }

    private func finish(token: UInt64, accepted: Bool) {
        // При cancel callback уже вызван; запрещаем повторный вызов.
        guard let callback = completion else { return }
        let result: Result<Void, MYCODEXPacketTunnelPreparationError>
        do {
            try preparation.settingsDidComplete(token: token, accepted: accepted)
            result = .success(())
        } catch let error as MYCODEXPacketTunnelPreparationError {
            result = .failure(error)
        } catch {
            result = .failure(.invalidState)
        }
        completion = nil
        callback(result)
    }
}
#endif
