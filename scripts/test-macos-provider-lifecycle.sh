#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [[ "$(uname -s)" != 'Darwin' ]]; then
    echo 'ERROR: macOS required' >&2
    exit 1
fi

echo '=== PREVIOUS OPENVPN3 / PACKET DRIVER NATIVE REGRESSION ==='
bash scripts/test-macos-packet-wakeup.sh

echo '=== PROVIDER LIFECYCLE XCTEST ==='
swift test --filter MYCODEXPacketTunnelSessionLifecycleTests

echo '=== RELEASE BUILD ==='
swift build -c release

echo '=== PARSE FAIL-CLOSED PACKET TUNNEL PROVIDER ==='
swiftc -frontend -parse Examples/PacketTunnelProvider/PacketTunnelProvider.swift

echo 'SWIFT_PROVIDER_LIFECYCLE_GUARDED=1'
echo 'SWIFT_PROVIDER_LIFECYCLE_GENERATIONS=1'
echo 'SWIFT_PROVIDER_LIFECYCLE_JOIN_BEFORE_RELEASE=1'
echo 'MYCODEX_PROVIDER_LIFECYCLE_TESTS_PASSED'
echo '=== MYCODEX STEP 8.3B2D2D3 VERIFIED ==='
