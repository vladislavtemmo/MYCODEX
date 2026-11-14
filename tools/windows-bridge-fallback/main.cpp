#include <MYCODEXBridge.h>
#include <cstring>
#include <iostream>
int main() {
const char* profile = "client\nremote example.invalid 1194\n";
const auto abi = mycodex_bridge_abi_version();
const auto linked = mycodex_bridge_core_linked();
const auto result = mycodex_bridge_validate_profile(profile, std::strlen(profile));
const auto empty = mycodex_bridge_validate_profile(nullptr, 0);
std::cout << "ABI_VERSION=" << abi << "\nCORE_LINKED=" << linked << "\nPROFILE_RESULT=" << result << "\nEMPTY_RESULT=" << empty << "\n";
return (abi == 1 && linked == 0 && result == -2 && empty == -1) ? 0 : 1;
}