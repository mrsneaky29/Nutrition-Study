#!/usr/bin/env bash
# Switch the server and admin site to one version while retaining shared data/keys.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/service_lib.sh"

if (($# != 1)) || ! valid_release_id "${1:-}"; then
  echo "Usage: $0 VERSION" >&2
  exit 2
fi
NEXT_VERSION="$1"
validate_release "$NEXT_VERSION"
acquire_lock
PREVIOUS_VERSION=""
if [[ -f "$ACTIVE_RELEASE_FILE" ]]; then PREVIOUS_VERSION="$(active_release)"; fi

if [[ -n "$PREVIOUS_VERSION" ]]; then
  service_paths "$PREVIOUS_VERSION"
  stop_all_services "$PREVIOUS_VERSION"
fi

write_active_version() {
  local version="$1" temp="$ACTIVE_RELEASE_FILE.tmp.$$"
  printf '%s\n' "$version" > "$temp"
  chmod 600 "$temp"
  mv -f -- "$temp" "$ACTIVE_RELEASE_FILE"
}

write_active_version "$NEXT_VERSION"
if start_all_services "$NEXT_VERSION"; then
  echo "Active release is now $NEXT_VERSION; persistent records and credentials remain at $DEPLOY_HOME."
  exit 0
fi

echo "Release $NEXT_VERSION failed startup; attempting rollback." >&2
stop_all_services "$NEXT_VERSION" || true
if [[ -n "$PREVIOUS_VERSION" ]]; then
  write_active_version "$PREVIOUS_VERSION"
  if start_all_services "$PREVIOUS_VERSION"; then
    echo "Rolled back to $PREVIOUS_VERSION." >&2
  else
    echo "Rollback to $PREVIOUS_VERSION also failed. Leave services stopped and inspect logs." >&2
  fi
else
  rm -f -- "$ACTIVE_RELEASE_FILE"
fi
exit 1
