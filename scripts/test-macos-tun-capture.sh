#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == "Darwin" ]] || { echo 'ERROR: macOS required'; exit 1; }

# Run full existing native Core + Swift packet regression first.
bash scripts/test-macos-packet-bridge.sh

CORE="$ROOT/.external/openvpn3"
PROBE="$ROOT/.external/macos-tun-capture-probe"
BUILD="$ROOT/.external/build-macos-tun-capture-probe"
mkdir -p "$PROBE"
# Build a separate test-only dylib. Production does NOT export the synthetic
# TunBuilder test hook. OPENVPN_FORCE_TUN_NULL keeps networking disabled.
grep -v '^target_link_options(mycodex_core PRIVATE' \
  tools/windows-swift-core-probe/CMakeLists.txt | \
  sed 's/OPENVPN_FORCE_TUN_NULL)/OPENVPN_FORCE_TUN_NULL MYCODEX_TUN_CAPTURE_TESTING)/' > "$PROBE/CMakeLists.txt"
export PKG_CONFIG_PATH="$(brew --prefix openssl@3)/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

echo '=== CONFIGURE NATIVE TUN CAPTURE ==='
cmake -S "$PROBE" -B "$BUILD" -G Ninja \
  -DOPENVPN3_ROOT="$CORE" -DMYCODEX_SDK_ROOT="$ROOT" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$(brew --prefix)"
echo '=== COMPILE OPENVPN3 TUNBUILDER OVERRIDES ==='
cmake --build "$BUILD" --parallel 2

echo '=== BUILD SWIFT TUN CAPTURE PROBE ==='
swiftc -D MYCODEX_TUN_CAPTURE_TESTING -Xcc -DMYCODEX_TUN_CAPTURE_TESTING \
  -I "$ROOT/tools/windows-swift-core-probe/COpenVPNBridge" \
  -L "$BUILD" -lmycodex_core -framework NetworkExtension \
  -Xlinker -rpath -Xlinker "$BUILD" \
  -o "$BUILD/mycodex_tun_capture_probe" \
  Sources/MYCODEX/OpenVPNProfile.swift \
  Sources/MYCODEX/OpenVPNNativeBridge.swift \
  Sources/MYCODEX/OpenVPNProfileValidation.swift \
  Sources/MYCODEX/OpenVPNClient.swift \
  Sources/MYCODEX/AppleTunnelNetworkSettings.swift \
  Sources/MYCODEX/MYCODEXTunSettingsCapture.swift \
  tools/macos-tun-capture-probe/main.swift

echo '=== TEST CORE TUNBUILDER CALLBACK CAPTURE ==='
"$BUILD/mycodex_tun_capture_probe"
echo '=== MYCODEX MACOS TUN CAPTURE PASSED ==='
