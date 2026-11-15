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
#include <algorithm>
#include <deque>
#include <memory>
#include <mutex>
#include <openssl/crypto.h>

class MYCODEXNativeClient final : public openvpn::ClientAPI::OpenVPNClient {
public:
    // От Core поступают исключительно события control plane. Не сохраняем info:
    // оно может включать персональные данные, адреса и диагностические секреты.
    void event(const openvpn::ClientAPI::Event &event) override {
        try {
            std::lock_guard<std::mutex> lock(events_mutex_);
            if (events_.size() == 64) events_.pop_front();
            events_.push_back({event.name.substr(0, MYCODEX_CLIENT_EVENT_NAME_CAPACITY - 1),
                               event.error, event.fatal});
        } catch (...) {
            // C++ исключения никогда не пересекают Core callback boundary.
        }
    }
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

    int32_t poll_event(char *name, size_t capacity, int32_t *flags) {
        std::lock_guard<std::mutex> lock(events_mutex_);
        if (events_.empty()) return 0;
        const auto &front = events_.front();
        if (capacity < front.name.size() + 1) return -1;
        std::copy(front.name.begin(), front.name.end(), name);
        name[front.name.size()] = '\0';
        *flags = (front.error ? 1 : 0) | (front.fatal ? 2 : 0);
        events_.pop_front();
        return 1;
    }
private:
    struct QueuedEvent {
        std::string name;
        bool error;
        bool fatal;
    };
    std::mutex events_mutex_;
    std::deque<QueuedEvent> events_;
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

/* Credentials принимаются только после успешного eval_config. Строки
 * передаются по длине: embedded NUL запрещён. Временная копия пароля
 * очищается после передачи в Core; Core хранит собственную копию до destroy.
 */
extern "C" int32_t mycodex_client_provide_credentials(mycodex_client_handle *handle,
        const char *username, size_t username_length,
        const char *password, size_t password_length) {
    if (handle == nullptr || username == nullptr || password == nullptr ||
        username_length == 0 || username_length > 4096 || password_length > 16384) return -1;
#if defined(MYCODEX_WITH_OPENVPN3)
    if (std::memchr(username, 0, username_length) != nullptr ||
        (password_length > 0 && std::memchr(password, 0, password_length) != nullptr)) return -1;
    if (!handle->configured) return -4;
    try {
        openvpn::ClientAPI::ProvideCreds creds;
        creds.username.assign(username, username_length);
        creds.password.assign(password, password_length);
        struct PasswordWiper {
            std::string &value;
            ~PasswordWiper() {
                if (!value.empty()) OPENSSL_cleanse(value.data(), value.size());
            }
        } wipe{creds.password};
        const auto status = handle->client->provide_creds(creds);
        return status.error ? -5 : 0;
    } catch (...) {
        return -3;
    }
#else
    return -2;
#endif
}

/* 1 = событие; 0 = нет событий. name — буфер, принадлежащий вызывающему.
 * flags: bit 0 = error, bit 1 = fatal. События ещё не генерируются без connect.
 */
extern "C" int32_t mycodex_client_poll_event(mycodex_client_handle *handle,
        char *name, size_t capacity, int32_t *flags) {
    if (handle == nullptr || name == nullptr || flags == nullptr ||
        capacity < MYCODEX_CLIENT_EVENT_NAME_CAPACITY) return -1;
#if defined(MYCODEX_WITH_OPENVPN3)
    try {
        return handle->client->poll_event(name, capacity, flags);
    } catch (...) {
        return -3;
    }
#else
    return -2;
#endif
}
