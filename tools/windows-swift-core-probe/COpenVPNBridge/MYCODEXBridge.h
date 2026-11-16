#ifndef MYCODEX_BRIDGE_H
#define MYCODEX_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
int32_t mycodex_bridge_abi_version(void);
int32_t mycodex_bridge_core_linked(void);
const char *mycodex_bridge_backend_name(void);
/* 0 = принят; 1 = отклонён; -1 = аргументы; -2 = ядро отсутствует; -3 = исключение. */
int32_t mycodex_bridge_validate_profile(const char *utf8, size_t length);
/* Opaque handle, владеет реальным экземпляром OpenVPNClient в сборке с Core.
 * create возвращает NULL, когда OpenVPN 3 Core не подключён.
 * configure: 0=OK, 1=невалидный профиль, -1=аргументы,
 * -2=нет Core, -3=ошибка ядра, -4=повторная конфигурация.
 * Операции с handle необходимо сериализовать; после destroy он недействителен.
 */
typedef struct mycodex_client_handle mycodex_client_handle;
mycodex_client_handle *mycodex_client_create(void);
int32_t mycodex_client_configure(mycodex_client_handle *handle, const char *utf8, size_t length);
void mycodex_client_destroy(mycodex_client_handle *handle);

/* Credentials: 0=accepted by Core, -1=arguments, -2=Core unavailable,
 * -3=native failure, -4=client not configured, -5=Core rejected credentials.
 * Buffer pointers are borrowed only for this synchronous call.
 * username must be non-empty, <=4096 bytes; password <=16384 bytes.
 * Never log credentials. Callers must serialize operations and destruction.
 */
int32_t mycodex_client_provide_credentials(mycodex_client_handle *handle,
    const char *username, size_t username_length,
    const char *password, size_t password_length);

/* Bound queue of up to 64 event names, never stores Core event.info or logs.
 * 1=event, 0=empty, -1=arguments, -3=native failure.
 * Caller-owned output name must have at least 128 bytes. flags: error=1, fatal=2.
 * Poll may be invoked from a second thread during Core callbacks; destroy
 * must never overlap any operation (including poll).
 */
#define MYCODEX_CLIENT_EVENT_NAME_CAPACITY 128
int32_t mycodex_client_poll_event(mycodex_client_handle *handle,
    char *name, size_t capacity, int32_t *flags);

/* Lifecycle: run state describes the Core worker, NOT VPN connectivity.
 * 0=new, 1=configured, 2=starting, 3=worker running, 4=stopping,
 * 5=stopped, 6=failed. A CONNECTED Core event is required to claim VPN.
 * Start returns -6 while the real PacketTunnel/TunBuilder adapter is absent,
 * or when no validated native TUN socket FD has been staged for this client.
 * Other error codes: -1 arguments, -2 Core unavailable, -3 exception,
 * -4 invalid state. stop is idempotent and nonblocking; wait and destroy
 * can block. Serialize all external operations and destruction on a handle.
 */
int32_t mycodex_client_tunnel_available(void);
int32_t mycodex_client_run_state(mycodex_client_handle *handle);
int32_t mycodex_client_start(mycodex_client_handle *handle);
int32_t mycodex_client_request_stop(mycodex_client_handle *handle);
int32_t mycodex_client_pause(mycodex_client_handle *handle);
int32_t mycodex_client_resume(mycodex_client_handle *handle);
int32_t mycodex_client_reconnect(mycodex_client_handle *handle, int32_t seconds);
int32_t mycodex_client_wait(mycodex_client_handle *handle);
/* Bounded, standalone duplex IP packet queue. No VPN/TUN is established.
 * Directions: 1=system->Core, 2=Core->system (queues are NOT connected
 * to either endpoint until the later PacketTunnel/ExternalTun integration).
 * Push: 1=stored, 0=full (caller must retain/retry), -1=arguments,
 * -2=invalid IP header, -3=closed, -4=internal failure.
 * Pop: 1=packet, 0=empty, -1=arguments, -3=closed+empty,
 * -4=internal failure, -5=buffer too small (packet remains queued).
 * Stats: 0=success. Close: 0=success (idempotent).
 * A queued packet is always copied once; returned packet bytes are copied
 * to the caller-provided buffer. Two queues have separate resource quotas.
 * All API calls except destroy are thread-safe. No calls may overlap destroy.
 * max_packets <= 1024, 1024 <= max_bytes <= 8 MiB PER DIRECTION.
 */
#define MYCODEX_PACKET_TO_CORE 1
#define MYCODEX_PACKET_TO_SYSTEM 2
#define MYCODEX_PACKET_MAX_LENGTH 65535

typedef struct mycodex_packet_bridge mycodex_packet_bridge;
mycodex_packet_bridge *mycodex_packet_bridge_create(uint32_t max_packets, size_t max_bytes);
int32_t mycodex_packet_bridge_push(mycodex_packet_bridge *bridge,
    int32_t direction, const uint8_t *data, size_t length, uint32_t family);
int32_t mycodex_packet_bridge_pop(mycodex_packet_bridge *bridge,
    int32_t direction, uint8_t *buffer, size_t capacity,
    size_t *actual_length, uint32_t *family);
int32_t mycodex_packet_bridge_stats(mycodex_packet_bridge *bridge,
    int32_t direction, uint32_t *packets, size_t *bytes);
int32_t mycodex_packet_bridge_close(mycodex_packet_bridge *bridge);
void mycodex_packet_bridge_destroy(mycodex_packet_bridge *bridge);
/* Captured OpenVPN TunBuilderBase settings (NOT a live TUN interface).
 * A snapshot owns a deep copy; it is safe to destroy the client after creation.
 * create returns NULL when callbacks have not reached establish().
 * get: 0=record, -1=arguments/index, -2=buffer too small.
 * record kinds: 1=remote, 2=v4 addr, 3=v6 addr, 4=v4 route, 5=v6 route,
 * 6=v4 excluded, 7=v6 excluded, 8=DNS IP, 9=MTU (in prefix),
 * 10=IPv4 default route, 11=IPv6 default route. Values max 255 bytes.
 * Records do not include credentials or raw packet data. No call may overlap
 * destruction of the parent client handle during snapshot creation.
 */
typedef struct mycodex_tun_snapshot mycodex_tun_snapshot;
mycodex_tun_snapshot *mycodex_client_tun_snapshot_create(mycodex_client_handle *handle);
size_t mycodex_tun_snapshot_count(const mycodex_tun_snapshot *snapshot);
int32_t mycodex_tun_snapshot_get(const mycodex_tun_snapshot *snapshot,
    size_t index, int32_t *kind, int32_t *prefix, char *value, size_t capacity);
void mycodex_tun_snapshot_destroy(mycodex_tun_snapshot *snapshot);
#if defined(MYCODEX_TUN_CAPTURE_TESTING)
/* Test-only direct callback fixture, compiled out of production binaries. */
int32_t mycodex_client_tun_test_fixture(mycodex_client_handle *handle);
#endif
/* Diagnostic: 1 means the OpenVPN EXTERNAL_TUN_FACTORY build path was
 * selected; 0 means fallback, TunNull or another native Core build.
 * Does not assert actual VPN connectivity or Apple NetworkExtension readiness.
 */
int32_t mycodex_external_tun_factory_compiled(void);
#if defined(MYCODEX_EXTERNAL_TUN_FACTORY_TESTING)
/* Test-only fixture, must not be available in production builds. */
int32_t mycodex_external_tun_factory_test_fixture(mycodex_client_handle *handle);
#endif

/* Core TUN file-descriptor handoff. This is NOT an active VPN.
 * attach_fd borrows/duplicates a nonblocking AF_UNIX SOCK_DGRAM endpoint;
 * original remains caller-owned. Must attach before Core connect attempt.
 * wait_pending returns 1=pending generation, 0=timeout; generation is
 * valid only until cancellation, teardown or the next establish attempt.
 * On pending, caller reads its TunBuilder snapshot, applies real Apple
 * network settings, THEN acknowledges 1=applied or 0=rejected.
 * Acknowledgement must be made on a different thread from Core establish.
 * On rejection, cancellation or timeout the Core FD is never released.
 * Concurrent client destruction is forbidden; cancel before joining worker.
 * All APIs return -1=bad args, -2=unsupported (fallback/no Core),
 * -3=OS failure/cancelled, -4=invalid state/stale generation.
 */
int32_t mycodex_client_tun_attach_fd(mycodex_client_handle *handle, int32_t fd);
int32_t mycodex_client_tun_wait_pending(mycodex_client_handle *handle,
                                        uint32_t timeout_ms, uint64_t *generation);
int32_t mycodex_client_tun_ack_settings(mycodex_client_handle *handle,
                                         uint64_t generation, int32_t applied);
int32_t mycodex_client_tun_cancel(mycodex_client_handle *handle);
#if defined(MYCODEX_TUN_FD_TESTING)
/* Test-only synthetic callback fixture. Never compiled in production. */
int32_t mycodex_client_tun_fd_test_fixture(mycodex_client_handle *handle);
#endif

/* POSIX AF_UNIX/SOCK_DGRAM packet transport. This is NOT an active TUN.
 * The transport borrows the packet bridge; it MUST be destroyed before bridge.
 * The returned core FD is a duplicate owned/closed by its caller. Core/transport
 * endpoints preserve IP datagram boundaries. pump is nonblocking; caller drives
 * it on an appropriate queue/wakeup, never a busy main-thread polling loop.
 * Caller must serialize close/destroy with pump and all other calls. Pump and
 * dup are protected by an internal mutex, but destroy cannot be concurrent.
 * create: NULL on invalid bridge / POSIX setup failure (Windows unsupported).
 * dup_core_fd: >=0 = descriptor, -1=argument, -3=closed, -4=OS failure.
 * pump: 0=success, -1=arguments, -2=invalid packet, -3=closed,
 * -4=OS failure, -5=bridge failure. Counters are successful packet moves.
 * 0 means no progress if both counters are zero. No packet silently dropped
 * on queue saturation: at most one pending packet per direction is retained.
 */
typedef struct mycodex_tun_socket_transport mycodex_tun_socket_transport;
mycodex_tun_socket_transport *mycodex_tun_socket_create(mycodex_packet_bridge *bridge);
int32_t mycodex_tun_socket_dup_core_fd(mycodex_tun_socket_transport *transport);
/* Event driven packet pumping. dup_monitor_fd returns an independently owned
 * duplicate of the PUMP side of the socketpair (NOT the Core side). It may
 * be used exclusively for POLLIN/POLLOUT/DispatchSource readiness observation;
 * never recv/send through it, because that races with transport.pump().
 * Caller closes the monitor descriptor after cancelling its event source.
 * core_write_pending: 1=unsent datagram held, 0=none, -3=closed.
 * Both return -1=arguments, -2=unsupported Windows, -4=OS failure.
 * No operation may overlap transport destroy.
 */
int32_t mycodex_tun_socket_dup_monitor_fd(mycodex_tun_socket_transport *transport);
int32_t mycodex_tun_socket_core_write_pending(mycodex_tun_socket_transport *transport);
int32_t mycodex_tun_socket_pump(mycodex_tun_socket_transport *transport,
    uint32_t max_per_direction, uint32_t *into_core, uint32_t *into_system);
int32_t mycodex_tun_socket_close(mycodex_tun_socket_transport *transport);
void mycodex_tun_socket_destroy(mycodex_tun_socket_transport *transport);
#ifdef __cplusplus
}
#endif
#endif
