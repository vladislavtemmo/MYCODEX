#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
bash scripts/test-macos-swift-core.sh
BUILD="$ROOT/.external/build-macos-swift-core-probe"
echo "=== COMPILE SWIFT NATIVE CLIENT PROBE ==="
swiftc -I "$ROOT/tools/windows-swift-core-probe/COpenVPNBridge" -L "$BUILD" -lmycodex_core -Xlinker -rpath -Xlinker "$BUILD" -o "$BUILD/mycodex_client_probe" Sources/MYCODEX/OpenVPNProfile.swift Sources/MYCODEX/OpenVPNNativeBridge.swift Sources/MYCODEX/OpenVPNProfileValidation.swift Sources/MYCODEX/OpenVPNClient.swift tools/macos-swift-client-probe/main.swift
echo "=== TEST NATIVE CLIENT CONFIGURATION ==="
"$BUILD/mycodex_client_probe"
echo "=== MYCODEX MACOS CLIENT PREPARATION PASSED ==="
