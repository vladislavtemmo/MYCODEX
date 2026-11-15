#include "MYCODEXBridge.h"

#include <cstdint>
#include <cstddef>

#if !defined(_WIN32)

#include <array>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <memory>
#include <mutex>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <vector>

// The peer is an ordinary Unix datagram socket, NOT an Apple virtual interface.
// Core must take a duplicate of core_fd; the transport retains its own copy to
// support repeatable tests. Call close() before release. The referenced packet
// bridge must outlive the transport and all pump calls. Destroy is serialized.
struct mycodex_tun_socket_transport {
    explicit mycodex_tun_socket_transport(mycodex_packet_bridge *borrowed)
        : bridge(borrowed) {}
    mycodex_packet_bridge *bridge;  // borrowed, never freed here
    ~mycodex_tun_socket_transport() {
        if (pump_fd >= 0) (void)::close(pump_fd);
        if (core_fd >= 0) (void)::close(core_fd);
    }
    int core_fd = -1;
    int pump_fd = -1;
    bool closed = false;
    std::mutex mutex;
    std::vector<uint8_t> pending_to_core;
    std::vector<uint8_t> pending_to_system;
    uint32_t pending_system_family = 0;
};

namespace {

bool cloexec(const int fd) {
    const int flags = fcntl(fd, F_GETFD, 0);
    return flags >= 0 && fcntl(fd, F_SETFD, flags | FD_CLOEXEC) == 0;
}

bool nonblocking(const int fd) {
    const int flags = fcntl(fd, F_GETFL, 0);
    return flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0;
}

void close_fd(int &fd) {
    if (fd >= 0) { (void)::close(fd); fd = -1; }
}

void close_locked(mycodex_tun_socket_transport &transport) {
    transport.closed = true;
    close_fd(transport.pump_fd);
    close_fd(transport.core_fd);
    transport.pending_to_core.clear();
    transport.pending_to_system.clear();
}

bool would_block() { return errno == EWOULDBLOCK || errno == EAGAIN; }

// Core->system. Returns: 1=transferred, 0=would block/no packet, -2=
// invalid datagram, -4=I/O error, -5=packet bridge failure.
int32_t receive_from_core(mycodex_tun_socket_transport &transport) {
    if (transport.pending_to_system.empty()) {
        std::array<uint8_t, MYCODEX_PACKET_MAX_LENGTH + 1> buffer{};
        ssize_t n;
        do { n = ::recv(transport.pump_fd, buffer.data(), buffer.size(), MSG_DONTWAIT); }
        while (n < 0 && errno == EINTR);
        if (n < 0) return would_block() ? 0 : -4;
        if (n == 0 || static_cast<size_t>(n) > MYCODEX_PACKET_MAX_LENGTH) return -2;
        const uint32_t family = buffer[0] >> 4;
        if (family != 4 && family != 6) return -2;
        transport.pending_to_system.assign(buffer.data(), buffer.data() + n);
        transport.pending_system_family = family;
    }
    const int32_t result = mycodex_packet_bridge_push(
        transport.bridge, MYCODEX_PACKET_TO_SYSTEM,
        transport.pending_to_system.data(), transport.pending_to_system.size(),
        transport.pending_system_family);
    if (result == 0) return 0;  // full: retry without reading another datagram
    if (result == -2) return -2;
    if (result != 1) return -5;
    transport.pending_to_system.clear();
    transport.pending_system_family = 0;
    return 1;
}

// System->Core. Same return codes, packet is kept on transient send failures.
int32_t send_to_core(mycodex_tun_socket_transport &transport) {
    if (transport.pending_to_core.empty()) {
        std::array<uint8_t, MYCODEX_PACKET_MAX_LENGTH> buffer{};
        size_t actual = 0;
        uint32_t family = 0;
        const int32_t result = mycodex_packet_bridge_pop(
            transport.bridge, MYCODEX_PACKET_TO_CORE,
            buffer.data(), buffer.size(), &actual, &family);
        if (result == 0) return 0;
        if (result == -3) return 0; // closed & drained
        if (result != 1) return -5;
        if (actual > MYCODEX_PACKET_MAX_LENGTH) return -5;
        transport.pending_to_core.assign(buffer.data(), buffer.data() + actual);
    }
    int flags = MSG_DONTWAIT;
#ifdef MSG_NOSIGNAL
    flags |= MSG_NOSIGNAL;
#endif
    ssize_t n;
    do { n = ::send(transport.pump_fd, transport.pending_to_core.data(),
                    transport.pending_to_core.size(), flags); }
    while (n < 0 && errno == EINTR);
    if (n < 0) return would_block() ? 0 : -4;
    if (static_cast<size_t>(n) != transport.pending_to_core.size()) return -4;
    transport.pending_to_core.clear();
    return 1;
}

} // namespace

extern "C" mycodex_tun_socket_transport *mycodex_tun_socket_create(mycodex_packet_bridge *bridge) {
    if (!bridge) return nullptr;
    try {
        auto transport = std::make_unique<mycodex_tun_socket_transport>(bridge);
        int fds[2] = {-1, -1};
        if (::socketpair(AF_UNIX, SOCK_DGRAM, 0, fds) != 0) return nullptr;
        transport->core_fd = fds[0];
        transport->pump_fd = fds[1];
        // No SIGPIPE when Core closes its endpoint while the pump is sending.
#ifdef SO_NOSIGPIPE
        int one = 1;
        if (::setsockopt(fds[1], SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one)) != 0) return nullptr;
#endif
        const int size = 256 * 1024;
        (void)::setsockopt(fds[0], SOL_SOCKET, SO_SNDBUF, &size, sizeof(size));
        (void)::setsockopt(fds[0], SOL_SOCKET, SO_RCVBUF, &size, sizeof(size));
        (void)::setsockopt(fds[1], SOL_SOCKET, SO_SNDBUF, &size, sizeof(size));
        (void)::setsockopt(fds[1], SOL_SOCKET, SO_RCVBUF, &size, sizeof(size));
        if (!cloexec(fds[0]) || !cloexec(fds[1]) || !nonblocking(fds[0]) || !nonblocking(fds[1])) return nullptr;
        return transport.release();
    } catch (...) { return nullptr; }
}

extern "C" int32_t mycodex_tun_socket_dup_core_fd(mycodex_tun_socket_transport *transport) {
    if (!transport) return -1;
    try {
        std::lock_guard<std::mutex> lock(transport->mutex);
        if (transport->closed) return -3;
        const int fd = ::dup(transport->core_fd);
        if (fd < 0) return -4;
        if (!cloexec(fd)) { (void)::close(fd); return -4; }
        return fd; // caller owns descriptor; must close it
    } catch (...) { return -4; }
}

// An independently owned monitor-only duplicate of the pump endpoint.
// Never read/write through this descriptor: it is exclusively for kqueue/
// DispatchSource readiness notifications. The caller must close it.
extern "C" int32_t mycodex_tun_socket_dup_monitor_fd(mycodex_tun_socket_transport *transport) {
    if (!transport) return -1;
    try {
        std::lock_guard<std::mutex> lock(transport->mutex);
        if (transport->closed || transport->pump_fd < 0) return -3;
        const int fd = ::dup(transport->pump_fd);
        if (fd < 0) return -4;
        if (!cloexec(fd)) { (void)::close(fd); return -4; }
        return fd;
    } catch (...) { return -4; }
}

// 1: a datagram is waiting for a writable pump FD. 0: none waiting.
// Does not inspect the separate staging queue; callers inspect both.
extern "C" int32_t mycodex_tun_socket_core_write_pending(mycodex_tun_socket_transport *transport) {
    if (!transport) return -1;
    try {
        std::lock_guard<std::mutex> lock(transport->mutex);
        if (transport->closed) return -3;
        return transport->pending_to_core.empty() ? 0 : 1;
    } catch (...) { return -4; }
}

extern "C" int32_t mycodex_tun_socket_pump(mycodex_tun_socket_transport *transport,
    uint32_t max_per_direction, uint32_t *into_core, uint32_t *into_system) {
    if (!transport || !into_core || !into_system || max_per_direction == 0 || max_per_direction > 256)
        return -1;
    *into_core = 0;
    *into_system = 0;
    try {
        std::lock_guard<std::mutex> lock(transport->mutex);
        if (transport->closed) return -3;
        for (uint32_t i = 0; i < max_per_direction; ++i) {
            const int32_t r = receive_from_core(*transport);
            if (r < 0) return r;
            if (r == 1) ++*into_system;
            const int32_t w = send_to_core(*transport);
            if (w < 0) return w;
            if (w == 1) ++*into_core;
            if (r == 0 && w == 0) break;
        }
        return 0;
    } catch (...) { return -4; }
}

extern "C" int32_t mycodex_tun_socket_close(mycodex_tun_socket_transport *transport) {
    if (!transport) return -1;
    try {
        std::lock_guard<std::mutex> lock(transport->mutex);
        close_locked(*transport);
        return 0;
    } catch (...) { return -4; }
}

extern "C" void mycodex_tun_socket_destroy(mycodex_tun_socket_transport *transport) {
    if (!transport) return;
    (void)mycodex_tun_socket_close(transport);
    delete transport;
}

#else // Windows: POSIX socketpair not available; explicit unsupported stubs.
struct mycodex_tun_socket_transport {};
extern "C" mycodex_tun_socket_transport *mycodex_tun_socket_create(mycodex_packet_bridge *) { return nullptr; }
extern "C" int32_t mycodex_tun_socket_dup_core_fd(mycodex_tun_socket_transport *) { return -2; }
extern "C" int32_t mycodex_tun_socket_dup_monitor_fd(mycodex_tun_socket_transport *) { return -2; }
extern "C" int32_t mycodex_tun_socket_core_write_pending(mycodex_tun_socket_transport *) { return -2; }
extern "C" int32_t mycodex_tun_socket_pump(mycodex_tun_socket_transport *, uint32_t,
    uint32_t *, uint32_t *) { return -2; }
extern "C" int32_t mycodex_tun_socket_close(mycodex_tun_socket_transport *) { return -2; }
extern "C" void mycodex_tun_socket_destroy(mycodex_tun_socket_transport *) {}
#endif
