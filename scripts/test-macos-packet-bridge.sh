#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
bash scripts/test-macos-swift-client.sh
BUILD="$ROOT/.external/build-macos-swift-core-probe"
echo "=== COMPILE NATIVE DUPLEX PACKET BRIDGE SWIFT PROBE ==="
swiftc -I "$ROOT/tools/windows-swift-core-probe/COpenVPNBridge" \
  -L "$BUILD" -lmycodex_core -framework NetworkExtension \
  -Xlinker -rpath -Xlinker "$BUILD" \
  -o "$BUILD/mycodex_packet_probe" \
  Sources/MYCODEX/AppleTunnelNetworkSettings.swift \
  Sources/MYCODEX/MYCODEXPacketBridge.swift \
  tools/macos-packet-probe/main.swift
echo "=== TEST NATIVE PACKET QUEUES ==="
"$BUILD/mycodex_packet_probe"
echo "=== MYCODEX MACOS PACKET BRIDGE PASSED ==="
