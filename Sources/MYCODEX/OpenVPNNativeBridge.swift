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

    /// Проверяет выбор настоящей External TUN Factory на этапе компиляции Core.
    /// Это не подтверждение подключения VPN или готовности Apple PacketFlow.
    public static var isExternalTunFactoryCompiled: Bool {
        mycodex_external_tun_factory_compiled() == 1
    }

    /// Название фактически доступного backend, без диагностических секретов.
    public static var backendName: String {
        String(cString: mycodex_bridge_backend_name())
    }
}
