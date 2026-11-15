#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == "Darwin" ]] || { echo 'ERROR: macOS required' >&2; exit 1; }

echo '=== PORTABLE SWIFT REGRESSION ==='
swift test
echo '=== RELEASE BUILD ==='
swift build -c release

echo '=== OPENVPN3 EXTERNAL TUN FACTORY REGRESSION ==='
bash scripts/test-macos-external-tun-factory.sh
BUILD="$ROOT/.external/build-macos-external-tun-factory-probe"
echo '=== COMPILE SWIFT SOCK_DGRAM TUN BRIDGE PROBE ==='
swiftc -I "$ROOT/tools/windows-swift-core-probe/COpenVPNBridge" \
  -L "$BUILD" -lmycodex_core -framework NetworkExtension \
  -Xlinker -rpath -Xlinker "$BUILD" \
  -o "$BUILD/mycodex_tun_socket_probe" \
  Sources/MYCODEX/AppleTunnelNetworkSettings.swift \
  Sources/MYCODEX/MYCODEXPacketBridge.swift \
  Sources/MYCODEX/MYCODEXTunSocketTransport.swift \
  tools/macos-tun-socket-probe/main.swift

echo '=== TEST NATIVE SOCKETPAIR DATAGRAM PACKET PATH ==='
"$BUILD/mycodex_tun_socket_probe"
echo '=== MYCODEX STEP 8.3B2D2B VERIFIED ==='
