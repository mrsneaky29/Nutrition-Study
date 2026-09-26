#!/usr/bin/env bash
set -euo pipefail

ROOT=${VPS_ROOT:-/opt/plus5-vps}
STATE_DIR=${VPS_STATE_DIR:-/var/lib/plus5-vps/state}
SERVICE_NAME=${VPS_SERVICE_NAME:-plus5-vps}

force_same_fs=0
dest=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-same-filesystem)
      force_same_fs=1
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--force-same-filesystem] BACKUP_DESTINATION_DIR" >&2
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--force-same-filesystem] BACKUP_DESTINATION_DIR" >&2
      exit 2
      ;;
    *)
      if [[ -z "$dest" ]]; then
        dest="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        echo "Usage: $0 [--force-same-filesystem] BACKUP_DESTINATION_DIR" >&2
        exit 2
      fi
      ;;
  esac
done

if [[ -z "$dest" ]]; then
  echo "Error: Backup destination directory is required." >&2
  echo "Usage: $0 [--force-same-filesystem] BACKUP_DESTINATION_DIR" >&2
  exit 2
fi

if [[ ! -d "$dest" ]]; then
  echo "Error: Destination directory does not exist or is not a directory: $dest" >&2
  exit 1
fi

if [[ ! -w "$dest" ]]; then
  echo "Error: Destination directory is not writable: $dest" >&2
  exit 1
fi

if [[ ! -d "$STATE_DIR" ]]; then
  echo "Error: State directory does not exist: $STATE_DIR" >&2
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

dest_real=$(canonical_path "$dest")
state_real=$(canonical_path "$STATE_DIR")
base_plus5="/var/lib/plus5-vps"
if [[ -d "$base_plus5" ]]; then
  base_real=$(canonical_path "$base_plus5")
else
  base_real="$base_plus5"
fi

if [[ "$dest_real" == "$state_real" || "$dest_real" == "$state_real"/* ]]; then
  echo "Error: Backup destination ($dest_real) cannot be inside or equal to the state directory ($state_real)." >&2
  exit 1
fi

if [[ -d "$base_plus5" && ( "$dest_real" == "$base_real" || "$dest_real" == "$base_real"/* ) ]]; then
  echo "Error: Backup destination ($dest_real) cannot be inside or equal to the service home directory ($base_real)." >&2
  exit 1
fi

get_fs_id() {
  local target="$1"
  if stat -c %d "$target" >/dev/null 2>&1; then
    stat -c %d "$target"
  elif command -v df >/dev/null 2>&1; then
    df -P "$target" 2>/dev/null | awk 'NR==2 {print $1}'
  else
    echo "unknown"
  fi
}

dest_fs=$(get_fs_id "$dest_real")
state_fs=$(get_fs_id "$state_real")

if [[ "$dest_fs" != "unknown" && "$dest_fs" == "$state_fs" ]]; then
  if [[ $force_same_fs -eq 0 ]]; then
    echo "Error: Backup destination ($dest_real) is on the same filesystem as state directory ($state_real)." >&2
    echo "For disaster resilience, backups should reside on a separate volume or remote mount (e.g., DigitalOcean Volume or network mount)." >&2
    echo "Use --force-same-filesystem to bypass this check for testing or CI environments." >&2
    exit 1
  else
    echo "Warning: Destination is on the same filesystem as state directory (--force-same-filesystem specified)."
  fi
fi

service_was_active=0
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$SERVICE_NAME"; then
  service_was_active=1
  echo "Stopping $SERVICE_NAME to quiesce state files before copying..."
  systemctl stop "$SERVICE_NAME"
fi

cleanup() {
  local exit_code=$?
  if [[ $service_was_active -eq 1 ]]; then
    echo "Restoring $SERVICE_NAME service status..."
    if systemctl start "$SERVICE_NAME"; then
      echo "Service $SERVICE_NAME restarted successfully."
    else
      echo "Warning: Failed to restart service $SERVICE_NAME during exit cleanup!" >&2
    fi
  fi
  return "$exit_code"
}
trap cleanup EXIT

timestamp=$(date -u +%Y%m%d_%H%M%S)
backup_dir="$dest_real/backup_${timestamp}"
if [[ -e "$backup_dir" ]]; then
  backup_dir="${dest_real}/backup_${timestamp}_$$"
fi
mkdir -p "$backup_dir"
chmod 0700 "$backup_dir" 2>/dev/null || true

echo "Copying state files from $STATE_DIR to $backup_dir..."
(
  cd "$STATE_DIR"
  tar --exclude='pre_restore_safety_backup_*' \
      --exclude='*.tmp*' \
      --exclude='restore_in_progress.json' \
      -cf - . | (cd "$backup_dir" && tar -xf -)
)

chmod -R u=rwX,go= "$backup_dir" 2>/dev/null || true

(
  cd "$backup_dir"
  find . -type f ! -name 'SHA256SUMS' | LC_ALL=C sort | while IFS= read -r f; do
    sha256sum "$f"
  done > SHA256SUMS

  if [[ ! -s SHA256SUMS ]]; then
    echo "Warning: No state files were copied into backup." >&2
    touch EMPTY_STATE
    sha256sum EMPTY_STATE > SHA256SUMS
  fi

  if ! sha256sum -c --status SHA256SUMS >/dev/null 2>&1; then
    echo "Error: Checksum verification failed immediately after creating backup!" >&2
    sha256sum -c SHA256SUMS
    exit 1
  fi
)

file_count=$(find "$backup_dir" -type f ! -name 'SHA256SUMS' | wc -l | tr -d ' ')
integrity_status="VERIFIED (PASS)"

echo "=================================================="
echo "Backup Status:    SUCCESS"
echo "Backup Directory: $backup_dir"
echo "Timestamp:        $timestamp"
echo "Files Backed Up:  $file_count"
echo "Integrity Status: $integrity_status"
echo "Checksum Manifest:"
cat "$backup_dir/SHA256SUMS"
echo "=================================================="
