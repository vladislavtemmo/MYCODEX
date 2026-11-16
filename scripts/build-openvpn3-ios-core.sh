#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$ROOT/Dependencies/ios-core-sources.lock"
DOWNLOADS="$ROOT/.external/ios-core-downloads"
SOURCES="$ROOT/.external/ios-core-sources"
BUILD="$ROOT/.external/ios-core-build"
PACKAGE="$ROOT/.external/ios-core-package"
JOBS="${MYCODEX_IOS_BUILD_JOBS:-2}"

[[ "$(uname -s)" == Darwin ]] || { echo 'macOS required' >&2; exit 1; }
for command_name in curl git tar unzip shasum xcodebuild xcrun make libtool; do
    command -v "$command_name" >/dev/null || { echo "Missing $command_name" >&2; exit 1; }
done
"$ROOT/scripts/fetch-openvpn3.sh" "$ROOT/.external/openvpn3"
mkdir -p "$DOWNLOADS" "$SOURCES" "$BUILD" "$PACKAGE"

locked() { awk -F= -v key="$1" '$1 == key { print $2; exit }' "$LOCK"; }
fetch_archive() {
    local filename="$1" url="$2" expected="$3" target="$DOWNLOADS/$1"
    if [[ ! -f "$target" ]]; then
        curl --fail --location --retry 2 --silent --show-error "$url" -o "$target.tmp"
        mv "$target.tmp" "$target"
    fi
    printf '%s  %s\n' "$expected" "$target" | shasum -a 256 -c - >/dev/null
}

fetch_archive "openssl-$(locked openssl_version).tar.gz" \
    "https://github.com/openssl/openssl/releases/download/openssl-$(locked openssl_version)/openssl-$(locked openssl_version).tar.gz" \
    "$(locked openssl_sha256)"
fetch_archive "fmt-$(locked fmt_version).zip" \
    "https://github.com/fmtlib/fmt/releases/download/$(locked fmt_version)/fmt-$(locked fmt_version).zip" \
    "$(locked fmt_sha256)"
fetch_archive "lz4-$(locked lz4_version).tar.gz" \
    "https://github.com/lz4/lz4/archive/refs/tags/v$(locked lz4_version).tar.gz" \
    "$(locked lz4_sha256)"
fetch_archive "asio-$(locked asio_version).tar.bz2" \
    "https://downloads.sourceforge.net/project/asio/asio/$(locked asio_version)%20%28Stable%29/asio-$(locked asio_version).tar.bz2" \
    "$(locked asio_sha256)"

if [[ ! -d "$SOURCES/fmt-$(locked fmt_version)" ]]; then
    unzip -q "$DOWNLOADS/fmt-$(locked fmt_version).zip" -d "$SOURCES"
fi
if [[ ! -d "$SOURCES/lz4-$(locked lz4_version)" ]]; then
    tar -xzf "$DOWNLOADS/lz4-$(locked lz4_version).tar.gz" -C "$SOURCES"
fi
if [[ ! -d "$SOURCES/asio-$(locked asio_version)" ]]; then
    tar -xjf "$DOWNLOADS/asio-$(locked asio_version).tar.bz2" -C "$SOURCES"
fi

build_slice() {
    local name="$1" sdk="$2" arch="$3" openssl_target="$4" target="$5"
    local folder="$BUILD/$name" openssl="$BUILD/$name/openssl" objects="$BUILD/$name/objects"
    local sdk_path cxx cc
    sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
    cxx="$(xcrun --sdk "$sdk" --find clang++)"
    cc="$(xcrun --sdk "$sdk" --find clang)"
    mkdir -p "$folder" "$objects"
    if [[ ! -d "$openssl" ]]; then
        tar -xzf "$DOWNLOADS/openssl-$(locked openssl_version).tar.gz" -C "$folder"
        mv "$folder/openssl-$(locked openssl_version)" "$openssl"
    fi
    if [[ ! -f "$openssl/Makefile" ]]; then
        (cd "$openssl" && ./Configure "$openssl_target" no-shared no-tests no-apps no-asm \
            "--prefix=$folder/install" "$([[ "$sdk" == iphoneos ]] && printf '%s' '-miphoneos-version-min=16.0' || printf '%s' '-mios-simulator-version-min=16.0')")
    fi
    make -C "$openssl" -j "$JOBS" build_libs
    local common=(-O2 -fPIC -fapplication-extension -target "$target" -isysroot "$sdk_path")
    local includes=(-I "$ROOT/Sources/COpenVPNBridge/include" -I "$ROOT/.external/openvpn3"
        -I "$SOURCES/asio-$(locked asio_version)/include" -I "$openssl/include"
        -I "$SOURCES/fmt-$(locked fmt_version)/include" -I "$SOURCES/lz4-$(locked lz4_version)/lib")
    local defines=(-DMYCODEX_WITH_OPENVPN3 -DOPENVPN_EXTERNAL_TUN_FACTORY
        -DASIO_STANDALONE -DUSE_ASIO -DUSE_OPENSSL -DHAVE_LZ4)
    "$cxx" -x objective-c++ -std=c++20 "${common[@]}" "${includes[@]}" "${defines[@]}" \
        -c "$ROOT/Sources/COpenVPNBridge/MYCODEXBridge.cpp" -o "$objects/MYCODEXBridge.o"
    "$cxx" -std=c++20 "${common[@]}" "${includes[@]}" "${defines[@]}" \
        -c "$ROOT/Sources/COpenVPNBridge/MYCODEXPacketBridge.cpp" -o "$objects/MYCODEXPacketBridge.o"
    "$cxx" -std=c++20 "${common[@]}" "${includes[@]}" "${defines[@]}" \
        -c "$ROOT/Sources/COpenVPNBridge/MYCODEXTunSocketTransport.cpp" -o "$objects/MYCODEXTunSocketTransport.o"
    "$cxx" -std=c++20 "${common[@]}" "${includes[@]}" "${defines[@]}" \
        -c "$ROOT/.external/openvpn3/openvpn/crypto/data_epoch.cpp" -o "$objects/data_epoch.o"
    "$cxx" -std=c++20 "${common[@]}" "${includes[@]}" \
        -c "$SOURCES/fmt-$(locked fmt_version)/src/format.cc" -o "$objects/fmt_format.o"
    "$cxx" -std=c++20 "${common[@]}" "${includes[@]}" \
        -c "$SOURCES/fmt-$(locked fmt_version)/src/os.cc" -o "$objects/fmt_os.o"
    for source in lz4 lz4hc lz4frame xxhash; do
        "$cc" "${common[@]}" -I "$SOURCES/lz4-$(locked lz4_version)/lib" \
            -c "$SOURCES/lz4-$(locked lz4_version)/lib/$source.c" -o "$objects/$source.o"
    done
    xcrun libtool -static -o "$folder/libCOpenVPNBridge.a" "$objects"/*.o \
        "$openssl/libssl.a" "$openssl/libcrypto.a"
    xcrun lipo -info "$folder/libCOpenVPNBridge.a"
    printf '%s\n' "${defines[*]}" > "$folder/compile-flags.txt"
}

build_slice device iphoneos arm64 ios64-xcrun arm64-apple-ios16.0
build_slice simulator_x86_64 iphonesimulator x86_64 iossimulator-x86_64-xcrun x86_64-apple-ios16.0-simulator
build_slice simulator_arm64 iphonesimulator arm64 iossimulator-arm64-xcrun arm64-apple-ios16.0-simulator
xcrun lipo -create "$BUILD/simulator_x86_64/libCOpenVPNBridge.a" \
    "$BUILD/simulator_arm64/libCOpenVPNBridge.a" \
    -output "$BUILD/libCOpenVPNBridge-simulator.a"

HEADERS="$BUILD/Headers"
mkdir -p "$HEADERS"
cp "$ROOT/Sources/COpenVPNBridge/include/MYCODEXBridge.h" "$HEADERS/"
cat > "$HEADERS/module.modulemap" <<'EOF'
module COpenVPNBridge {
    header "MYCODEXBridge.h"
    export *
}
EOF
rm -rf "$PACKAGE/COpenVPNBridge.xcframework"
xcodebuild -create-xcframework \
    -library "$BUILD/device/libCOpenVPNBridge.a" -headers "$HEADERS" \
    -library "$BUILD/libCOpenVPNBridge-simulator.a" -headers "$HEADERS" \
    -output "$PACKAGE/COpenVPNBridge.xcframework"
mkdir -p "$PACKAGE/Sources/MYCODEX"
rsync -a --delete "$ROOT/Sources/MYCODEX/" "$PACKAGE/Sources/MYCODEX/"
cp "$ROOT/Examples/AppleExtension/CorePackage.swift" "$PACKAGE/Package.swift"
echo "iOS OpenVPN3 Core package ready: $PACKAGE"
