#pragma once

// Strictly POSIX and fail-closed. This object does not create a TUN device.
// It gates the already-existing Unix datagram endpoint on explicit settings
// approval. No method may overlap destruction. All regular methods are
// protected by an internal mutex, with condition_variable handshakes.
#if !defined(_WIN32)

#include <cerrno>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <fcntl.h>
#include <mutex>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

class MYCODEXTunFDHandoff final {
public:
    ~MYCODEXTunFDHandoff() { cancel(); }
    MYCODEXTunFDHandoff() = default;
    MYCODEXTunFDHandoff(const MYCODEXTunFDHandoff &) = delete;
    MYCODEXTunFDHandoff &operator=(const MYCODEXTunFDHandoff &) = delete;

    bool has_staged_fd() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return !cancelled_ && staged_fd_ >= 0;
    }

    // Borrowed input descriptor. Validates AF_UNIX / SOCK_DGRAM and duplicates
    // it with CLOEXEC. The caller retains ownership of the input FD.
    // 0=accepted, -1=invalid fd/type, -3=dup/fcntl failure, -4=state.
    int32_t stage(int fd) {
        if (fd < 0) return -1;
        int type = 0;
        socklen_t type_len = sizeof(type);
        sockaddr_storage address{};
        socklen_t address_len = sizeof(address);
        if (::getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &type_len) != 0 ||
            type_len != sizeof(type) || type != SOCK_DGRAM ||
            ::getsockname(fd, reinterpret_cast<sockaddr *>(&address), &address_len) != 0 ||
            address.ss_family != AF_UNIX) return -1;
        const int flags = ::fcntl(fd, F_GETFL, 0);
        if (flags < 0 || !(flags & O_NONBLOCK)) return -1;
        const int copy = ::dup(fd);
        if (copy < 0) return -3;
        const int old = ::fcntl(copy, F_GETFD, 0);
        if (old < 0 || ::fcntl(copy, F_SETFD, old | FD_CLOEXEC) != 0) {
            ::close(copy);
            return -3;
        }
        std::lock_guard<std::mutex> lock(mutex_);
        if (cancelled_ || pending_ || staged_fd_ >= 0) {
            ::close(copy);
            return -4;
        }
        staged_fd_ = copy;
        return 0;
    }

    // Only the Core's own builder thread may call establish(). Return the FD
    // (owned by Core) after acknowledgement, or -1 on rejection/timeout/cancel.
    // The staged FD is consumed exactly once; no silent fallthrough to TunMac.
    int establish(uint32_t timeout_ms = 15000) {
        std::unique_lock<std::mutex> lock(mutex_);
        if (cancelled_ || pending_ || staged_fd_ < 0 || timeout_ms == 0 || timeout_ms > 30000)
            return -1;
        pending_ = true;
        acknowledged_ = false;
        approved_ = false;
        ++generation_;
        cv_.notify_all();
        const bool signaled = cv_.wait_for(lock, std::chrono::milliseconds(timeout_ms), [&] {
            return cancelled_ || acknowledged_;
        });
        int result = -1;
        if (signaled && acknowledged_ && approved_ && !cancelled_ && staged_fd_ >= 0) {
            result = ::dup(staged_fd_);
            if (result >= 0) {
                const int flags = ::fcntl(result, F_GETFD, 0);
                if (flags < 0 || ::fcntl(result, F_SETFD, flags | FD_CLOEXEC) != 0) {
                    ::close(result);
                    result = -1;
                }
            }
        }
        close_staged_locked();
        pending_ = false;
        acknowledged_ = false;
        approved_ = false;
        cv_.notify_all();
        return result;
    }

    // 1=pending and generation returned, 0=timed out, -3=cancelled.
    int32_t wait_pending(uint32_t timeout_ms, uint64_t &generation) {
        if (timeout_ms > 30000) return -1;
        std::unique_lock<std::mutex> lock(mutex_);
        cv_.wait_for(lock, std::chrono::milliseconds(timeout_ms), [&] {
            return pending_ || cancelled_;
        });
        if (cancelled_) return -3;
        if (!pending_) return 0;
        generation = generation_;
        return 1;
    }

    // One acknowledgement per generation. Stale and duplicate ACKs fail.
    int32_t acknowledge(uint64_t generation, bool applied) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (cancelled_ || !pending_ || acknowledged_ || generation == 0 || generation != generation_)
            return -4;
        acknowledged_ = true;
        approved_ = applied;
        cv_.notify_all();
        return 0;
    }

    // Idempotent. Unblocks an awaiting Core worker and prevents later reuse.
    void cancel() {
        std::lock_guard<std::mutex> lock(mutex_);
        cancelled_ = true;
        approved_ = false;
        acknowledged_ = false;
        close_staged_locked();
        cv_.notify_all();
    }

private:
    void close_staged_locked() {
        if (staged_fd_ >= 0) {
            (void)::close(staged_fd_);
            staged_fd_ = -1;
        }
    }

    mutable std::mutex mutex_;
    std::condition_variable cv_;
    int staged_fd_ = -1;
    uint64_t generation_ = 0;
    bool pending_ = false;
    bool acknowledged_ = false;
    bool approved_ = false;
    bool cancelled_ = false;
};
#endif
