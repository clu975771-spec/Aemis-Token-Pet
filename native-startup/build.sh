#!/bin/zsh
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
bundle="$root/build/Codex 爱弥斯.app"
resources="$bundle/Contents/Resources"
mkdir -p "$resources" "$bundle/Contents/MacOS"
/usr/bin/swiftc -O -framework AppKit -framework AVFoundation -framework AVKit -framework ApplicationServices "$root/Sources/main.swift" -o "$bundle/Contents/MacOS/AemeathStartup"
for name in startup.mp4 wallpaper.png wallpaper-bridge.mjs theme.css motion.js enhancements.js; do cp "$root/$name" "$resources/"; done
cp "$root/audio/startup-voice-v2.wav" "$resources/startup-voice.wav"
node_path="$(command -v node)"
cp "$node_path" "$resources/node"
python3 - "$bundle/Contents/Info.plist" <<'PY'
import plistlib,sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleExecutable':'AemeathStartup','CFBundleIdentifier':'local.qianlve.aemeath-startup','CFBundleName':'Codex 爱弥斯','CFBundlePackageType':'APPL','LSUIElement':True,'CFBundleURLTypes':[{'CFBundleURLSchemes':['codex-aemeath']}]}))
PY
codesign --force --deep --sign - "$bundle"
echo "$bundle"
