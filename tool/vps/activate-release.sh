#!/usr/bin/env bash
#
# activate-release.sh: Activates a staged release by updating symlinks, restarting
# the service, and verifying daemon health via authenticated endpoint check.
#
# NOTE: This is a restart-based deployment (NOT zero-downtime). A brief service
# interruption occurs while restarting the plus5-vps systemd daemon.
#
set -euo pipefail

# Ensure POSIX/native symlinks if running under MSYS/Cygwin environments
if [[ "${OSTYPE:-}" == "msys" || "${OSTYPE:-}" == "cygwin" ]]; then
  export MSYS="${MSYS:-winsymlinks:native}"
fi

ROOT=${VPS_ROOT:-/opt/plus5-vps}
SERVICE_NAME=${VPS_SERVICE_NAME:-plus5-vps.service}
SYSTEMCTL_BIN=${VPS_SYSTEMCTL_BIN:-systemctl}
HEALTH_CHECK_TIMEOUT=${HEALTH_CHECK_TIMEOUT:-15}
HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-0.5}

release_id=${1:?Usage: activate-release.sh RELEASE_ID}
[[ $release_id =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid release ID: $release_id" >&2; exit 2; }
release="$ROOT/releases/$release_id"
[[ -d "$release" && -f "$release/tool/local_sync_server.dart" ]] || { echo "Not a valid release: $release" >&2; exit 1; }

# Activation updates service-owned release pointer; require root in production
if [[ $(id -u) -ne 0 && "${VPS_ALLOW_NON_ROOT:-0}" != "1" && "${ALLOW_NON_ROOT:-0}" != "1" ]]; then
  echo "Run activation as root so it can update the service-owned release pointer." >&2
  exit 1
fi

resolve_target() {
  local target="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$target"
  elif readlink -f "$target" >/dev/null 2>&1; then
    readlink -f "$target"
  else
    readlink "$target"
  fi
}

# Resolve ENV_FILE (defaulting to /etc/plus5-vps/local-sync.env or /etc/plus5-vps/env)
ENV_FILE=${ENV_FILE:-${VPS_ENV_FILE:-}}
if [[ -z "$ENV_FILE" ]]; then
  if [[ -f "/etc/plus5-vps/local-sync.env" ]]; then
    ENV_FILE="/etc/plus5-vps/local-sync.env"
  elif [[ -f "/etc/plus5-vps/env" ]]; then
    ENV_FILE="/etc/plus5-vps/env"
  elif [[ -f "${VPS_ETC_DIR:-/etc/plus5-vps}/local-sync.env" ]]; then
    ENV_FILE="${VPS_ETC_DIR}/local-sync.env"
  elif [[ -f "${VPS_ETC_DIR:-/etc/plus5-vps}/env" ]]; then
    ENV_FILE="${VPS_ETC_DIR}/env"
  fi
fi

# Extract host, port, and admin key
admin_key=${LOCAL_SYNC_ADMIN_KEY:-}
check_host=${HEALTH_CHECK_HOST:-${LOCAL_SYNC_HOST:-127.0.0.1}}
check_port=${HEALTH_CHECK_PORT:-${LOCAL_SYNC_PORT:-8787}}

if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
  if [[ -z "$admin_key" ]]; then
    extracted_key=$(grep -E '^[[:space:]]*LOCAL_SYNC_ADMIN_KEY=' "$ENV_FILE" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*LOCAL_SYNC_ADMIN_KEY=["'\''"]?//; s/["'\''"]?[[:space:]]*$//' || true)
    [[ -n "$extracted_key" ]] && admin_key="$extracted_key"
  fi
  if [[ -z "${HEALTH_CHECK_HOST:-}" && -z "${LOCAL_SYNC_HOST:-}" ]]; then
    extracted_host=$(grep -E '^[[:space:]]*(LOCAL_SYNC_HOST|HOST)=' "$ENV_FILE" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*(LOCAL_SYNC_HOST|HOST)=["'\''"]?//; s/["'\''"]?[[:space:]]*$//' || true)
    [[ -n "$extracted_host" ]] && check_host="$extracted_host"
  fi
  if [[ -z "${HEALTH_CHECK_PORT:-}" && -z "${LOCAL_SYNC_PORT:-}" ]]; then
    extracted_port=$(grep -E '^[[:space:]]*(LOCAL_SYNC_PORT|PORT)=' "$ENV_FILE" 2>/dev/null | head -n 1 | sed -E 's/^[[:space:]]*(LOCAL_SYNC_PORT|PORT)=["'\''"]?//; s/["'\''"]?[[:space:]]*$//' || true)
    [[ -n "$extracted_port" ]] && check_port="$extracted_port"
  fi
fi

prior_previous=""
if [[ -L "$ROOT/previous" || -d "$ROOT/previous" ]]; then
  prior_previous=$(resolve_target "$ROOT/previous" 2>/dev/null || true)
fi

perform_rollback() {
  local error_msg="$1"
  echo "" >&2
  echo "============================================================" >&2
  echo "ACTIVATION FAILED: $error_msg" >&2
  echo "============================================================" >&2

  if [[ -L "$ROOT/previous" || -d "$ROOT/previous" ]]; then
    local prior
    prior=$(resolve_target "$ROOT/previous" 2>/dev/null || true)
    if [[ -n "$prior" && -d "$prior" ]]; then
      echo "Triggering automatic rollback: restoring previous release '$prior'..." >&2
      ln -sfn "$prior" "$ROOT/current.rollback"
      mv -Tf "$ROOT/current.rollback" "$ROOT/current"

      # If there was a prior previous release before this failed activation, restore it
      if [[ -n "$prior_previous" && -d "$prior_previous" && "$prior_previous" != "$prior" ]]; then
        ln -sfn "$prior_previous" "$ROOT/previous.rollback"
        mv -Tf "$ROOT/previous.rollback" "$ROOT/previous"
      fi

      echo "Restarting $SERVICE_NAME with previous release..." >&2
      if "$SYSTEMCTL_BIN" restart "$SERVICE_NAME"; then
        echo "Automatic rollback completed: $SERVICE_NAME restarted on previous release $(basename "$prior")." >&2
      else
        echo "Error: Failed to restart $SERVICE_NAME during rollback to $prior." >&2
      fi
    else
      echo "Cannot rollback: previous release pointer exists but destination is invalid or missing ($prior)." >&2
    fi
  else
    echo "Cannot rollback: no previous release pointer ($ROOT/previous) exists." >&2
  fi
  exit 1
}

# Update previous release pointer if current exists and points to a different release
if [[ -L "$ROOT/current" || -d "$ROOT/current" ]]; then
  old=$(resolve_target "$ROOT/current" 2>/dev/null || true)
  if [[ -n "$old" && "$old" != "$release" ]]; then
    ln -sfn "$old" "$ROOT/previous.new"
    mv -Tf "$ROOT/previous.new" "$ROOT/previous"
  fi
fi

echo "==> Initiating restart-based deployment of release '$release_id'..."
echo "    Note: Brief service interruption will occur during daemon restart."

# Update current pointer
ln -sfn "$release" "$ROOT/current.new"
mv -Tf "$ROOT/current.new" "$ROOT/current"

# Restart systemd service
echo "==> Restarting $SERVICE_NAME..."
if ! "$SYSTEMCTL_BIN" restart "$SERVICE_NAME"; then
  perform_rollback "Service restart failed for $SERVICE_NAME with release $release_id"
fi

# Authenticated health check
echo "==> Verifying backend health at http://$check_host:$check_port/health (timeout: ${HEALTH_CHECK_TIMEOUT}s)..."

curl_headers=(-H "X-Forwarded-Proto: https")
if [[ -n "$admin_key" ]]; then
  curl_headers+=(-H "X-Local-Sync-Key: $admin_key")
fi

start_time=$(date +%s)
deadline=$(( start_time + HEALTH_CHECK_TIMEOUT ))
healthy=0
last_code="none"
last_body=""
health_tmp=$(mktemp 2>/dev/null || mktemp -t plus5-health.XXXXXX)

while true; do
  http_code=$(curl --silent --show-error --max-time 3 "${curl_headers[@]}" --output "$health_tmp" --write-out "%{http_code}" "http://$check_host:$check_port/health" 2>/dev/null || echo "000")
  last_code="$http_code"
  last_body=$(cat "$health_tmp" 2>/dev/null || true)

  if [[ "$http_code" == "200" ]]; then
    healthy=1
    break
  fi

  current_time=$(date +%s)
  if (( current_time >= deadline )); then
    break
  fi

  sleep "$HEALTH_CHECK_INTERVAL"
done

rm -f "$health_tmp" 2>/dev/null || true

if [[ $healthy -ne 1 ]]; then
  perform_rollback "Health check failed or timed out after ${HEALTH_CHECK_TIMEOUT}s (last HTTP status: $last_code, body: $last_body)"
fi

echo "==> Release '$release_id' successfully activated and verified healthy!"
echo "    Backend responded with HTTP status $last_code"
if [[ -n "$last_body" ]]; then
  echo "    Health status: $last_body"
fi
