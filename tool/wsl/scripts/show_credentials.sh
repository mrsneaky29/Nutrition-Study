#!/usr/bin/env bash
# Reveal keys only to an interactive terminal, then clear the display.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/common.sh"
if [[ ! -t 0 || ! -t 1 ]]; then
  echo "Refusing to print credentials when stdin/stdout is redirected." >&2
  exit 1
fi
init_credentials
printf '\nCollector number: 1\nCollector key: %s\nAdministrator key: %s\n\n' \
  "${LOCAL_SYNC_COLLECTOR_KEYS#*:}" "$LOCAL_SYNC_ADMIN_KEY"
read -r -p 'Press Enter to clear this terminal...' _
clear
echo "Credential display cleared."
