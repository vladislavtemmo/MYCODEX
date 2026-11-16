#include "MYCODEXTunFDHandoff.hpp"
#include <cassert>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>

struct Pair {
    int fd[2] = {-1, -1};
    Pair() {
        assert(socketpair(AF_UNIX, SOCK_DGRAM, 0, fd) == 0);
        int flags = fcntl(fd[0], F_GETFL, 0);
        assert(flags >= 0 && fcntl(fd[0], F_SETFL, flags | O_NONBLOCK) == 0);
    }
    ~Pair() { for (auto &s : fd) if (s >= 0) close(s); }
};

void test_approved() {
    Pair pair;
    MYCODEXTunFDHandoff gate;
    assert(!gate.has_staged_fd());
    assert(gate.stage(pair.fd[0]) == 0);
    assert(gate.has_staged_fd());
    uint64_t gen = 0;
    assert(gate.wait_pending(0, gen) == 0);
    int corefd = -4;
    std::thread worker([&] { corefd = gate.establish(2000); });
    assert(gate.wait_pending(1500, gen) == 1 && gen > 0);
    assert(gate.acknowledge(gen + 1, true) == -4);
    assert(gate.acknowledge(gen, true) == 0);
    assert(gate.acknowledge(gen, true) == -4);
    worker.join();
    assert(corefd >= 0);
    assert(!gate.has_staged_fd());
    const unsigned char packet[20] = {0x45};
    unsigned char got[32]{};
    assert(send(pair.fd[1], packet, 20, 0) == 20);
    assert(recv(corefd, got, sizeof(got), MSG_DONTWAIT) == 20);
    assert(memcmp(packet, got, 20) == 0);
    close(corefd);
    printf("FD_APPROVAL_DELIVERS_DATAGRAM=1\n");
}

void test_rejected() {
    Pair pair;
    MYCODEXTunFDHandoff gate;
    assert(gate.stage(pair.fd[0]) == 0);
    int corefd = -4;
    std::thread worker([&] { corefd = gate.establish(2000); });
    uint64_t gen = 0;
    assert(gate.wait_pending(1500, gen) == 1);
    assert(gate.acknowledge(gen, false) == 0);
    worker.join();
    assert(corefd == -1);
    printf("FD_REJECT_FAIL_CLOSED=1\n");
}

void test_cancel() {
    Pair pair;
    MYCODEXTunFDHandoff gate;
    assert(gate.stage(pair.fd[0]) == 0);
    int corefd = -4;
    std::thread worker([&] { corefd = gate.establish(2000); });
    uint64_t gen = 0;
    assert(gate.wait_pending(1500, gen) == 1);
    gate.cancel();
    worker.join();
    assert(corefd == -1);
    assert(!gate.has_staged_fd());
    assert(gate.wait_pending(0, gen) == -3);
    assert(gate.acknowledge(gen, true) == -4);
    assert(gate.stage(pair.fd[0]) == -4);
    printf("FD_CANCEL_UNBLOCKS=1\n");
}

void test_timeout_and_validation() {
    Pair pair;
    MYCODEXTunFDHandoff gate;
    assert(gate.stage(-1) == -1);
    assert(gate.stage(pair.fd[0]) == 0);
    assert(gate.stage(pair.fd[0]) == -4);
    const auto started = std::chrono::steady_clock::now();
    assert(gate.establish(20) == -1);
    assert(!gate.has_staged_fd());
    const auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::steady_clock::now() - started).count();
    assert(elapsed < 2);
    assert(gate.establish(30) == -1); // descriptor consumed
    int raw[2];
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, raw) == 0);
    MYCODEXTunFDHandoff wrong;
    assert(wrong.stage(raw[0]) == -1);
    close(raw[0]); close(raw[1]);
    printf("FD_TIMEOUT_AND_SOCKET_VALIDATION=1\n");
}

int main() {
    test_approved();
    test_rejected();
    test_cancel();
    test_timeout_and_validation();
    puts("MYCODEX_TUN_FD_HANDOFF_UNIT_PASSED");
    return 0;
}
