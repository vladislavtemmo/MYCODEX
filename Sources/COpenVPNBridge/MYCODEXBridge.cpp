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