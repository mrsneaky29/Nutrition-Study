#!/usr/bin/env bash
# Shared paths, credentials, validation, and process helpers for WSL operators.
set -euo pipefail

WSL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [[ -n "${NUTRITION_WSL_HOME:-}" ]]; then
  if [[ "$NUTRITION_WSL_HOME" != /* ]]; then
    echo "NUTRITION_WSL_HOME must be an absolute Linux path." >&2
    return 2 2>/dev/null || exit 2
  fi
  DEPLOY_HOME="$NUTRITION_WSL_HOME"
else
  DEPLOY_HOME="$WSL_ROOT/var"
fi

RELEASES_DIR="$DEPLOY_HOME/releases"
DATA_DIR="$DEPLOY_HOME"
RECORDS_DIR="$DATA_DIR/.local_data"
LOGS_DIR="$DATA_DIR/logs"
RUN_DIR="$DATA_DIR/run"
CREDENTIALS_FILE="$DATA_DIR/.credentials.env"
ACTIVE_RELEASE_FILE="$DATA_DIR/active_release"
LOCK_FILE="$RUN_DIR/operator.lock"
SYNC_PID_FILE="$RUN_DIR/sync_server.pid"
ADMIN_PID_FILE="$RUN_DIR/admin_web.pid"
SYNC_PORT="${LOCAL_SYNC_PORT:-8787}"
ADMIN_PORT="${LOCAL_ADMIN_PORT:-8086}"
SYNC_HOST="${LOCAL_SYNC_HOST:-0.0.0.0}"
ADMIN_HOST="${LOCAL_ADMIN_HOST:-0.0.0.0}"

ensure_layout() {
  mkdir -p "$RELEASES_DIR" "$RECORDS_DIR" "$LOGS_DIR" "$RUN_DIR"
  chmod 700 "$DEPLOY_HOME" "$RECORDS_DIR" "$LOGS_DIR" "$RUN_DIR"
}

generate_key() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  elif command -v od >/dev/null 2>&1; then
    od -An -N24 -tx1 /dev/urandom | tr -d ' \n'
  else
    echo "Install openssl or coreutils before generating credentials." >&2
    return 1
  fi
}

init_credentials() {
  ensure_layout
  if [[ ! -e "$CREDENTIALS_FILE" ]]; then
    local collector_key admin_key temp_file
    collector_key="$(generate_key)"
    admin_key="$(generate_key)"
    temp_file="$CREDENTIALS_FILE.tmp.$$"
    (umask 077; printf 'export LOCAL_SYNC_COLLECTOR_KEYS=\047C001:%s\047\nexport LOCAL_SYNC_ADMIN_KEY=\047%s\047\n' \
      "$collector_key" "$admin_key" > "$temp_file")
    chmod 600 "$temp_file"
    mv -n -- "$temp_file" "$CREDENTIALS_FILE"
    rm -f -- "$temp_file"
  fi
  if [[ -L "$CREDENTIALS_FILE" || ! -f "$CREDENTIALS_FILE" ]]; then
    echo "Credentials path is not a regular file: $CREDENTIALS_FILE" >&2
    return 1
  fi
  chmod 600 "$CREDENTIALS_FILE"
  local -a credential_lines=()
  mapfile -t credential_lines < "$CREDENTIALS_FILE"
  if ((${#credential_lines[@]} != 2)); then
    echo "Credentials file has an unexpected format; refusing to start services." >&2
    return 1
  fi
  LOCAL_SYNC_COLLECTOR_KEYS="$(printf '%s\n' "${credential_lines[0]}" | sed -n "s/^export LOCAL_SYNC_COLLECTOR_KEYS='\\(C001:[[:xdigit:]]*\\)'$/\\1/p")"
  LOCAL_SYNC_ADMIN_KEY="$(printf '%s\n' "${credential_lines[1]}" | sed -n "s/^export LOCAL_SYNC_ADMIN_KEY='\\([[:xdigit:]]*\\)'$/\\1/p")"
  if [[ ! "$LOCAL_SYNC_COLLECTOR_KEYS" =~ ^C001:[A-Fa-f0-9]{48}$ ||
        ! "$LOCAL_SYNC_ADMIN_KEY" =~ ^[A-Fa-f0-9]{48}$ ]]; then
    echo "Credentials file has an unexpected format; refusing to start services." >&2
    return 1
  fi
  export LOCAL_SYNC_COLLECTOR_KEYS LOCAL_SYNC_ADMIN_KEY
}

acquire_lock() {
  ensure_layout
  exec 9>"$LOCK_FILE"
  flock -x 9
}

valid_release_id() {
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$ ]]
}

release_dir() {
  local version="$1"
  valid_release_id "$version" || return 1
  printf '%s/%s' "$RELEASES_DIR" "$version"
}

validate_release() {
  local version="$1" dir
  dir="$(release_dir "$version")" || {
    echo "Invalid release version: $version" >&2
    return 1
  }
  [[ -f "$dir/server/tool/local_sync_server.dart" &&
     -f "$dir/server/tool/backup_utility.dart" &&
     -f "$dir/server/tool/static_site_server.js" &&
     -f "$dir/server/pubspec.yaml" &&
     -f "$dir/admin/index.html" ]] || {
    echo "Release $version is incomplete; expected server source and admin index." >&2
    return 1
  }
}

active_release() {
  [[ -f "$ACTIVE_RELEASE_FILE" ]] || return 1
  local version
  version="$(tr -d '\r\n' < "$ACTIVE_RELEASE_FILE")"
  valid_release_id "$version" || {
    echo "Active release marker is invalid." >&2
    return 1
  }
  validate_release "$version" || return 1
  printf '%s' "$version"
}

read_process_command() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/cmdline" ]] || return 1
  tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null
}

process_matches() {
  local pid="$1" expected="$2" command_line
  command_line="$(read_process_command "$pid")" || return 1
  [[ "$command_line" == *"$expected"* ]]
}

process_is_running() {
  local pid="$1" state
  [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/status" ]] || return 1
  state="$(awk '/^State:/ {print $2; exit}' "/proc/$pid/status")"
  [[ -n "$state" && "$state" != Z && "$state" != X ]]
}

pid_file_process() {
  local pid_file="$1" expected="$2" pid
  [[ -f "$pid_file" && ! -L "$pid_file" ]] || return 1
  pid="$(tr -d ' \r\n' < "$pid_file")"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  process_matches "$pid" "$expected" || return 1
  printf '%s' "$pid"
}
