// Пример NSExtensionPrincipalClass для подписанного Packet Tunnel Extension.
// Это намеренно fail-closed, потому что production Core start() ещё возвращает
// -6: подписанный NetworkExtension и сквозной VPN-трафик не проверены.
#if canImport(NetworkExtension)
import Foundation
import NetworkExtension
import MYCODEX

// Callback NetworkExtension может прийти с любой очереди. Обёртка вызывается
// на MainActor после однократного завершения операции в lifecycle.
private final class TunnelCompletion: @unchecked Sendable {
    let finish: (Error?) -> Void
    init(_ finish: @escaping (Error?) -> Void) { self.finish = finish }
}

private final class StopCompletion: @unchecked Sendable {
    let finish: () -> Void
    init(_ finish: @escaping () -> Void) { self.finish = finish }
}

// Изменяемое состояние Provider изолировано MainActor через lifecycle.
final class PacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    @MainActor private let lifecycle = MYCODEXPacketTunnelSessionLifecycle()

    private enum StartError: LocalizedError {
        case nativeTransportNotReady
        var errorDescription: String? {
            "MYCODEX: native OpenVPN PacketTunnel transport is not verified"
        }
    }

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        let callback = TunnelCompletion(completionHandler)
        // Start/stop callbacks могут приходить не на MainActor; вся работа
        // с состоянием сериализуется на главном акторе.
        Task { @MainActor [weak self] in
            guard let self else {
                callback.finish(StartError.nativeTransportNotReady)
                return
            }
            guard let generation = self.lifecycle.begin(
                completion: { result in
                    switch result {
                    case .success:
                        // Недостижимо в этом fail-closed примере: без реального
                        // Core CONNECTED и PacketFlow нельзя завершать start(nil).
                        callback.finish(nil)
                    case .failure:
                        callback.finish(StartError.nativeTransportNotReady)
                    }
                },
                onDisconnection: { [weak self] _ in
                    self?.cancelTunnelWithError(StartError.nativeTransportNotReady)
                }
            ) else { return }

            // Проверка заставляет именно extension слинковать настоящий Core.
            // Созданный клиент не запускает worker и не создаёт VPN-сессию.
            guard OpenVPNNativeBridge.isOpenVPNCoreLinked,
                  OpenVPNNativeBridge.isExternalTunFactoryCompiled,
                  (try? OpenVPNClient()) != nil else {
                _ = self.lifecycle.fail(generation: generation, reason: .nativeTunnelUnavailable)
                return
            }
            // Транспорт ещё не подключён. Не имитировать ACK или CONNECTED.
            _ = self.lifecycle.fail(generation: generation, reason: .nativeTunnelUnavailable)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        let callback = StopCompletion(completionHandler)
        Task { @MainActor [weak self] in
            guard let self else { callback.finish(); return }
            guard let token = self.lifecycle.requestStop(completion: { callback.finish() }) else {
                return
            }
            // В ЭТОМ примере Core worker никогда не создаётся, а PacketFlow
            // никогда не запускается. Поэтому отсутствующие ресурсы могут
            // завершить обе фазы без блокирующего join. В реальном Provider:
            // 1) native cancel+stop, 2) join на фоне, 3) stopMonitoring,
            // 4) close socket/bridge, 5) resourcesDidRelease.
            guard self.lifecycle.coreWorkerDidJoin(stopToken: token) else { return }
            _ = self.lifecycle.resourcesDidRelease(stopToken: token)
        }
    }
}
#endif
