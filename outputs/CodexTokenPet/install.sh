#!/bin/zsh
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
target_dir="$HOME/Library/Application Support/CodexTokenPet"
mkdir -p "$target_dir"
/usr/bin/swiftc -O -framework AppKit -framework ApplicationServices -framework AVFoundation -framework Security -lsqlite3 "$source_dir"/*.swift -o "$source_dir/CodexTokenPet.next"
cp "$source_dir"/*.swift "$source_dir/launch-token-pet.sh" "$source_dir/prepare_voice_bank.py" "$target_dir/"
cp -R "$source_dir/assets" "$source_dir/voice-assets" "$target_dir/"
python3 "$target_dir/prepare_voice_bank.py" "$target_dir"
mv "$source_dir/CodexTokenPet.next" "$target_dir/CodexTokenPet"
chmod +x "$target_dir/CodexTokenPet" "$target_dir/launch-token-pet.sh"
mkdir -p "$HOME/Library/LaunchAgents"
plist="$HOME/Library/LaunchAgents/com.qianlve.codex-token-pet.plist"
/usr/bin/python3 - "$plist" "$target_dir" <<'PY'
import sys,plistlib
from pathlib import Path
p=Path(sys.argv[1]);d=sys.argv[2]
p.write_bytes(plistlib.dumps({'Label':'com.qianlve.codex-token-pet','ProgramArguments':[d+'/launch-token-pet.sh'],'RunAtLoad':True,'KeepAlive':True}))
PY
launchctl bootout "gui/$(id -u)/com.qianlve.codex-token-pet" 2>/dev/null || true
launchctl enable "gui/$(id -u)/com.qianlve.codex-token-pet"
launchctl bootstrap "gui/$(id -u)" "$plist"
echo 'Installed Aemis Token Pet.'
