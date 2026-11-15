#include "MYCODEXBridge.h"
#if defined(MYCODEX_WITH_OPENVPN3)
#define OPENVPN_CORE_API_VISIBILITY_HIDDEN
#include <client/ovpncli.cpp>
#include <cstring>
#include <string>
#endif
extern "C" int32_t mycodex_bridge_abi_version(void) { return 1; }
extern "C" int32_t mycodex_bridge_core_linked(void) {
#if defined(MYCODEX_WITH_OPENVPN3)
return 1;
#else
return 0;
#endif
}
extern "C" const char *mycodex_bridge_backend_name(void) {
#if defined(MYCODEX_WITH_OPENVPN3)
return "OpenVPN 3 Core";
#else
return "OpenVPN 3 Core: not linked";
#endif
}
extern "C" int32_t mycodex_bridge_validate_profile(const char *utf8, size_t length) {
if (utf8 == nullptr || length == 0 || length > 1048576) return -1;
#if defined(MYCODEX_WITH_OPENVPN3)
if (std::memchr(utf8, 0, length) != nullptr) return -1;
try {
openvpn::ClientAPI::Config config;
config.content.assign(utf8, length);
openvpn::ClientAPI::OpenVPNClientHelper helper;
const auto result = helper.eval_config(config);
return result.error ? 1 : 0;
} catch (...) { return -3; }
#else
return -2;
#endif
}

/* Первый инкремент OpenVPNClient. Пока НЕ запускает VPN-туннель.
 * После create handle принадлежит вызывающему коду до destroy.
 * Все операции с одним handle должны выполняться последовательно.
 */
#if defined(MYCODEX_WITH_OPENVPN3)
#include <memory>

class MYCODEXNativeClient final : public openvpn::ClientAPI::OpenVPNClient {
public:
    void event(const openvpn::ClientAPI::Event &) override {}
    void acc_event(const openvpn::ClientAPI::AppCustomControlMessageEvent &) override {}
    void log(const openvpn::ClientAPI::LogInfo &) override {}
    bool pause_on_connection_timeout() override { return false; }
    void external_pki_cert_request(openvpn::ClientAPI::ExternalPKICertRequest &r) override {
        r.error = true;
        r.errorText = "External PKI is not implemented";
    }
    void external_pki_sign_request(openvpn::ClientAPI::ExternalPKISignRequest &r) override {
        r.error = true;
        r.errorText = "External PKI is not implemented";
    }
};
#endif

struct mycodex_client_handle {
#if defined(MYCODEX_WITH_OPENVPN3)
    std::unique_ptr<MYCODEXNativeClient> client;
    bool configured = false;
#endif
};

extern "C" mycodex_client_handle *mycodex_client_create(void) {
#if defined(MYCODEX_WITH_OPENVPN3)
    try {
        auto handle = std::make_unique<mycodex_client_handle>();
        handle->client = std::make_unique<MYCODEXNativeClient>();
        return handle.release();
    } catch (...) {
        return nullptr;
    }
#else
    return nullptr;
#endif
}

extern "C" int32_t mycodex_client_configure(mycodex_client_handle *handle, const char *utf8, size_t length) {
    if (handle == nullptr || utf8 == nullptr || length == 0 || length > 1048576) return -1;
#if defined(MYCODEX_WITH_OPENVPN3)
    if (std::memchr(utf8, 0, length) != nullptr) return -1;
    if (handle->configured) return -4;
    try {
        openvpn::ClientAPI::Config config;
        config.content.assign(utf8, length);
        const auto result = handle->client->eval_config(config);
        if (result.error) return 1;
        handle->configured = true;
        return 0;
    } catch (...) {
        return -3;
    }
#else
    return -2;
#endif
}

extern "C" void mycodex_client_destroy(mycodex_client_handle *handle) {
    delete handle;
}
