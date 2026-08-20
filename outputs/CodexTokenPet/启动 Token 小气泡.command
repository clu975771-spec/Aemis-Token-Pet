#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BIN="$ROOT_DIR/CodexTokenPet"

if [[ ! -x "$APP_BIN" || "$ROOT_DIR/CodexTokenPet.swift" -nt "$APP_BIN" ]]; then
  /usr/bin/swiftc -O -framework AppKit "$ROOT_DIR/CodexTokenPet.swift" -o "$APP_BIN"
fi

exec "$APP_BIN"
