#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCKFILE="$PROJECT_ROOT/Dependencies/openvpn3.lock"
DESTINATION="${1:-$PROJECT_ROOT/.external/openvpn3}"

require_binary() {
  command -v "$1" >/dev/null 2>&1 || { echo "Ошибка: требуется $1" >&2; exit 1; }
}
require_binary git
require_binary awk

read_lock() {
  awk -F= -v key="$1" '$1 == key { print substr($0, index($0, "=")+1); exit }' "$LOCKFILE" | tr -d '\r'
}

EXPECTED_REPO="https://github.com/OpenVPN/openvpn3.git"
EXPECTED_SHA="$(read_lock revision)"
REPO="$(read_lock repository)"
if [[ "$REPO" != "$EXPECTED_REPO" || ! "$EXPECTED_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Ошибка: неверный репозиторий или SHA в openvpn3.lock" >&2
  exit 1
fi

mkdir -p "$(dirname "$DESTINATION")"
if [[ -e "$DESTINATION" && ! -d "$DESTINATION/.git" ]]; then
  echo "Ошибка: путь существует и не является Git-репозиторием: $DESTINATION" >&2
  exit 1
fi

if [[ ! -d "$DESTINATION/.git" ]]; then
  git init -q "$DESTINATION"
  git -C "$DESTINATION" remote add origin "$REPO"
fi

ACTUAL_ORIGIN="$(git -C "$DESTINATION" remote get-url origin)"
if [[ "$ACTUAL_ORIGIN" != "$EXPECTED_REPO" ]]; then
  echo "Ошибка: неожиданный origin: $ACTUAL_ORIGIN" >&2
  exit 1
fi

CURRENT_SHA="$(git -C "$DESTINATION" rev-parse HEAD 2>/dev/null || true)"
if [[ -n "$(git -C "$DESTINATION" status --porcelain 2>/dev/null)" ]]; then
  echo "Ошибка: в каталоге ядра есть незакоммиченные изменения; отмена безопасна" >&2
  exit 1
fi
if [[ "$CURRENT_SHA" != "$EXPECTED_SHA" ]]; then
  git -C "$DESTINATION" fetch --depth=1 origin "$EXPECTED_SHA"
  git -C "$DESTINATION" checkout --detach "$EXPECTED_SHA"
fi

ACTUAL_SHA="$(git -C "$DESTINATION" rev-parse HEAD)"
[[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]] || { echo "Ошибка: несовпадение SHA" >&2; exit 1; }
for path in client/ovpncli.hpp CMakeLists.txt LICENSE.md; do
  [[ -f "$DESTINATION/$path" ]] || { echo "Ошибка: отсутствует upstream файл $path" >&2; exit 1; }
done

echo "Подтверждён upstream: $ACTUAL_SHA"
echo "Локальный путь: $DESTINATION"
echo "ВНИМАНИЕ: проверка лицензирования и сборки для Apple ещё необходима"
