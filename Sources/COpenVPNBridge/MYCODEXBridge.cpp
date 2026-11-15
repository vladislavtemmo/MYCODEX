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
#include <thread>
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
    // The worker owns no Swift objects. External C ABI calls must be serialized.
    std::mutex lifecycle_mutex;
    std::thread worker;
    int32_t run_state = 0; // 0=new, 1=configured, 2=starting, 3=running,
                           // 4=stopping, 5=stopped, 6=failed
    bool run_started = false; // one connect attempt per client handle
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
        {
            std::lock_guard<std::mutex> lock(handle->lifecycle_mutex);
            handle->run_state = 1;
        }
        return 0;
    } catch (...) {
        return -3;
    }
#else
    return -2;
#endif
}

/* Stops and joins the worker before releasing its Core client. This may block.
 * Never call destroy concurrently with another ABI operation on the same handle.
 */
extern "C" void mycodex_client_destroy(mycodex_client_handle *handle) {
    if (handle == nullptr) return;
#if defined(MYCODEX_WITH_OPENVPN3)
    try {
        bool active;
        {
            std::lock_guard<std::mutex> lock(handle->lifecycle_mutex);
            active = handle->run_state == 2 || handle->run_state == 3 || handle->run_state == 4;
            if (active) handle->run_state = 4;
        }
        if (active) handle->client->stop();
        if (handle->worker.joinable()) handle->worker.join();
    } catch (...) {
        // C ABI must not propagate exceptions; std::thread::join normally cannot
        // throw from an external (non-worker) thread. Caller must serialize calls.
    }
#endif
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

/* Lifecycle API is intentionally disabled until a real PacketTunnel adapter is
 * linked. OPENVPN_FORCE_TUN_NULL is an integration probe, NOT a VPN interface.
 * This guards against reporting an unauthenticated/null-tunnel test as a VPN.
 * If a genuine adapter is supplied later, all state transitions remain in Core.
 */
extern "C" int32_t mycodex_client_run_state(mycodex_client_handle *handle) {
    if (!handle) return -1;
#if defined(MYCODEX_WITH_OPENVPN3)
    try {
        std::lock_guard<std::mutex> lock(handle->lifecycle_mutex);
        return handle->run_state;
    } catch (...) { return -3; }
#else
    return -2;
#endif
}

extern "C" int32_t mycodex_client_start(mycodex_client_handle *handle) {
    if (!handle) return -1;
#if defined(MYCODEX_WITH_OPENVPN3)
    try {
        std::lock_guard<std::mutex> lock(handle->lifecycle_mutex);
        if (!handle->configured || handle->run_started) return -4;
#if defined(MYCODEX_HAS_APPLE_TUN_ADAPTER) && !defined(OPENVPN_FORCE_TUN_NULL)
        // Only an Apple TUN adapter that actively implements TunBuilderBase may
        // enable this flag. The adapter is not present in the current milestone.
        handle->run_state = 2;
        handle->run_started = true;
        try {
            handle->worker = std::thread([handle]() {
                {
                    std::lock_guard<std::mutex> lk(handle->lifecycle_mutex);
                    if (handle->run_state == 4) {
                        handle->run_state = 5;
                        return;
                    }
                    handle->run_state = 3;
                }
                try {
                    const auto status = handle->client->connect();
                    std::lock_guard<std::mutex> lk(handle->lifecycle_mutex);
                    handle->run_state = status.error ? 6 : 5;
                } catch (...) {
                    std::lock_guard<std::mutex> lk(handle->lifecycle_mutex);
                    handle->run_state = 6;
                }
            });
        } catch (...) {
            handle->run_started = false;
            handle->run_state = 1;
            return -3;
        }
        return 0;
#else
        return -6; // tunnel adapter not installed: NEVER start a null-tun VPN
#endif
    } catch (...) { return -3; }
#else
    return -2;
#endif
}

extern "C" int32_t mycodex_client_request_stop(mycodex_client_handle *handle) {
    if (!handle) return -1;
#if defined(MYCODEX_WITH_OPENVPN3)
    try {
        bool active;
        {
            std::lock_guard<std::mutex> lock(handle->lifecycle_mutex);
            active = handle->run_state == 2 || handle->run_state == 3;
            if (active) handle->run_state = 4;
        }
        if (active) handle->client->stop();
        return 0; // idempotent, including before start and after stop
    } catch (...) { return -3; }
#else
    return -2;
#endif
}

extern "C" int32_t mycodex_client_pause(mycodex_client_handle *handle) {
    if (!handle) return -1;
#if defined(MYCODEX_WITH_OPENVPN3)
    try {
        {
            std::lock_guard<std::mutex> lock(handle->lifecycle_mutex);
            if (handle->run_state != 3) return -4;
        }
        handle->client->pause("network unavailable");
        return 0;
    } catch (...) { return -3; }
#else
    return -2;
#endif
}

extern "C" int32_t mycodex_client_resume(mycodex_client_handle *handle) {
    if (!handle) return -1;
#if defined(MYCODEX_WITH_OPENVPN3)
    try {
        {
            std::lock_guard<std::mutex> lock(handle->lifecycle_mutex);
            if (handle->run_state != 3) return -4;
        }
        handle->client->resume();
        return 0;
    } catch (...) { return -3; }
#else
    return -2;
#endif
}

extern "C" int32_t mycodex_client_reconnect(mycodex_client_handle *handle, int32_t seconds) {
    if (!handle || seconds < 0 || seconds > 3600) return -1;
#if defined(MYCODEX_WITH_OPENVPN3)
    try {
        {
            std::lock_guard<std::mutex> lock(handle->lifecycle_mutex);
            if (handle->run_state != 3) return -4;
        }
        handle->client->reconnect(seconds);
        return 0;
    } catch (...) { return -3; }
#else
    return -2;
#endif
}

/* Blocking join, never call on the Swift main actor or from worker callbacks.
 * The caller owns the handle and must serialize wait/destroy and other calls.
 */
extern "C" int32_t mycodex_client_wait(mycodex_client_handle *handle) {
    if (!handle) return -1;
#if defined(MYCODEX_WITH_OPENVPN3)
    try {
        if (handle->worker.joinable()) handle->worker.join();
        return 0;
    } catch (...) { return -3; }
#else
    return -2;
#endif
}

/* Diagnostic capability, not a claim of active connection. */
extern "C" int32_t mycodex_client_tunnel_available(void) {
#if defined(MYCODEX_WITH_OPENVPN3) && defined(MYCODEX_HAS_APPLE_TUN_ADAPTER) && !defined(OPENVPN_FORCE_TUN_NULL)
    return 1;
#else
    return 0;
#endif
}
