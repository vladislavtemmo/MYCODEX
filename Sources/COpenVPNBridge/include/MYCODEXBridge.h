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
#ifdef __cplusplus
}
#endif
#endif