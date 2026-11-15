#ifndef MYCODEX_TUN_CAPTURE_HPP
#define MYCODEX_TUN_CAPTURE_HPP

#include <cstdint>
#include <string>
#include <vector>

// Internal snapshot of OpenVPN TunBuilderBase callbacks. Values come from
// OpenVPN Core, never from a locally invented VPN connection.
// Records are immutable once copied out to the C ABI snapshot.
enum class MYCODEXTunKind : int32_t {
    Remote = 1,
    IPv4Address = 2,
    IPv6Address = 3,
    IPv4Route = 4,
    IPv6Route = 5,
    IPv4Exclude = 6,
    IPv6Exclude = 7,
    DNS = 8,
    MTU = 9,
    RedirectIPv4 = 10,
    RedirectIPv6 = 11
};

struct MYCODEXTunRecord {
    MYCODEXTunKind kind;
    int32_t prefix;
    std::string value;
};

using MYCODEXTunRecords = std::vector<MYCODEXTunRecord>;

#endif
