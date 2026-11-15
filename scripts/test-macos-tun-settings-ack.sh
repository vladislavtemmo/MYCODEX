#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == 'Darwin' ]] || { echo 'ERROR: macOS required' >&2; exit 1; }

echo '=== SWIFT UNIT TESTS ==='
swift test
echo '=== SWIFT RELEASE BUILD ==='
swift build -c release

echo '=== OPENVPN3 FD HANDOFF NATIVE REGRESSION ==='
bash scripts/test-macos-tun-fd-handoff.sh

BUILD="$ROOT/.external/build-macos-tun-fd-handoff-probe"
echo '=== COMPILE SWIFT TUN SETTINGS ACK PROBE ==='
swiftc \
  -I "$ROOT/tools/windows-swift-core-probe/COpenVPNBridge" \
  -L "$BUILD" -lmycodex_core -framework NetworkExtension \
  -Xlinker -rpath -Xlinker "$BUILD" \
  -o "$BUILD/mycodex_native_settings_ack_probe" \
  Sources/MYCODEX/OpenVPNProfile.swift \
  Sources/MYCODEX/OpenVPNNativeBridge.swift \
  Sources/MYCODEX/OpenVPNProfileValidation.swift \
  Sources/MYCODEX/OpenVPNClient.swift \
  Sources/MYCODEX/AppleTunnelNetworkSettings.swift \
  Sources/MYCODEX/MYCODEXPacketBridge.swift \
  Sources/MYCODEX/MYCODEXTunSocketTransport.swift \
  Sources/MYCODEX/MYCODEXTunSettingsCapture.swift \
  Sources/MYCODEX/MYCODEXTunFDAcknowledgement.swift \
  tools/macos-tun-fd-settings-ack-probe/main.swift

echo '=== VERIFY NATIVE SWIFT TO OPENVPN3 HANDOFF ==='
"$BUILD/mycodex_native_settings_ack_probe"
echo '=== MYCODEX STEP 8.3B2D2D1 VERIFIED ==='
