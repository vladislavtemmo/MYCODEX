#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == "Darwin" ]] || { echo "ERROR: macOS required"; exit 1; }
for cmd in brew cmake ninja swiftc git pkg-config; do command -v "$cmd" >/dev/null || { echo "ERROR: missing $cmd"; exit 1; }; done
CORE="$ROOT/.external/openvpn3"
PROBE="$ROOT/.external/macos-swift-core-probe"
BUILD="$ROOT/.external/build-macos-swift-core-probe"
LOCK="$(grep "^revision=" "$ROOT/Dependencies/openvpn3.lock" | cut -d= -f2 | tr -d "\r")"
[[ -n "$LOCK" && "$(git -C "$CORE" rev-parse HEAD)" == "$LOCK" ]] || { echo "ERROR: OpenVPN Core revision mismatch"; exit 1; }
cmp -s Sources/COpenVPNBridge/include/MYCODEXBridge.h tools/windows-swift-core-probe/COpenVPNBridge/MYCODEXBridge.h || { echo "ERROR: C ABI header mismatch"; exit 1; }
export PKG_CONFIG_PATH="$(brew --prefix openssl@3)/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
pkg-config --exists openssl || { echo "ERROR: OpenSSL not found"; exit 1; }
echo "=== CONFIGURE MACOS BRIDGE ==="
mkdir -p "$PROBE"
grep -v "^target_link_options(mycodex_core PRIVATE" tools/windows-swift-core-probe/CMakeLists.txt > "$PROBE/CMakeLists.txt"
cmake -S "$PROBE" -B "$BUILD" -G Ninja -DOPENVPN3_ROOT="$CORE" -DMYCODEX_SDK_ROOT="$ROOT" -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$(brew --prefix)"
echo "=== BUILD NATIVE CORE BRIDGE ==="
cmake --build "$BUILD" --parallel 2
echo "=== BUILD SWIFT INTEGRATION PROBE ==="
swiftc -I "$ROOT/tools/windows-swift-core-probe/COpenVPNBridge" -L "$BUILD" -lmycodex_core -Xlinker -rpath -Xlinker "$BUILD" -o "$BUILD/mycodex_swift_probe" Sources/MYCODEX/OpenVPNProfile.swift Sources/MYCODEX/OpenVPNNativeBridge.swift Sources/MYCODEX/OpenVPNProfileValidation.swift tools/windows-swift-core-probe/main.swift
echo "=== TEST SWIFT TO OPENVPN3 ==="
"$BUILD/mycodex_swift_probe"
echo "=== MYCODEX MACOS INTEGRATION PASSED ==="
