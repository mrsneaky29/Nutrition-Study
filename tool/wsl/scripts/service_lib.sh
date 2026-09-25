#!/usr/bin/env bash
# Service lifecycle functions. Caller holds the operator lock.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"

service_paths() {
  local version="$1"
  RELEASE_DIR="$(release_dir "$version")"
  SERVER_SCRIPT="$RELEASE_DIR/server/tool/local_sync_server.dart"
  BACKUP_SCRIPT="$RELEASE_DIR/server/tool/backup_utility.dart"
  ADMIN_SCRIPT="$RELEASE_DIR/server/tool/static_site_server.js"
  ADMIN_ROOT="$RELEASE_DIR/admin"
}

wait_for_sync() {
  local ready=0
  for _ in {1..40}; do
    if curl --silent --show-error --fail --max-time 1 \
      -H "x-local-sync-key: $LOCAL_SYNC_ADMIN_KEY" \
      "http://127.0.0.1:$SYNC_PORT/health" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 0.25
  done
  [[ "$ready" -eq 1 ]]
}

wait_for_admin() {
  local ready=0
  for _ in {1..40}; do
    if curl --silent --show-error --fail --max-time 1 \
      "http://127.0.0.1:$ADMIN_PORT/index.html" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 0.25
  done
  [[ "$ready" -eq 1 ]]
}

start_sync() {
  local version="$1" pid_file="$SYNC_PID_FILE" pid
  service_paths "$version"
  init_credentials
  if pid="$(pid_file_process "$pid_file" "$SERVER_SCRIPT")"; then
    if wait_for_sync; then
      echo "Sync service for $version is already ready (PID $pid)."
      return 0
    fi
    echo "Sync process exists but did not become ready; refusing to launch a duplicate." >&2
    return 1
  fi
  rm -f -- "$pid_file"
  echo "Starting sync service for release $version..."
  (
    cd "$DATA_DIR"
    nohup dart "$SERVER_SCRIPT" --host="$SYNC_HOST" --port="$SYNC_PORT" \
      >> "$LOGS_DIR/sync_server.log" 2>&1 < /dev/null &
    printf '%s\n' "$!" > "$pid_file.tmp.$$"
    mv -f -- "$pid_file.tmp.$$" "$pid_file"
  )
  if ! pid="$(pid_file_process "$pid_file" "$SERVER_SCRIPT")" || ! wait_for_sync; then
    echo "Sync service failed readiness; inspect $LOGS_DIR/sync_server.log." >&2
    stop_one "$pid_file" "$SERVER_SCRIPT" "sync service"
    return 1
  fi
  echo "Sync service is ready (PID $pid)."
}

start_admin() {
  local version="$1" pid_file="$ADMIN_PID_FILE" pid
  service_paths "$version"
  if [[ ! -f "$ADMIN_SCRIPT" ]]; then
    echo "Admin server script is missing from release $version." >&2
    return 1
  fi
  if pid="$(pid_file_process "$pid_file" "$ADMIN_SCRIPT")"; then
    if wait_for_admin; then
      echo "Admin site for $version is already ready (PID $pid)."
      return 0
    fi
    echo "Admin process exists but did not become ready; refusing to launch a duplicate." >&2
    return 1
  fi
  rm -f -- "$pid_file"
  echo "Starting admin site for release $version..."
  (
    nohup node "$ADMIN_SCRIPT" --root="$ADMIN_ROOT" --port="$ADMIN_PORT" \
      --host="$ADMIN_HOST" >> "$LOGS_DIR/admin_web.log" 2>&1 < /dev/null &
    printf '%s\n' "$!" > "$pid_file.tmp.$$"
    mv -f -- "$pid_file.tmp.$$" "$pid_file"
  )
  if ! pid="$(pid_file_process "$pid_file" "$ADMIN_SCRIPT")" || ! wait_for_admin; then
    echo "Admin site failed readiness; inspect $LOGS_DIR/admin_web.log." >&2
    stop_one "$pid_file" "$ADMIN_SCRIPT" "admin site"
    return 1
  fi
  echo "Admin site is ready (PID $pid)."
}

stop_one() {
  local pid_file="$1" expected="$2" label="$3" pid
  [[ -f "$pid_file" ]] || { echo "$label is not marked as running."; return 0; }
  pid="$(tr -d ' \r\n' < "$pid_file")"
  if [[ ! "$pid" =~ ^[0-9]+$ ]] || ! process_matches "$pid" "$expected"; then
    echo "Removing stale $label PID file; no unrelated process was signalled."
    rm -f -- "$pid_file"
    return 0
  fi
  echo "Stopping $label (verified PID $pid)..."
  kill -TERM "$pid" 2>/dev/null || true
  for _ in {1..50}; do
    if ! process_is_running "$pid"; then
      rm -f -- "$pid_file"
      echo "$label stopped."
      return 0
    fi
    sleep 0.1
  done
  if process_matches "$pid" "$expected"; then
    echo "$label did not stop after SIGTERM; sending SIGKILL to the still-verified process." >&2
    kill -KILL "$pid" 2>/dev/null || true
  fi
  for _ in {1..20}; do
    if ! process_is_running "$pid"; then
      rm -f -- "$pid_file"
      echo "$label stopped after forced shutdown."
      return 0
    fi
    sleep 0.1
  done
  echo "Could not verify that $label stopped; leaving PID file for inspection." >&2
  return 1
}

stop_sync() { stop_one "$SYNC_PID_FILE" "$1" "sync service"; }
stop_admin() { stop_one "$ADMIN_PID_FILE" "$1" "admin site"; }

stop_all_services() {
  local version="$1"
  service_paths "$version"
  local result=0
  stop_sync "$SERVER_SCRIPT" || result=1
  stop_admin "$ADMIN_SCRIPT" || result=1
  return "$result"
}

start_all_services() {
  local version="$1"
  service_paths "$version"
  if ! start_sync "$version"; then return 1; fi
  if ! start_admin "$version"; then
    stop_sync "$SERVER_SCRIPT" || true
    return 1
  fi
}
