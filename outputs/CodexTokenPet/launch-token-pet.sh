#!/bin/zsh
set -euo pipefail

APP_DIR="/Users/qianlve/Documents/Codex/2026-08-20/1-2-codex-token/outputs/CodexTokenPet"
APP_BIN="$APP_DIR/CodexTokenPet"

if [[ ! -x "$APP_BIN" || "$APP_DIR/CodexTokenPet.swift" -nt "$APP_BIN" ]]; then
  /usr/bin/swiftc -O -framework AppKit "$APP_DIR/CodexTokenPet.swift" -o "$APP_BIN"
fi

exec "$APP_BIN"
