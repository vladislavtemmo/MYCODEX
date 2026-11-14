#ifndef MYCODEX_BRIDGE_H
#define MYCODEX_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Версия ABI — меняется только при несовместимых изменениях C-интерфейса.
int32_t mycodex_bridge_abi_version(void);

// 0, пока настоящий OpenVPN 3 Core не собран и не подключён к SDK.
int32_t mycodex_bridge_core_linked(void);

// Статическое диагностическое описание; не содержит приватных данных.
const char *mycodex_bridge_backend_name(void);

#ifdef __cplusplus
}
#endif

#endif // MYCODEX_BRIDGE_H
