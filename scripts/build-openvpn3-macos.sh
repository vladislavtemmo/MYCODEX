#!/usr/bin/env bash
set -euo pipefail

[[ "$(uname -s)" == "Darwin" ]] || { echo "Для сборки OpenVPN 3 Core требуется macOS" >&2; exit 1; }

for bin in brew cmake ninja git xcodebuild; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Отсутствует: $bin" >&2; exit 1; }
done

for pkg in asio fmt jsoncpp lz4 openssl@3 pkg-config xxhash; do
  brew list --versions "$pkg" 2>/dev/null | grep -q . || {
    echo "Отсутствует Homebrew пакет $pkg. Установите требуемые зависимости вручную." >&2
    exit 1
  }
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${MYCODEX_OPENVPN3_SOURCE:-$ROOT/.external/openvpn3}"
BUILD_DIR="${MYCODEX_OPENVPN3_BUILD_DIR:-$ROOT/.external/build-openvpn3-macos}"
"$ROOT/scripts/fetch-openvpn3.sh" "$SOURCE"

OPENSSL_ROOT="$(brew --prefix openssl@3)"
HOMEBREW_PREFIX="$(brew --prefix)"
cmake -S "$SOURCE" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_STANDARD=20 \
  -DOPENSSL_ROOT_DIR="$OPENSSL_ROOT" \
  -DCMAKE_PREFIX_PATH="$HOMEBREW_PREFIX"
cmake --build "$BUILD_DIR" --parallel 2

if [[ "${MYCODEX_RUN_CORE_TESTS:-0}" == "1" ]]; then
  ctest --test-dir "$BUILD_DIR" --output-on-failure
else
  echo "Core test suite не запускалась (MYCODEX_RUN_CORE_TESTS=1 для запуска)"
fi

echo "Готова исследовательская сборка OpenVPN 3 Core. К MYCODEX пока не подключена."
