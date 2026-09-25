#!/usr/bin/env bash
# Import a matched immutable source/admin pair into a versioned release folder.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/common.sh"

if (($# != 3)); then
  echo "Usage: $0 VERSION SOURCE.zip ADMIN.zip" >&2
  exit 2
fi
VERSION="$1"
SOURCE_ZIP="$(realpath -e -- "$2")"
ADMIN_ZIP="$(realpath -e -- "$3")"
valid_release_id "$VERSION" || { echo "Invalid version identifier: $VERSION" >&2; exit 2; }
[[ -f "$SOURCE_ZIP" && -f "$ADMIN_ZIP" ]] || { echo "Both release archives must be regular files." >&2; exit 2; }

ensure_layout
acquire_lock
FINAL_DIR="$(release_dir "$VERSION")"
if [[ -e "$FINAL_DIR" ]]; then
  echo "Release already exists and is immutable: $FINAL_DIR" >&2
  exit 1
fi
STAGE_DIR="$RELEASES_DIR/.import-${VERSION}-$$"
cleanup() { rm -rf -- "$STAGE_DIR"; }
trap cleanup EXIT
mkdir -m 700 "$STAGE_DIR"

validate_archive_paths() {
  local archive="$1" entry component
  unzip -tqq "$archive"
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    [[ "$entry" != /* && "$entry" != *\\* && "$entry" != *:* ]] || {
      echo "Unsafe archive path in $archive: $entry" >&2; return 1;
    }
    IFS='/' read -r -a parts <<< "$entry"
    for component in "${parts[@]}"; do
      [[ "$component" != ".." ]] || { echo "Unsafe archive path in $archive: $entry" >&2; return 1; }
    done
  done < <(unzip -Z1 "$archive")
}

validate_archive_paths "$SOURCE_ZIP"
validate_archive_paths "$ADMIN_ZIP"
mkdir "$STAGE_DIR/server" "$STAGE_DIR/admin"
unzip -q "$SOURCE_ZIP" -d "$STAGE_DIR/server"
unzip -q "$ADMIN_ZIP" -d "$STAGE_DIR/admin"
[[ -f "$STAGE_DIR/server/tool/local_sync_server.dart" &&
   -f "$STAGE_DIR/server/tool/backup_utility.dart" &&
   -f "$STAGE_DIR/server/pubspec.yaml" &&
   -f "$STAGE_DIR/admin/index.html" ]] || {
  echo "Archives do not contain the expected server source and admin site." >&2
  exit 1
}
printf '{\n  "version": "%s",\n  "sourceSha256": "%s",\n  "adminSha256": "%s"\n}\n' \
  "$VERSION" "$(sha256sum "$SOURCE_ZIP" | cut -d' ' -f1)" \
  "$(sha256sum "$ADMIN_ZIP" | cut -d' ' -f1)" > "$STAGE_DIR/release.json"
chmod -R go-w "$STAGE_DIR"
mv -- "$STAGE_DIR" "$FINAL_DIR"
echo "Imported immutable release $VERSION to $FINAL_DIR"
echo "Activate it with scripts/activate_release.sh $VERSION"
