#!/usr/bin/env bash
# Start the selected release's sync and admin services after readiness checks.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/service_lib.sh"
acquire_lock
VERSION="$(active_release)" || { echo "No active release; import and activate one first." >&2; exit 1; }
start_all_services "$VERSION"
echo "Persistent records stay at $RECORDS_DIR."
