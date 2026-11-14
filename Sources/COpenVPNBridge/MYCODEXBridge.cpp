#include "MYCODEXBridge.h"

// Исследовательская точка межъязыкового ABI. Здесь намеренно нет сетевого
// подключения и нет имитации успешного OpenVPN-соединения.
// На следующем этапе реализация будет обёрткой над
// openvpn::ClientAPI::OpenVPNClient и TunBuilderBase.
extern "C" int32_t mycodex_bridge_abi_version(void) {
    return 1;
}

extern "C" int32_t mycodex_bridge_core_linked(void) {
    return 0;
}

extern "C" const char *mycodex_bridge_backend_name(void) {
    return "OpenVPN 3 Core: not linked";
}
