// Образец NSExtensionPrincipalClass (отдельный Packet Tunnel Extension target).
// ВНИМАНИЕ: намеренно fail closed, пока реальный ExternalTun/TUN packet engine
// не соединён с MYCODEXPacketBridge и нет end-to-end device тестов.
// Добавьте этот файл в подписываемый Packet Tunnel Extension target Xcode.
#if canImport(NetworkExtension)
import Foundation
import NetworkExtension
import MYCODEX

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private enum StartError: LocalizedError {
        case nativeTransportNotReady
        var errorDescription: String? {
            "MYCODEX: OpenVPN TUN packet transport is not integrated"
        }
    }

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        // Никогда не сообщать ОС об успешном запуске без рабочего Core TUN.
        // Будущая последовательность:
        // Core config/creds -> capture pushed settings -> apply & acknowledge ->
        // start native packet transport -> Core CONNECTED -> completion(nil).
        completionHandler(StartError.nativeTransportNotReady)
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        // Когда появятся worker/PacketFlow: сначала stop/drain/join, затем callback.
        completionHandler()
    }
}
#endif
