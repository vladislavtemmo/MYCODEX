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
#ifdef __cplusplus
}
#endif
#endif
