#if canImport(NetworkExtension)
import Foundation
import NetworkExtension

/// Apple-only bridge from an already-pending native TunBuilder generation to
/// setTunnelNetworkSettings. This does not invoke OpenVPNClient.start() and
/// never reports the VPN as connected.
@MainActor
public final class MYCODEXAppleTunFDSettingsHandoff {
    private let settingsApplier: MYCODEXAppleTunnelSettingsApplier
    private let coordinator: MYCODEXTunFDSettingsCoordinator

    public init(provider: NEPacketTunnelProvider, nativeClient: OpenVPNClient) {
        settingsApplier = MYCODEXAppleTunnelSettingsApplier(provider: provider)
        coordinator = MYCODEXTunFDSettingsCoordinator(native: nativeClient)
    }

    public var state: MYCODEXTunFDSettingsState { coordinator.state }

    /// Only call with a generation obtained on a background worker via
    /// OpenVPNClient.waitForPendingTunSettings(). The completion is deliberately
    /// NOT NEPacketTunnelProvider.startTunnel's completion: Core CONNECTED is
    /// still required before signalling a usable VPN.
    public func applyPending(
        generation: UInt64,
        completion: @escaping @MainActor (Result<Void, MYCODEXTunFDSettingsError>) -> Void
    ) {
        coordinator.begin(generation: generation, apply: { [settingsApplier] config, finished in
            settingsApplier.apply(config) { result in
                switch result {
                case .success: finished(true)
                case .failure: finished(false)
                }
            }
        }, completion: completion)
    }

    public func cancel() {
        // Invalidate generation BEFORE applier.cancel calls its callback.
        coordinator.cancel()
        settingsApplier.cancel()
    }
}
#endif
