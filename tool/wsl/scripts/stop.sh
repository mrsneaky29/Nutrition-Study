#!/usr/bin/env bash
# Stop only the selected release processes after verifying their command lines.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/service_lib.sh"
acquire_lock
VERSION="$(active_release)" || {
  echo "No valid active release marker; refusing to signal an unknown process." >&2
  exit 1
}
stop_all_services "$VERSION"
