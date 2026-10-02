#!/bin/zsh
set -euo pipefail
source_dir="$(cd "$(dirname "$0")/.." && pwd)"
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
/usr/bin/swiftc -lsqlite3 "$source_dir/CodexTaskMonitor.swift" "$source_dir/tests/MonitorFixture.swift" -o "$fixture_dir/monitor-test"
"$fixture_dir/monitor-test" "$fixture_dir"
/usr/bin/swiftc "$source_dir/PetDisplayPlacement.swift" "$source_dir/tests/DisplayPlacementFixture.swift" -o "$fixture_dir/display-placement-test"
"$fixture_dir/display-placement-test"
python3 "$source_dir/tests/check_boosted_task_alerts.py"
