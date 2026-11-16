#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v xcodegen >/dev/null || { echo 'xcodegen required' >&2; exit 1; }
if [[ "${MYCODEX_SKIP_IOS_CORE_BUILD:-0}" == 1 ]]; then
  [[ -d "$ROOT/.external/ios-core-package/COpenVPNBridge.xcframework" ]] || {
    echo 'iOS Core XCFramework missing' >&2; exit 1;
  }
else
  "$ROOT/scripts/build-openvpn3-ios-core.sh"
fi
xcodegen -s "$ROOT/Examples/AppleExtension/project.yml"
for configuration in Debug Release; do
  if [[ "$configuration" == Debug ]]; then
    derived="$ROOT/.external/apple-extension-derived"
  else
    derived="$ROOT/.external/apple-extension-core-release-derived"
  fi
  for destination in 'generic/platform=iOS Simulator' 'generic/platform=iOS'; do
    xcodebuild -project "$ROOT/Examples/AppleExtension/MYCODEXExtensionExample.xcodeproj" \
      -scheme PacketTunnelExtension -configuration "$configuration" \
      -destination "$destination" -derivedDataPath "$derived" \
      CODE_SIGNING_ALLOWED=NO build
  done
done
