#!/usr/bin/env bash
set -euo pipefail

ROOT=${VPS_ROOT:-/opt/plus5-vps}
SERVICE_NAME=${VPS_SERVICE_NAME:-plus5-vps}
ACCOUNT=${VPS_ACCOUNT:-plus5-vps}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 BACKUP_DIR [TARGET_STATE_DIR]" >&2
  exit 2
fi

backup_input="$1"
target_dir="${2:-${VPS_STATE_DIR:-/var/lib/plus5-vps/state}}"

# Reject paths containing directory traversal ('..')
if [[ "$backup_input" =~ \.\. ]]; then
  echo "Error: Directory traversal ('..') detected in backup path: $backup_input" >&2
  exit 1
fi

if [[ "$target_dir" =~ \.\. ]]; then
  echo "Error: Directory traversal ('..') detected in target path: $target_dir" >&2
  exit 1
fi

canonical_path() {
  local target="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath -m "$target"
  elif command -v readlink >/dev/null 2>&1; then
    readlink -m "$target" 2>/dev/null || (cd "$target" 2>/dev/null && pwd -P) || echo "$target"
  else
    (cd "$target" 2>/dev/null && pwd -P) || echo "$target"
  fi
}

if [[ ! -d "$backup_input" ]]; then
  echo "Error: Backup directory does not exist: $backup_input" >&2
  exit 1
fi

backup_dir_real=$(canonical_path "$backup_input")
manifest_file="$backup_dir_real/SHA256SUMS"

if [[ ! -f "$manifest_file" ]]; then
  echo "Error: SHA256SUMS manifest not found in $backup_dir_real" >&2
  candidate_subdirs=( "$backup_dir_real"/backup_* )
  if [[ -d "${candidate_subdirs[0]:-}" ]]; then
    echo "Hint: Did you specify a parent backup folder? Available backups inside:" >&2
    for d in "${candidate_subdirs[@]}"; do
      [[ -d "$d" ]] && echo "  $d" >&2
    done
  fi
  exit 1
fi

# Reject if target is a symbolic link
if [[ -L "$target_dir" ]]; then
  echo "Error: Target state directory cannot be a symbolic link: $target_dir" >&2
  exit 1
fi

target_dir_real=$(canonical_path "$target_dir")

is_unsafe_target() {
  local p="$1"
  p="${p%/}"
  [[ -z "$p" ]] && return 0

  case "$p" in
    "" | "/" | "/bin" | "/boot" | "/dev" | "/etc" | "/home" | "/lib" | "/lib32" | "/lib64" | "/libx32" | \
    "/media" | "/mnt" | "/opt" | "/proc" | "/root" | "/run" | "/sbin" | "/srv" | "/sys" | "/tmp" | \
    "/usr" | "/usr/bin" | "/usr/include" | "/usr/lib" | "/usr/local" | "/usr/sbin" | "/usr/share" | "/usr/src" | \
    "/var" | "/var/backups" | "/var/cache" | "/var/lib" | "/var/local" | "/var/lock" | "/var/log" | "/var/mail" | "/var/opt" | "/var/run" | "/var/spool" | "/var/tmp" )
      return 0
      ;;
  esac

  # Windows drive roots if in MSYS/Git Bash (e.g. /c, C:)
  if [[ "$p" =~ ^/[a-zA-Z]$ || "$p" =~ ^[a-zA-Z]:/?$ ]]; then
    return 0
  fi

  # Reject broad top-level single directory directly under root (e.g. /state, /data)
  local stripped="${p#/}"
  if [[ "$stripped" != *"/"* ]]; then
    return 0
  fi

  return 1
}

if is_unsafe_target "$target_dir_real"; then
  echo "Error: Target directory ($target_dir_real) is broad, unsafe, or a system root directory." >&2
  echo "Target must be a dedicated state directory (e.g. /var/lib/plus5-vps/state or a specific dedicated subpath)." >&2
  exit 1
fi

# Reject overlapping paths
if [[ "$backup_dir_real" == "$target_dir_real" || \
      "$backup_dir_real" == "$target_dir_real"/* || \
      "$target_dir_real" == "$backup_dir_real"/* ]]; then
  echo "Error: Source backup directory and target state directory cannot be identical or overlapping." >&2
  echo "  Backup: $backup_dir_real" >&2
  echo "  Target: $target_dir_real" >&2
  exit 1
fi

validate_records_file() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  [[ -s "$file" ]] || return 1

  local py_cmd=""
  if python3 -c "import sys; sys.exit(0)" >/dev/null 2>&1; then
    py_cmd="python3"
  elif python -c "import sys; sys.exit(0)" >/dev/null 2>&1; then
    py_cmd="python"
  fi

  if [[ -n "$py_cmd" ]]; then
    "$py_cmd" -c "import json, sys; d = json.load(sys.stdin); sys.exit(0 if isinstance(d, list) else 1)" < "$file" 2>/dev/null || return 1
  elif command -v jq >/dev/null 2>&1; then
    jq -e 'type == "array"' "$file" >/dev/null 2>&1 || return 1
  elif command -v node >/dev/null 2>&1; then
    node -e "const d = JSON.parse(require('fs').readFileSync(0, 'utf8')); process.exit(Array.isArray(d) ? 0 : 1);" < "$file" 2>/dev/null || return 1
  else
    local content
    content=$(tr -d ' \t\r\n' < "$file")
    [[ "$content" == \[*\] ]] || return 1
  fi
  return 0
}

# State tracking variables for rollback & cleanup
restore_success=0
swapped=0
target_created=0
service_was_active=0
staging_dir=""
swap_dir=""
safety_dir=""

rollback_and_cleanup() {
  local exit_code=$?
  if [[ $restore_success -eq 1 ]]; then
    [[ -n "$staging_dir" && -d "$staging_dir" ]] && rm -rf "$staging_dir"
    [[ -n "$swap_dir" && -d "$swap_dir" ]] && rm -rf "$swap_dir"
    exit 0
  fi

  echo "==================================================" >&2
  echo "RESTORE FAILED - INITIATING RECOVERY / ROLLBACK" >&2
  echo "==================================================" >&2

  if [[ $swapped -eq 1 && -n "$swap_dir" && -d "$swap_dir" ]]; then
    echo "Rolling back: restoring previous target state from swap directory ($swap_dir)..." >&2
    rm -rf "$target_dir_real"
    mv "$swap_dir" "$target_dir_real"
    echo "Rollback from swap directory completed." >&2
  elif [[ -n "$safety_dir" && -d "$safety_dir" ]]; then
    echo "Rolling back: restoring state from pre-restore safety backup ($safety_dir)..." >&2
    rm -rf "$target_dir_real"
    mkdir -p "$target_dir_real"
    (
      cd "$safety_dir"
      tar --exclude='SHA256SUMS' -cf - . | (cd "$target_dir_real" && tar -xf -)
    )
    echo "Rollback from safety backup completed." >&2
  elif [[ $target_created -eq 1 && -d "$target_dir_real" ]]; then
    echo "Rolling back: removing partially initialized target directory..." >&2
    rm -rf "$target_dir_real"
  fi

  if [[ $service_was_active -eq 1 ]]; then
    echo "Restarting service $SERVICE_NAME..." >&2
    if command -v systemctl >/dev/null 2>&1; then
      if systemctl start "$SERVICE_NAME"; then
        echo "Service $SERVICE_NAME restarted successfully." >&2
      else
        echo "Warning: Service $SERVICE_NAME failed to restart after rollback!" >&2
      fi
    fi
  fi

  if [[ -n "$staging_dir" && -d "$staging_dir" ]]; then
    rm -rf "$staging_dir"
  fi

  echo "Rollback Status: RESTORE FAILED - AUTOMATIC ROLLBACK COMPLETED" >&2
  if [[ $exit_code -eq 0 ]]; then
    exit 1
  else
    exit "$exit_code"
  fi
}

trap rollback_and_cleanup EXIT

echo "Step 1: Staging backup in isolated directory before touching target state..."
target_parent=$(dirname "$target_dir_real")
staging_base="$target_parent"
[[ -d "$staging_base" && -w "$staging_base" ]] || staging_base="${TMPDIR:-/tmp}"
staging_dir=$(mktemp -d "$staging_base/.restore_staging_XXXXXX")
chmod 0700 "$staging_dir" 2>/dev/null || true
staging_dir_real=$(canonical_path "$staging_dir")

(
  cd "$backup_dir_real"
  tar --exclude='restore_in_progress.json' \
      -cf - . | (cd "$staging_dir_real" && tar -xf -)
)

echo "Auditing symbolic links in staging directory..."
while IFS= read -r -d '' link_file; do
  target_link=$(readlink "$link_file" 2>/dev/null || true)
  resolved_link=$(canonical_path "$link_file")
  if [[ "$resolved_link" != "$staging_dir_real"/* ]]; then
    echo "Error: Backup staging contains unsafe symlink pointing outside staging: $link_file -> $target_link" >&2
    exit 1
  fi
  if [[ "$target_link" =~ \.\. ]]; then
    echo "Error: Backup staging contains symlink with directory traversal: $link_file -> $target_link" >&2
    exit 1
  fi
done < <(find "$staging_dir_real" -type l -print0)

if [[ ! -f "$staging_dir_real/SHA256SUMS" ]]; then
  echo "Error: SHA256SUMS manifest missing in staging directory!" >&2
  exit 1
fi

echo "Verifying backup integrity in staging directory..."
if ! (cd "$staging_dir_real" && sha256sum -c SHA256SUMS); then
  echo "Error: Backup integrity check failed in staging directory! Aborting restore." >&2
  exit 1
fi
echo "Backup integrity verified: all checksums matched in staging."

found_valid_records=0
if [[ -f "$staging_dir_real/records.json" ]]; then
  if validate_records_file "$staging_dir_real/records.json"; then
    found_valid_records=1
  else
    echo "Error: staging records.json is empty or not a valid JSON list." >&2
    exit 1
  fi
fi

if [[ -f "$staging_dir_real/.local_data/records.json" ]]; then
  if validate_records_file "$staging_dir_real/.local_data/records.json"; then
    found_valid_records=1
  else
    echo "Error: staging .local_data/records.json is empty or not a valid JSON list." >&2
    exit 1
  fi
fi

if [[ $found_valid_records -ne 1 ]]; then
  echo "Error: Backup is empty or missing valid state files (records.json or .local_data/records.json)." >&2
  exit 1
fi

# Normalize .local_data inside staging directory
if [[ -f "$staging_dir_real/records.json" && ! -f "$staging_dir_real/.local_data/records.json" ]]; then
  mkdir -p "$staging_dir_real/.local_data"
  cp -p "$staging_dir_real/records.json" "$staging_dir_real/.local_data/records.json"
  if [[ -f "$staging_dir_real/conflicts.json" && ! -f "$staging_dir_real/.local_data/conflicts.json" ]]; then
    cp -p "$staging_dir_real/conflicts.json" "$staging_dir_real/.local_data/conflicts.json"
  fi
elif [[ -f "$staging_dir_real/.local_data/records.json" && ! -f "$staging_dir_real/records.json" ]]; then
  cp -p "$staging_dir_real/.local_data/records.json" "$staging_dir_real/records.json"
  if [[ -f "$staging_dir_real/.local_data/conflicts.json" && ! -f "$staging_dir_real/conflicts.json" ]]; then
    cp -p "$staging_dir_real/.local_data/conflicts.json" "$staging_dir_real/conflicts.json"
  fi
fi

if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$SERVICE_NAME"; then
  service_was_active=1
  echo "Step 2: Service $SERVICE_NAME is active. Stopping service..."
  systemctl stop "$SERVICE_NAME"
fi

has_records=0
if [[ -d "$target_dir_real" ]]; then
  if [[ -f "$target_dir_real/records.json" || \
        -f "$target_dir_real/.local_data/records.json" || \
        -f "$target_dir_real/conflicts.json" || \
        -f "$target_dir_real/.local_data/conflicts.json" ]]; then
    has_records=1
  elif find "$target_dir_real" -maxdepth 2 -name '*.json' 2>/dev/null | grep -q .; then
    has_records=1
  fi
fi

safety_dir=""
safety_timestamp=$(date -u +%Y%m%d_%H%M%S)

if [[ $has_records -eq 1 ]]; then
  if [[ -n "${VPS_SAFETY_BACKUP_DIR:-}" ]]; then
    safety_base="$VPS_SAFETY_BACKUP_DIR"
  else
    safety_base="$target_parent/pre_restore_safety_backups"
  fi

  if [[ "$safety_base" == "$target_dir_real" || "$safety_base" == "$target_dir_real"/* ]]; then
    echo "Error: Safety backup base directory ($safety_base) cannot be inside target state directory ($target_dir_real)." >&2
    exit 1
  fi

  mkdir -p "$safety_base"
  chmod 0700 "$safety_base" 2>/dev/null || true
  safety_dir="$safety_base/safety_backup_${safety_timestamp}_$$"

  echo "Step 3: Target state directory contains existing records."
  echo "        Creating automatic rollback safety snapshot in: $safety_dir"
  mkdir -p "$safety_dir"
  chmod 0700 "$safety_dir" 2>/dev/null || true

  (
    cd "$target_dir_real"
    tar --exclude='pre_restore_safety_backup*' \
        --exclude='*.tmp*' \
        --exclude='*.pre_swap*' \
        --exclude='restore_in_progress.json' \
        -cf - . | (cd "$safety_dir" && tar -xf -)
  )

  (
    cd "$safety_dir"
    find . -type f ! -name 'SHA256SUMS' | LC_ALL=C sort | while IFS= read -r f; do
      sha256sum "$f"
    done > SHA256SUMS
    sha256sum -c --status SHA256SUMS
  )

  find "$safety_dir" -type d -exec chmod 0700 {} + 2>/dev/null || true
  find "$safety_dir" -type f -exec chmod 0600 {} + 2>/dev/null || true
  if [[ $(id -u) -eq 0 ]] && id "$ACCOUNT" >/dev/null 2>&1; then
    chown -R "$ACCOUNT:$ACCOUNT" "$safety_dir" 2>/dev/null || true
  fi
  echo "Safety snapshot created and verified at $safety_dir"
else
  echo "Step 3: Target state directory does not contain existing records. Skipping safety snapshot."
fi

echo "Step 4: Performing clean replacement of target state from verified staging..."
swap_dir="${target_dir_real}.pre_swap.${safety_timestamp}_$$"

if [[ -d "$target_dir_real" ]]; then
  mv "$target_dir_real" "$swap_dir"
  swapped=1
else
  target_created=1
fi

mv "$staging_dir_real" "$target_dir_real"
staging_dir=""

# Optional test hook to simulate failure after swap
if [[ -n "${_VPS_RESTORE_FAIL_POINT:-}" && "${_VPS_RESTORE_FAIL_POINT:-}" == "after_swap" ]]; then
  echo "Test hook: simulating failure after swap..." >&2
  exit 42
fi

echo "Step 5: Setting permissions and ownership..."
if [[ $(id -u) -eq 0 ]] && id "$ACCOUNT" >/dev/null 2>&1; then
  chown -R "$ACCOUNT:$ACCOUNT" "$target_dir_real"
fi

find "$target_dir_real" -type d -exec chmod 0700 {} + 2>/dev/null || chmod 0700 "$target_dir_real" 2>/dev/null || true
find "$target_dir_real" -type f -exec chmod 0600 {} + 2>/dev/null || true
if [[ -d "$target_dir_real/.local_data" ]]; then
  chmod 0700 "$target_dir_real/.local_data" 2>/dev/null || true
fi

echo "Step 6: Verifying final restored files and checksums..."
manifest_file="$target_dir_real/SHA256SUMS"
if [[ ! -f "$manifest_file" ]]; then
  manifest_file="$backup_dir_real/SHA256SUMS"
fi

restore_verified=1
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue

  expected_hash="${line%% *}"
  rel_path="${line#* }"
  rel_path="${rel_path# }"
  rel_path="${rel_path#\*}"
  clean_path="${rel_path#./}"

  if [[ "$clean_path" == "SHA256SUMS" || "$clean_path" == "manifest.json" || "$clean_path" == "EMPTY_STATE" ]]; then
    continue
  fi

  candidate="$target_dir_real/$clean_path"
  if [[ ! -f "$candidate" && -f "$target_dir_real/.local_data/$clean_path" ]]; then
    candidate="$target_dir_real/.local_data/$clean_path"
  fi

  if [[ ! -f "$candidate" ]]; then
    echo "Error: Restored file missing: $candidate" >&2
    restore_verified=0
    continue
  fi

  actual_hash=$(sha256sum "$candidate" | awk '{print $1}')
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    echo "Error: Hash mismatch for $candidate (expected: $expected_hash, got: $actual_hash)" >&2
    restore_verified=0
  else
    echo "OK  $clean_path"
  fi
done < "$manifest_file"

if [[ $restore_verified -ne 1 ]]; then
  echo "Error: Verification of restored files failed!" >&2
  exit 1
fi
echo "All restored files exist and match backup checksums."

if [[ $service_was_active -eq 1 ]]; then
  echo "Step 7: Restarting service $SERVICE_NAME..."
  if systemctl start "$SERVICE_NAME"; then
    echo "Service $SERVICE_NAME restarted successfully."
  else
    echo "Error: Service $SERVICE_NAME failed to restart after restore!" >&2
    exit 1
  fi
fi

# Clean state replacement successful: remove temporary swap directory so no stale files remain
if [[ $swapped -eq 1 && -n "$swap_dir" && -d "$swap_dir" ]]; then
  rm -rf "$swap_dir"
  swap_dir=""
  swapped=0
fi

restore_success=1

echo "=================================================="
echo "Restore Status:   SUCCESS"
echo "Restored From:    $backup_dir_real"
echo "Restored To:      $target_dir_real"
if [[ -n "$safety_dir" ]]; then
  echo "Safety Snapshot:  $safety_dir"
fi
echo "Integrity Status: VERIFIED (PASS)"
echo "=================================================="
