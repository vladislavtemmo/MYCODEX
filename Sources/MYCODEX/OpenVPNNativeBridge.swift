import COpenVPNBridge

/// Диагностика нативного C++-моста OpenVPN.
///
/// Наличие моста само по себе НЕ означает, что OpenVPN 3 Core уже подключён
/// или что VPN-туннель способен устанавливать соединение.
public enum OpenVPNNativeBridge {
    /// Версия стабильного C ABI между Swift и C++.
    public static var abiVersion: Int32 { mycodex_bridge_abi_version() }

    /// `false` до настоящей линковки OpenVPN 3 Core.
    public static var isOpenVPNCoreLinked: Bool {
        mycodex_bridge_core_linked() == 1
    }

    /// Название фактически доступного backend, без диагностических секретов.
    public static var backendName: String {
        String(cString: mycodex_bridge_backend_name())
    }
}
