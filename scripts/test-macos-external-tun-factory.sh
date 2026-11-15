#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == "Darwin" ]] || { echo 'ERROR: macOS required'; exit 1; }

# Full regression from published preparation milestone: still fail closed.
bash scripts/test-macos-provider-preparation.sh

CORE="$ROOT/.external/openvpn3"
PROBE="$ROOT/.external/macos-external-tun-factory-probe"
BUILD="$ROOT/.external/build-macos-external-tun-factory-probe"
mkdir -p "$PROBE"

# Separate experimental dylib. No OPENVPN_FORCE_TUN_NULL; the C++ Core will
# select ExternalTun::Factory, but connect remains blocked until full Apple I/O.
# Windows linker directives must not reach AppleClang's linker.
sed -e '/^target_link_options(mycodex_core PRIVATE/d' \
    -e 's/OPENVPN_FORCE_TUN_NULL/OPENVPN_EXTERNAL_TUN_FACTORY MYCODEX_EXTERNAL_TUN_FACTORY_TESTING/g' \
    tools/windows-swift-core-probe/CMakeLists.txt > "$PROBE/CMakeLists.txt"

grep -q 'OPENVPN_EXTERNAL_TUN_FACTORY MYCODEX_EXTERNAL_TUN_FACTORY_TESTING' "$PROBE/CMakeLists.txt"
if grep -q 'OPENVPN_FORCE_TUN_NULL' "$PROBE/CMakeLists.txt"; then
    echo 'ERROR: null tun must not be selected by the ExternalTun probe' >&2
    exit 1
fi
export PKG_CONFIG_PATH="$(brew --prefix openssl@3)/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
echo '=== CONFIGURE REAL OPENVPN3 EXTERNAL TUN FACTORY ==='
cmake -S "$PROBE" -B "$BUILD" -G Ninja \
    -DOPENVPN3_ROOT="$CORE" -DMYCODEX_SDK_ROOT="$ROOT" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$(brew --prefix)"
echo '=== COMPILE EXTERNAL TUN FACTORY (NO NULL TUN) ==='
cmake --build "$BUILD" --parallel 2

echo '=== COMPILE SWIFT EXTERNAL TUN PROBE ==='
swiftc -D MYCODEX_EXTERNAL_TUN_FACTORY_TESTING \
    -Xcc -DMYCODEX_EXTERNAL_TUN_FACTORY_TESTING \
    -I "$ROOT/tools/windows-swift-core-probe/COpenVPNBridge" \
    -L "$BUILD" -lmycodex_core \
    -Xlinker -rpath -Xlinker "$BUILD" \
    -o "$BUILD/mycodex_external_tun_probe" \
    tools/macos-external-tun-probe/main.swift

echo '=== TEST OPENVPN3 EXTERNAL TUN FACTORY SELECTION ==='
"$BUILD/mycodex_external_tun_probe"
echo '=== MYCODEX STEP 8.3B2D2A VERIFIED ==='
