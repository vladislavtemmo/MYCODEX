#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == "Darwin" ]] || { echo 'ERROR: macOS required'; exit 1; }
echo '=== SWIFT TESTS INCLUDING APPLE FRAMEWORK ==='
swift test
echo '=== RELEASE BUILD ==='
swift build -c release
echo '=== PARSE PACKET TUNNEL PROVIDER SAMPLE ==='
swiftc -frontend -parse -parse-as-library Examples/PacketTunnelProvider/PacketTunnelProvider.swift
echo '=== NATIVE OPENVPN3 TUN CAPTURE REGRESSION ==='
bash scripts/test-macos-tun-capture.sh
echo '=== MYCODEX STEP 8.3B2D VERIFIED ==='
