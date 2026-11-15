// Пример NSExtensionPrincipalClass для подписанного Packet Tunnel Extension.
// Это намеренно fail-closed, потому что production Core start() ещё возвращает
// -6: подписанный NetworkExtension и сквозной VPN-трафик не проверены.
#if canImport(NetworkExtension)
import Foundation
import NetworkExtension
import MYCODEX

final class PacketTunnelProvider: NEPacketTunnelProvider {
    @MainActor private let lifecycle = MYCODEXPacketTunnelSessionLifecycle()

    private enum StartError: LocalizedError {
        case nativeTransportNotReady
        var errorDescription: String? {
            "MYCODEX: native OpenVPN PacketTunnel transport is not verified"
        }
    }

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        // Start/stop callbacks могут приходить не на MainActor; вся работа
        // с состоянием сериализуется на главном акторе.
        Task { @MainActor [weak self] in
            guard let self else {
                completionHandler(StartError.nativeTransportNotReady)
                return
            }
            guard let generation = self.lifecycle.begin(
                completion: { result in
                    switch result {
                    case .success:
                        // Недостижимо в этом fail-closed примере: без реального
                        // Core CONNECTED и PacketFlow нельзя завершать start(nil).
                        completionHandler(nil)
                    case .failure:
                        completionHandler(StartError.nativeTransportNotReady)
                    }
                },
                onDisconnection: { [weak self] _ in
                    self?.cancelTunnelWithError(StartError.nativeTransportNotReady)
                }
            ) else { return }

            // Единственная доступная сейчас ветка. Не вызывать Core.start(),
            // не имитировать ACK, пакетный транспорт или CONNECTED.
            _ = self.lifecycle.fail(generation: generation, reason: .nativeTunnelUnavailable)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { completionHandler(); return }
            guard let token = self.lifecycle.requestStop(completion: { completionHandler() }) else {
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
