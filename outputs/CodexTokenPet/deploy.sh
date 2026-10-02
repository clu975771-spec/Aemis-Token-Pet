#!/bin/zsh
set -euo pipefail
exec /bin/zsh "$(cd "$(dirname "$0")" && pwd)/install.sh"
