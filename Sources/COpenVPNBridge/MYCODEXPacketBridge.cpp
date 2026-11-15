#include "MYCODEXBridge.h"

#include <cstdint>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <utility>
#include <vector>

// Non-networked, bounded duplex IP packet staging. This object does NOT
// implement TunBuilderBase and is not connected to OpenVPN 3 Core yet.
// Ownership: one caller-owned handle; push/pop/stat may be concurrent, but
// destruction MUST be serialized with all calls against that handle.
struct mycodex_packet_bridge {
    struct Packet {
        std::vector<uint8_t> bytes;
        uint32_t family; // 4 (IPv4) or 6 (IPv6), deliberately not AF_*.
    };
    struct Channel {
        std::deque<Packet> packets;
        size_t bytes = 0;
    };

    explicit mycodex_packet_bridge(uint32_t limit_packets, size_t limit_bytes)
        : limit_packets(limit_packets), limit_bytes(limit_bytes) {}

    std::mutex mutex;
    Channel system_to_core;
    Channel core_to_system;
    const uint32_t limit_packets;
    const size_t limit_bytes;
    bool closed = false;
};

namespace {
// A minimal, cheap IP header check; intentionally NOT a full packet verifier.
bool valid_packet(const uint8_t *data, size_t length, uint32_t family) {
    if (data == nullptr || length > MYCODEX_PACKET_MAX_LENGTH) return false;
    if (family == 4) {
        if (length < 20 || (data[0] >> 4) != 4) return false;
        const size_t header_len = (data[0] & 0x0F) * 4;
        return header_len >= 20 && length >= header_len;
    }
    if (family == 6) return length >= 40 && (data[0] >> 4) == 6;
    return false;
}

mycodex_packet_bridge::Channel *channel_for(mycodex_packet_bridge *bridge, int32_t direction) {
    if (direction == MYCODEX_PACKET_TO_CORE) return &bridge->system_to_core;
    if (direction == MYCODEX_PACKET_TO_SYSTEM) return &bridge->core_to_system;
    return nullptr;
}
} // namespace

extern "C" mycodex_packet_bridge *mycodex_packet_bridge_create(uint32_t max_packets, size_t max_bytes) {
    if (max_packets == 0 || max_packets > 1024 || max_bytes < 1024 || max_bytes > 8u * 1024u * 1024u)
        return nullptr;
    try {
        return new mycodex_packet_bridge(max_packets, max_bytes);
    } catch (...) { return nullptr; }
}

extern "C" int32_t mycodex_packet_bridge_push(mycodex_packet_bridge *bridge,
    int32_t direction, const uint8_t *data, size_t length, uint32_t family) {
    if (bridge == nullptr || channel_for(bridge, direction) == nullptr) return -1;
    if (!valid_packet(data, length, family)) return -2;
    try {
        std::lock_guard<std::mutex> lock(bridge->mutex);
        if (bridge->closed) return -3;
        auto *channel = channel_for(bridge, direction);
        if (channel->packets.size() >= bridge->limit_packets ||
            length > bridge->limit_bytes - channel->bytes)
            return 0; // backpressure: caller RETAINS packet and must retry
        std::vector<uint8_t> copy(data, data + length);
        channel->packets.push_back({std::move(copy), family});
        channel->bytes += length;
        return 1;
    } catch (...) { return -4; }
}

extern "C" int32_t mycodex_packet_bridge_pop(mycodex_packet_bridge *bridge,
    int32_t direction, uint8_t *buffer, size_t capacity,
    size_t *actual_length, uint32_t *family) {
    if (bridge == nullptr || channel_for(bridge, direction) == nullptr ||
        buffer == nullptr || actual_length == nullptr || family == nullptr)
        return -1;
    try {
        std::lock_guard<std::mutex> lock(bridge->mutex);
        auto *channel = channel_for(bridge, direction);
        if (channel->packets.empty()) return bridge->closed ? -3 : 0;
        const auto &packet = channel->packets.front();
        *actual_length = packet.bytes.size();
        if (capacity < packet.bytes.size()) return -5; // packet remains queued
        std::memcpy(buffer, packet.bytes.data(), packet.bytes.size());
        *family = packet.family;
        channel->bytes -= packet.bytes.size();
        channel->packets.pop_front();
        return 1;
    } catch (...) { return -4; }
}

extern "C" int32_t mycodex_packet_bridge_stats(mycodex_packet_bridge *bridge,
    int32_t direction, uint32_t *packets, size_t *bytes) {
    if (bridge == nullptr || channel_for(bridge, direction) == nullptr ||
        packets == nullptr || bytes == nullptr) return -1;
    try {
        std::lock_guard<std::mutex> lock(bridge->mutex);
        auto *channel = channel_for(bridge, direction);
        *packets = static_cast<uint32_t>(channel->packets.size());
        *bytes = channel->bytes;
        return 0;
    } catch (...) { return -4; }
}

extern "C" int32_t mycodex_packet_bridge_close(mycodex_packet_bridge *bridge) {
    if (!bridge) return -1;
    try {
        std::lock_guard<std::mutex> lock(bridge->mutex);
        bridge->closed = true;
        return 0;
    } catch (...) { return -4; }
}

extern "C" void mycodex_packet_bridge_destroy(mycodex_packet_bridge *bridge) {
    delete bridge;
}
