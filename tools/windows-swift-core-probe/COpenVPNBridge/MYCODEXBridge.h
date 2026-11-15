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
#ifdef __cplusplus
}
#endif
#endif
