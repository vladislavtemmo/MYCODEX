#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == 'Darwin' ]] || { echo 'macOS required' >&2; exit 1; }

echo '=== SWIFT UNIT / RELEASE / CORE REGRESSION ==='
bash scripts/test-macos-tun-settings-ack.sh
BUILD="$ROOT/.external/build-macos-tun-fd-handoff-probe"

echo '=== COMPILE NATIVE PACKET WAKEUP PROBE ==='
swiftc \
  -I "$ROOT/tools/windows-swift-core-probe/COpenVPNBridge" \
  -L "$BUILD" -lmycodex_core -framework NetworkExtension \
  -Xlinker -rpath -Xlinker "$BUILD" \
  -o "$BUILD/mycodex_packet_wakeup_probe" \
  Sources/MYCODEX/AppleTunnelNetworkSettings.swift \
  Sources/MYCODEX/MYCODEXPacketBridge.swift \
  Sources/MYCODEX/MYCODEXTunSocketTransport.swift \
  tools/macos-packet-wakeup-probe/main.swift

echo '=== TEST NATIVE READINESS NOTIFICATIONS ==='
"$BUILD/mycodex_packet_wakeup_probe"

echo '=== PARSE PACKET TUNNEL PROVIDER SAMPLE ==='
swiftc -frontend -parse Examples/PacketTunnelProvider/PacketTunnelProvider.swift

echo '=== MYCODEX STEP 8.3B2D2D2 VERIFIED ==='
