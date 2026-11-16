#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Examples/AppleExtension/MYCODEXExtensionExample.xcodeproj"
if [[ "${MYCODEX_SKIP_APPLE_EXTENSION_BUILD:-0}" != 1 ]]; then
    "$ROOT/scripts/build-apple-extension-example.sh"
fi

for variant in Debug-iphonesimulator Debug-iphoneos Release-iphonesimulator Release-iphoneos; do
    if [[ "$variant" == Debug-* ]]; then
        derived="$ROOT/.external/apple-extension-derived"
        binary=PacketTunnelExtension.debug.dylib
    else
        derived="$ROOT/.external/apple-extension-core-release-derived"
        binary=PacketTunnelExtension
    fi
    executable="$derived/Build/Products/$variant/PacketTunnelExtension.appex/$binary"
    [[ -f "$executable" ]] || { echo "Extension executable missing: $variant" >&2; exit 1; }
    for arch in $(xcrun lipo -archs "$executable"); do
        symbols="$(xcrun nm -arch "$arch" -gU "$executable")"
        for symbol in mycodex_bridge_core_linked mycodex_external_tun_factory_compiled \
                      mycodex_client_create mycodex_client_configure mycodex_client_start \
                      mycodex_client_tun_attach_fd mycodex_client_tun_wait_pending; do
            count="$(printf '%s\n' "$symbols" | grep -Ec " _${symbol}$" || true)"
            [[ "$count" == 1 ]] || { echo "Expected one $symbol in $variant/$arch; found $count" >&2; exit 1; }
        done
        demangled="$(xcrun nm -arch "$arch" -gU "$executable" | xcrun swift-demangle)"
        grep -q 'MYCODEXApplePacketTunnelSessionController.start(profileText:' <<< "$demangled" || {
            echo "Session controller missing: $variant/$arch" >&2; exit 1;
        }
        grep -q 'MYCODEXAppleOpenVPNRuntime.joinWorker()' <<< "$demangled" || {
            echo "Native worker orchestration missing: $variant/$arch" >&2; exit 1;
        }
    done
    if xcrun otool -L "$executable" | grep -Eq '/usr/local/|/opt/homebrew/|libmycodex_core\.dylib'; then
        echo "macOS/Homebrew library linked into $variant" >&2
        exit 1
    fi
    platform="$(xcrun vtool -show-build "$executable" | awk '/platform / { print $2; exit }')"
    if [[ "$variant" == *-iphoneos ]]; then
        [[ "$platform" == IOS ]] || { echo "Wrong device platform: $platform" >&2; exit 1; }
    else
        [[ "$platform" == IOSSIMULATOR ]] || { echo "Wrong simulator platform: $platform" >&2; exit 1; }
    fi
    echo "EXTENSION_CORE_SYMBOLS_$variant=1"
done

grep -q 'relativePath = "../../.external/ios-core-package";' \
    "$PROJECT/project.pbxproj"
grep -q 'path: "COpenVPNBridge.xcframework"' "$ROOT/.external/ios-core-package/Package.swift"
! grep -q 'OPENVPN_FORCE_TUN_NULL' "$ROOT/.external/ios-core-build/device/compile-flags.txt"
! grep -q 'OPENVPN_FORCE_TUN_NULL' "$ROOT/.external/ios-core-build/simulator_x86_64/compile-flags.txt"
! grep -q 'OPENVPN_FORCE_TUN_NULL' "$ROOT/.external/ios-core-build/simulator_arm64/compile-flags.txt"
for slice in device simulator_x86_64 simulator_arm64; do
    grep -q 'OPENVPN_EXTERNAL_TUN_FACTORY' "$ROOT/.external/ios-core-build/$slice/compile-flags.txt"
    ! grep -q 'MYCODEX_PRODUCTION_TUN_TRANSPORT_VERIFIED' "$ROOT/.external/ios-core-build/$slice/compile-flags.txt"
done
echo 'EXTERNAL_TUN_NO_NULL_OR_PRODUCTION_ENABLE=1'

destination="${MYCODEX_IOS_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
xcodebuild -project "$PROJECT" -scheme CoreLinkTests -configuration Debug \
    -destination "$destination" -derivedDataPath "$ROOT/.external/apple-extension-derived" \
    CODE_SIGNING_ALLOWED=NO test
echo 'MYCODEX_IOS_EXTENSION_CORE_LINK_PASSED'
