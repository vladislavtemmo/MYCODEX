#include <MYCODEXBridge.h>
#include <cstring>
#include <iostream>
int main() {
const char *valid = "client\nremote example.invalid 1194\nproto udp\n";
const char *invalid = "client\nproto udp\n";
const int32_t linked = mycodex_bridge_core_linked();
const int32_t good = mycodex_bridge_validate_profile(valid, std::strlen(valid));
const int32_t bad = mycodex_bridge_validate_profile(invalid, std::strlen(invalid));
const int32_t empty = mycodex_bridge_validate_profile(nullptr, 0);
std::cout << "CORE_LINKED=" << linked << "\n";
std::cout << "VALID_RESULT=" << good << "\n";
std::cout << "INVALID_RESULT=" << bad << "\n";
std::cout << "EMPTY_RESULT=" << empty << "\n";
return (linked == 1 && good == 0 && bad == 1 && empty == -1) ? 0 : 1;
}