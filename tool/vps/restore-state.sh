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

if [[ ! -d "$backup_input" ]]; then
  echo "Error: Backup directory does not exist: $backup_input" >&2
  exit 1
fi

canonical_path() {
  local target="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$target"
  else
    readlink -f "$target" 2>/dev/null || (cd "$target" 2>/dev/null && pwd -P) || echo "$target"
  fi
}

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

echo "Step 1: Verifying backup integrity before touching target..."
if ! (cd "$backup_dir_real" && sha256sum -c SHA256SUMS); then
  echo "Error: Backup integrity check failed in $backup_dir_real! Aborting restore." >&2
  exit 1
fi
echo "Backup integrity verified: all checksums matched."

service_was_active=0
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$SERVICE_NAME"; then
  service_was_active=1
  echo "Step 2: Service $SERVICE_NAME is active. Stopping service..."
  systemctl stop "$SERVICE_NAME"
fi

if [[ ! -d "$target_dir" ]]; then
  mkdir -p "$target_dir"
  chmod 0700 "$target_dir" 2>/dev/null || true
fi
target_dir_real=$(canonical_path "$target_dir")

has_records=0
if [[ -f "$target_dir_real/records.json" || \
      -f "$target_dir_real/.local_data/records.json" || \
      -f "$target_dir_real/conflicts.json" || \
      -f "$target_dir_real/.local_data/conflicts.json" ]]; then
  has_records=1
elif [[ -d "$target_dir_real" ]] && find "$target_dir_real" -maxdepth 2 -name '*.json' | grep -q .; then
  has_records=1
fi

safety_dir=""
if [[ $has_records -eq 1 ]]; then
  safety_timestamp=$(date -u +%Y%m%d_%H%M%S)
  safety_dir="$target_dir_real/pre_restore_safety_backup_${safety_timestamp}"
  echo "Step 3: Target state directory contains existing records."
  echo "        Creating automatic rollback safety snapshot in: $safety_dir"
  mkdir -p "$safety_dir"
  chmod 0700 "$safety_dir" 2>/dev/null || true
  (
    cd "$target_dir_real"
    tar --exclude='pre_restore_safety_backup_*' \
        --exclude='*.tmp*' \
        --exclude='restore_in_progress.json' \
        -cf - . | (cd "$safety_dir" && tar -xf -)
  )
  (
    cd "$safety_dir"
    find . -type f ! -name 'SHA256SUMS' | LC_ALL=C sort | while IFS= read -r f; do
      sha256sum "$f"
    done > SHA256SUMS
  )
  echo "Safety snapshot created and verified at $safety_dir"
else
  echo "Step 3: Target state directory does not contain existing records. Skipping safety snapshot."
fi

echo "Step 4: Restoring state files into $target_dir_real..."
marker_file="$target_dir_real/restore_in_progress.json"
echo "{\"version\":1,\"startedAt\":\"$(date -u +%Y%m%dT%H%M%SZ)\",\"source\":\"$backup_dir_real\"}" > "$marker_file"

(
  cd "$backup_dir_real"
  tar --exclude='SHA256SUMS' \
      --exclude='manifest.json' \
      --exclude='EMPTY_STATE' \
      -cf - . | (cd "$target_dir_real" && tar -xf -)
)

if [[ -f "$backup_dir_real/records.json" && ! -e "$backup_dir_real/.local_data" ]]; then
  mkdir -p "$target_dir_real/.local_data"
  cp -p "$backup_dir_real/records.json" "$target_dir_real/.local_data/records.json"
  if [[ -f "$backup_dir_real/conflicts.json" ]]; then
    cp -p "$backup_dir_real/conflicts.json" "$target_dir_real/.local_data/conflicts.json"
  fi
fi

rm -f "$marker_file"

if [[ $(id -u) -eq 0 ]] && id "$ACCOUNT" >/dev/null 2>&1; then
  echo "Step 5: Restoring file ownership ($ACCOUNT:$ACCOUNT) and permissions..."
  chown -R "$ACCOUNT:$ACCOUNT" "$target_dir_real"
  chmod 0700 "$target_dir_real" 2>/dev/null || true
  if [[ -d "$target_dir_real/.local_data" ]]; then
    chmod 0700 "$target_dir_real/.local_data" 2>/dev/null || true
  fi
fi

echo "Step 6: Verifying restored files and checksums..."
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
  if [[ -n "$safety_dir" ]]; then
    echo "Safety rollback snapshot remains available at: $safety_dir" >&2
  fi
  exit 1
fi
echo "All restored files exist and match backup checksums."

if [[ $service_was_active -eq 1 ]]; then
  echo "Step 7: Restarting service $SERVICE_NAME..."
  if systemctl start "$SERVICE_NAME"; then
    echo "Service $SERVICE_NAME restarted successfully."
  else
    echo "Warning: Service $SERVICE_NAME failed to restart after restore!" >&2
    exit 1
  fi
fi

echo "=================================================="
echo "Restore Status:   SUCCESS"
echo "Restored From:    $backup_dir_real"
echo "Restored To:      $target_dir_real"
if [[ -n "$safety_dir" ]]; then
  echo "Safety Snapshot:  $safety_dir"
fi
echo "Integrity Status: VERIFIED (PASS)"
echo "=================================================="
