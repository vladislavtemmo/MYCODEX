// NSExtensionPrincipalClass for the signed Packet Tunnel Extension.
// Native start() remains guarded by -6 until the production TUN transport is verified.
#if canImport(NetworkExtension)
import Foundation
import NetworkExtension
import MYCODEX

private final class TunnelCompletion: @unchecked Sendable {
    let finish: (Error?) -> Void
    init(_ finish: @escaping (Error?) -> Void) { self.finish = finish }
}

private final class StopCompletion: @unchecked Sendable {
    let finish: () -> Void
    init(_ finish: @escaping () -> Void) { self.finish = finish }
}

final class PacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    private enum StartError: LocalizedError {
        case nativeTransportNotReady
        var errorDescription: String? {
            "MYCODEX: native OpenVPN PacketTunnel transport is not verified"
        }
    }

    @MainActor private var sessionController: MYCODEXApplePacketTunnelSessionController?

    @MainActor private func controller() -> MYCODEXApplePacketTunnelSessionController {
        if let sessionController { return sessionController }
        let controller = MYCODEXApplePacketTunnelSessionController(
            makeRuntime: { [weak self] profile, credentials, generation in
            guard let self else { throw StartError.nativeTransportNotReady }
            return try await MYCODEXAppleOpenVPNRuntime.prepare(
                profile: profile, credentials: credentials, provider: self,
                onFailure: { [weak self] in self?.sessionController?.transportDidFail(generation: generation) }
            )
            },
            onDisconnection: { [weak self] _ in
                self?.cancelTunnelWithError(StartError.nativeTransportNotReady)
            }
        )
        sessionController = controller
        return controller
    }

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        let callback = TunnelCompletion(completionHandler)
        // Read the non-Sendable options before crossing to MainActor. Never log
        // profile material, credentials, certificates, or private keys.
        let configuration = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        let profileText = (options?["ovpnProfile"] as? String) ?? (configuration?["ovpnProfile"] as? String)
        let username = (options?["username"] as? String) ?? (configuration?["username"] as? String)
        let password = (options?["password"] as? String) ?? (configuration?["password"] as? String)
        let credentials: MYCODEXAppleTunnelCredentials?
        if let username, let password {
            credentials = MYCODEXAppleTunnelCredentials(username: username, password: password)
        } else {
            credentials = nil
        }
        let incompleteCredentials = (username == nil) != (password == nil)
        Task { @MainActor [weak self] in
            guard let self, !incompleteCredentials,
                  OpenVPNNativeBridge.isOpenVPNCoreLinked,
                  OpenVPNNativeBridge.isExternalTunFactoryCompiled else {
                callback.finish(StartError.nativeTransportNotReady)
                return
            }
            self.controller().start(profileText: profileText, credentials: credentials) { result in
                switch result {
                case .success: callback.finish(nil)
                case .failure: callback.finish(StartError.nativeTransportNotReady)
                }
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        let callback = StopCompletion(completionHandler)
        Task { @MainActor [weak self] in
            guard let self else { callback.finish(); return }
            guard let controller = self.sessionController else { callback.finish(); return }
            controller.stop { callback.finish() }
        }
    }
}
#endif
