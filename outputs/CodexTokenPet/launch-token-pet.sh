#!/bin/zsh
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BIN="$APP_DIR/CodexTokenPet"

if [[ ! -x "$APP_BIN" || "$APP_DIR/AemisLayeredRig.swift" -nt "$APP_BIN" || "$APP_DIR/UnifiedSpeech.swift" -nt "$APP_BIN" || "$APP_DIR/CodexTokenPet.swift" -nt "$APP_BIN" || "$APP_DIR/AemisCompanionWindows.swift" -nt "$APP_BIN" || "$APP_DIR/CodexTaskMonitor.swift" -nt "$APP_BIN" ]]; then
  /usr/bin/swiftc -O -framework AppKit -framework ApplicationServices -framework AVFoundation -framework Security -lsqlite3 "$APP_DIR"/*.swift -o "$APP_BIN"
fi

exec "$APP_BIN"
