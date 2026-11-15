#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == 'Darwin' ]] || { echo 'ERROR: macOS required' >&2; exit 1; }

echo '=== STANDALONE HANDOFF STATE MACHINE ==='
mkdir -p "$ROOT/.external/build-tun-fd-handoff"
c++ -std=c++20 -pthread -Wall -Wextra -Werror \
  -I "$ROOT/Sources/COpenVPNBridge" \
  -o "$ROOT/.external/build-tun-fd-handoff/unit" \
  "$ROOT/tools/tun-fd-handoff-test/main.cpp"
"$ROOT/.external/build-tun-fd-handoff/unit"

echo '=== PREVIOUS CORE / SOCKETPAIR REGRESSION ==='
bash scripts/test-macos-tun-socket.sh

CORE="$ROOT/.external/openvpn3"
PROBE="$ROOT/.external/macos-tun-fd-handoff-probe"
BUILD="$ROOT/.external/build-macos-tun-fd-handoff-probe"
mkdir -p "$PROBE"
sed -e '/^target_link_options(mycodex_core PRIVATE/d' \
    -e 's/OPENVPN_FORCE_TUN_NULL/OPENVPN_EXTERNAL_TUN_FACTORY MYCODEX_TUN_FD_TESTING/g' \
    tools/windows-swift-core-probe/CMakeLists.txt > "$PROBE/CMakeLists.txt"
grep -q 'OPENVPN_EXTERNAL_TUN_FACTORY MYCODEX_TUN_FD_TESTING' "$PROBE/CMakeLists.txt"
! grep -q 'OPENVPN_FORCE_TUN_NULL' "$PROBE/CMakeLists.txt"
export PKG_CONFIG_PATH="$(brew --prefix openssl@3)/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
echo '=== CONFIGURE CORE WITH NATIVE TUN FD HANDOFF ==='
cmake -S "$PROBE" -B "$BUILD" -G Ninja \
  -DOPENVPN3_ROOT="$CORE" -DMYCODEX_SDK_ROOT="$ROOT" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$(brew --prefix)"
echo '=== COMPILE OPENVPN3 HANDOFF ==='
cmake --build "$BUILD" --parallel 2

echo '=== SWIFT / C ABI / REAL TUNBUILDER CALLBACK PROBE ==='
swiftc -D MYCODEX_TUN_FD_TESTING -Xcc -DMYCODEX_TUN_FD_TESTING \
  -I "$ROOT/tools/windows-swift-core-probe/COpenVPNBridge" \
  -L "$BUILD" -lmycodex_core \
  -Xlinker -rpath -Xlinker "$BUILD" \
  -o "$BUILD/mycodex_tun_fd_probe" \
  "$ROOT/tools/macos-tun-fd-handoff-probe/main.swift"
"$BUILD/mycodex_tun_fd_probe"
echo '=== MYCODEX STEP 8.3B2D2C VERIFIED ==='
