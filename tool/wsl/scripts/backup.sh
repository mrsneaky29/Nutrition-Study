#!/usr/bin/env bash
# Make a verified external backup, quiescing sync and attempting restart on all exits.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/service_lib.sh"

if (($# < 1 || $# > 2)); then
  echo "Usage: $0 ABSOLUTE_EXTERNAL_DESTINATION [LABEL]" >&2
  exit 2
fi
DESTINATION="$1"
LABEL="${2:-wsl_backup}"
[[ "$DESTINATION" == /* ]] || { echo "Backup destination must be an absolute WSL path." >&2; exit 2; }
[[ "$DESTINATION" != *$'\n'* ]] || { echo "Newlines are not allowed in backup paths." >&2; exit 2; }
command -v findmnt >/dev/null 2>&1 || { echo "findmnt is required to inspect backup storage." >&2; exit 1; }

ensure_layout
acquire_lock
init_credentials
VERSION="$(active_release)" || { echo "No valid active release." >&2; exit 1; }
service_paths "$VERSION"
[[ -f "$BACKUP_SCRIPT" ]] || { echo "Backup utility missing for release $VERSION." >&2; exit 1; }

DEST_PARENT="$(dirname -- "$DESTINATION")"
[[ -d "$DEST_PARENT" ]] || { echo "Create or mount the backup parent first: $DEST_PARENT" >&2; exit 1; }
DEST_PARENT="$(realpath -e -- "$DEST_PARENT")"
DESTINATION="$DEST_PARENT/$(basename -- "$DESTINATION")"

mount_source() { findmnt -n -o SOURCE --target "$1" 2>/dev/null | head -n 1; }
port_is_listening() {
  ss -H -ltn | awk -v suffix=":$SYNC_PORT" 'substr($4, length($4)-length(suffix)+1) == suffix { found=1 } END { exit !found }'
}

windows_drive_letter() {
  local source="$1"
  source="${source%\\}"
  if [[ "$source" =~ ^([A-Za-z]):$ ]]; then
    printf '%s' "${BASH_REMATCH[1]^^}"
    return 0
  fi
  return 1
}

windows_disk_number() {
  local drive="$1" raw number
  command -v powershell.exe >/dev/null 2>&1 || return 1
  raw="$(powershell.exe -NoProfile -NonInteractive -Command \
    "try { (Get-Partition -DriveLetter $drive | Select-Object -First 1 | Get-Disk).Number } catch { exit 3 }" 2>/dev/null | tr -d '\r')" || return 1
  number="$(printf '%s' "$raw" | tr -d '[:space:]')"
  [[ "$number" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$number"
}

check_separate_storage() {
  local target="$1"
  local data_dev dest_dev data_mount dest_mount data_source dest_source data_drive dest_drive
  data_dev="$(stat -c '%d' "$RECORDS_DIR")"
  dest_dev="$(stat -c '%d' "$target")"
  data_mount="$(findmnt -n -o TARGET --target "$RECORDS_DIR" | head -n 1)"
  dest_mount="$(findmnt -n -o TARGET --target "$target" | head -n 1)"
  data_source="$(mount_source "$RECORDS_DIR")"
  dest_source="$(mount_source "$target")"

  if [[ "$data_dev" == "$dest_dev" || "$data_mount" == "$dest_mount" ]]; then
    echo "Backup rejected: destination shares the data filesystem or mount." >&2
    return 1
  fi

  if data_drive="$(windows_drive_letter "$data_source")"; then
    if ! dest_drive="$(windows_drive_letter "$dest_source")"; then
      # A Linux block or remote filesystem with a distinct mount is independent.
      return 0
    fi
    local data_disk dest_disk
    data_disk="$(windows_disk_number "$data_drive")" || { echo "Cannot verify Windows disk identity for $data_drive:" >&2; return 1; }
    dest_disk="$(windows_disk_number "$dest_drive")" || { echo "Cannot verify Windows disk identity for $dest_drive:" >&2; return 1; }
    [[ "$data_disk" != "$dest_disk" ]] || { echo "Backup rejected: both Windows drives are on physical disk $data_disk." >&2; return 1; }
    return 0
  fi

  if dest_drive="$(windows_drive_letter "$dest_source")"; then
    local host_drive host_disk dest_disk
    host_drive="${SYSTEMDRIVE:-C:}"
    host_drive="${host_drive:0:1}"
    host_disk="$(windows_disk_number "${host_drive^^}")" || {
      echo "Cannot verify which physical disk contains the WSL virtual disk; refusing this Windows-drive backup." >&2
      return 1
    }
    dest_disk="$(windows_disk_number "$dest_drive")" || { echo "Cannot verify Windows disk identity for $dest_drive:" >&2; return 1; }
    [[ "$host_disk" != "$dest_disk" ]] || { echo "Backup rejected: destination shares the Windows system disk that normally stores the WSL virtual disk." >&2; return 1; }
    return 0
  fi

  # Linux block devices and remote filesystems are checked by device and mount above.
  return 0
}

if [[ -L "$DESTINATION" ]]; then
  echo "Backup destination cannot be a symbolic link: $DESTINATION" >&2
  exit 1
fi
check_separate_storage "$DEST_PARENT"
mkdir -p -- "$DESTINATION"
if [[ -L "$DESTINATION" ]]; then
  echo "Backup destination became a symbolic link during validation; refusing it." >&2
  exit 1
fi
REAL_DEST="$(realpath -e -- "$DESTINATION")"
if [[ "$REAL_DEST" == "$DEPLOY_HOME" || "$REAL_DEST" == "$DEPLOY_HOME"/* ]]; then
  echo "Backup destination cannot be inside the deployment home." >&2
  exit 1
fi
check_separate_storage "$REAL_DEST"

WAS_RUNNING=0
QUIESCED=0
finish_backup() {
  local status=$?
  trap - EXIT
  if [[ "$QUIESCED" -eq 1 && "$WAS_RUNNING" -eq 1 ]]; then
    echo "Attempting to restart the sync service after backup operation..." >&2
    if ! start_sync "$VERSION"; then
      echo "ERROR: sync service restart failed; inspect $LOGS_DIR/sync_server.log." >&2
      [[ "$status" -ne 0 ]] || status=1
    fi
  fi
  exit "$status"
}
trap finish_backup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if pid="$(pid_file_process "$SYNC_PID_FILE" "$SERVER_SCRIPT")"; then
  WAS_RUNNING=1
  QUIESCED=1
  stop_sync "$SERVER_SCRIPT"
elif curl --silent --fail --max-time 1 -H "x-local-sync-key: $LOCAL_SYNC_ADMIN_KEY" \
  "http://127.0.0.1:$SYNC_PORT/health" >/dev/null 2>&1; then
  echo "A sync service is healthy but its PID file cannot be verified; refusing to back up live data." >&2
  exit 1
elif [[ -f "$SYNC_PID_FILE" ]]; then
  pid="$(tr -d ' \r\n' < "$SYNC_PID_FILE")"
  if process_is_running "$pid"; then
    echo "A process in the sync PID file cannot be identified safely; refusing backup." >&2
    exit 1
  fi
  rm -f -- "$SYNC_PID_FILE"
fi

if port_is_listening; then
  echo "A process is still listening on sync port $SYNC_PORT but is not safely controlled by this toolkit; refusing backup." >&2
  exit 1
fi

BEFORE="$(find "$REAL_DEST" -mindepth 1 -maxdepth 1 -type d -name 'backup_*' -printf '%f\n' | sort)"
echo "Creating verified backup on $REAL_DEST..."
dart "$BACKUP_SCRIPT" backup --source="$RECORDS_DIR" --destination="$REAL_DEST" --label="$LABEL"
AFTER="$(find "$REAL_DEST" -mindepth 1 -maxdepth 1 -type d -name 'backup_*' -printf '%f\n' | sort)"
NEW_BACKUP="$(comm -13 <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") | tail -n 1)"
[[ -n "$NEW_BACKUP" ]] || { echo "Backup utility did not create a new backup directory." >&2; exit 1; }
dart "$BACKUP_SCRIPT" verify --backup="$REAL_DEST/$NEW_BACKUP"
echo "Backup verified: $REAL_DEST/$NEW_BACKUP"
