#!/usr/bin/env bash
#
# rollback.sh: Rolls back to previous release using activate-release.sh,
# ensuring full health check verification and error propagation.
#
set -euo pipefail

ROOT=${VPS_ROOT:-/opt/plus5-vps}
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

target=${1:-}
if [[ -z "$target" ]]; then
  if [[ ! -L "$ROOT/previous" && ! -d "$ROOT/previous" ]]; then
    echo "Error: No previous release pointer exists at $ROOT/previous" >&2
    exit 1
  fi
  if command -v realpath >/dev/null 2>&1; then
    resolved=$(realpath "$ROOT/previous")
  else
    resolved=$(readlink -f "$ROOT/previous")
  fi
  target=${resolved##*/}
fi

echo "==> Rolling back to release '$target' via activate-release.sh..."
exec "$script_dir/activate-release.sh" "$target"
