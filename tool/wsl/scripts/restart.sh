#!/usr/bin/env bash
# Restart active services while keeping the same data directory and credentials.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/service_lib.sh"
acquire_lock
VERSION="$(active_release)" || { echo "No active release to restart." >&2; exit 1; }
stop_all_services "$VERSION"
start_all_services "$VERSION"
