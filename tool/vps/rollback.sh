#!/usr/bin/env bash
set -euo pipefail

ROOT=${VPS_ROOT:-/opt/plus5-vps}
target=${1:-}
if [[ -z $target ]]; then
  [[ -L "$ROOT/previous" ]] || { echo "No previous release pointer exists" >&2; exit 1; }
  resolved=$(readlink -f "$ROOT/previous")
  target=${resolved##*/}
fi
exec "$(dirname "$0")/activate-release.sh" "$target"
