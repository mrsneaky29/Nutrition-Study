#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BACKUP_SCRIPT=${VPS_BACKUP_SCRIPT:-"$SCRIPT_DIR/backup-state.sh"}
RCLONE_BIN=${RCLONE_BIN:-rclone}
SYSTEMCTL_BIN=${SYSTEMCTL_BIN:-systemctl}
SERVICE_NAME=${VPS_SERVICE_NAME:-plus5-vps}
STAGING_ROOT=${VPS_OFFSITE_STAGING_ROOT:-/var/lib/plus5-offsite-backups}
LOCK_FILE=${VPS_OFFSITE_LOCK_FILE:-/run/lock/plus5-offsite-backup.lock}
RCLONE_CONFIG=${RCLONE_CONFIG:-/etc/rclone/rclone.conf}
RCLONE_DESTINATION=${RCLONE_DESTINATION:-}

umask 077

log() {
  printf '%s\n' "offsite-backup: $*" >&2
}

fail() {
  log "ERROR: $*"
  exit 1
}

[[ -x "$(command -v flock || true)" ]] || fail "flock is required."
[[ -x "$(command -v "$RCLONE_BIN" || true)" ]] || fail "rclone is not installed."
[[ -x "$(command -v "$SYSTEMCTL_BIN" || true)" ]] || fail "systemctl is not installed."
[[ -f "$BACKUP_SCRIPT" && -r "$BACKUP_SCRIPT" ]] || fail "local backup script is unavailable."

# Validate all local credentials and destination settings before backup-state.sh
# can stop the application service. The env file should contain only paths and
# the configured remote destination; rclone secrets stay in its private config.
[[ -n "$RCLONE_DESTINATION" ]] || fail "RCLONE_DESTINATION is not configured."
[[ -f "$RCLONE_CONFIG" && -r "$RCLONE_CONFIG" ]] || fail "rclone configuration is missing or unreadable."
[[ -d "$STAGING_ROOT" || ( ! -e "$STAGING_ROOT" && -w "$(dirname "$STAGING_ROOT")" ) ]] || fail "local staging location is unavailable."

remote_name=${RCLONE_DESTINATION%%:*}
[[ "$RCLONE_DESTINATION" == *:* && -n "$remote_name" ]] || fail "RCLONE_DESTINATION must use a configured rclone remote."
remotes=$("$RCLONE_BIN" listremotes --config "$RCLONE_CONFIG" 2>/dev/null) || fail "rclone could not read its configuration."
if ! printf '%s\n' "$remotes" | grep -Fqx -- "${remote_name}:"; then
  fail "the configured rclone remote is not present."
fi

# This also verifies credentials and access to the configured destination before
# pausing the service. Do not enable the timer until synthetic restore testing.
"$RCLONE_BIN" lsf "$RCLONE_DESTINATION" --config "$RCLONE_CONFIG" >/dev/null 2>&1 || \
  fail "rclone cannot access the configured destination."

mkdir -p -- "$STAGING_ROOT"
chmod 0700 "$STAGING_ROOT"
mkdir -p -- "$(dirname "$LOCK_FILE")"
exec 9>"$LOCK_FILE"
flock -n 9 || fail "another offsite backup is already running."

timestamp=$(date -u +%Y%m%d_%H%M%S)
stage_dir=$(mktemp -d "$STAGING_ROOT/offsite_${timestamp}_XXXXXX")
chmod 0700 "$stage_dir"
log "starting backup $timestamp"

# Local staging is intentionally retained, including after success, so failed
# transfers remain recoverable and no cleanup operation can erase a backup.
"$BACKUP_SCRIPT" --force-same-filesystem "$stage_dir" >/dev/null

shopt -s nullglob
backup_dirs=("$stage_dir"/backup_*)
shopt -u nullglob
[[ ${#backup_dirs[@]} -eq 1 && -d "${backup_dirs[0]}" ]] || fail "local backup did not produce exactly one backup directory."
backup_dir=${backup_dirs[0]}
backup_id=${backup_dir##*/}
# backup-state.sh names backups to the second; add mktemp's random stage suffix
# so fast consecutive invocations can never target the same remote directory.
remote_id="${backup_id}_${stage_dir##*/}"
remote_target="${RCLONE_DESTINATION%/}/$remote_id"

# copy is additive and never removes older remote backups.
"$RCLONE_BIN" copy "$backup_dir" "$remote_target" --config "$RCLONE_CONFIG" --create-empty-src-dirs >/dev/null 2>&1 || \
  fail "upload failed for backup $remote_id; local copy was retained."

# --download verifies content by downloading it for comparison, including when
# the configured remote does not expose hashes usable by rclone.
"$RCLONE_BIN" check "$backup_dir" "$remote_target" --config "$RCLONE_CONFIG" --download >/dev/null 2>&1 || \
  fail "remote verification failed for backup $remote_id; local copy was retained."

log "verified backup $remote_id"
