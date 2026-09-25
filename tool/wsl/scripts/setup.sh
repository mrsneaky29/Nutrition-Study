#!/usr/bin/env bash
# Initialize the persistent WSL deployment home without touching study records.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/common.sh"

missing=()
for command_name in awk bash curl dart flock findmnt node sha256sum ss stat unzip; do
  command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
done
if ((${#missing[@]})); then
  printf 'Missing required tools: %s\n' "${missing[*]}" >&2
  echo "Install them in Ubuntu, then rerun scripts/setup.sh. Dart SDK installation instructions: https://dart.dev/get-dart" >&2
  exit 1
fi

ensure_layout
init_credentials
echo "WSL deployment home is ready: $DEPLOY_HOME"
echo "Persistent records: $RECORDS_DIR"
echo "Credentials were generated once (or retained) at $CREDENTIALS_FILE with mode 600."
echo "Next: verify release archive checksums, then run scripts/import_release.sh VERSION SOURCE.zip ADMIN.zip."
