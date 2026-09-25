#!/usr/bin/env bash
# Isolated end-to-end server smoke test: questionnaire, restart, session, and data persistence.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/common.sh"
VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then VERSION="$(active_release)"; fi
validate_release "$VERSION"
SMOKE_PORT="${SMOKE_PORT:-18787}"
[[ "$SMOKE_PORT" =~ ^[0-9]{1,5}$ ]] && ((SMOKE_PORT > 0 && SMOKE_PORT < 65536)) || {
  echo "SMOKE_PORT must be an integer from 1 to 65535." >&2; exit 2;
}
SERVER_SCRIPT="$(release_dir "$VERSION")/server/tool/local_sync_server.dart"
SMOKE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nutrition-wsl-smoke.XXXXXXXX")"
chmod 700 "$SMOKE_DIR"
SMOKE_PID=""
COLLECTOR_KEY="$(generate_key)"
ADMIN_KEY="$(generate_key)"
COLLECTOR_ID="C001"
RECORD_ID="smoke-$(date +%s)-$$"

pid_is_smoke_server() {
  local command_line
  [[ "$SMOKE_PID" =~ ^[0-9]+$ && -r "/proc/$SMOKE_PID/cmdline" ]] || return 1
  command_line="$(tr '\0' ' ' < "/proc/$SMOKE_PID/cmdline" 2>/dev/null || true)"
  [[ "$command_line" == *"$SERVER_SCRIPT"* ]]
}

process_is_running() {
  local state
  [[ "$SMOKE_PID" =~ ^[0-9]+$ && -r "/proc/$SMOKE_PID/status" ]] || return 1
  state="$(awk '/^State:/ {print $2; exit}' "/proc/$SMOKE_PID/status")"
  [[ -n "$state" && "$state" != Z && "$state" != X ]]
}

smoke_port_is_listening() {
  ss -H -ltn | awk -v suffix=":$SMOKE_PORT" 'substr($4, length($4)-length(suffix)+1) == suffix { found=1 } END { exit !found }'
}

stop_smoke_server() {
  [[ -n "$SMOKE_PID" ]] || return 0
  if ! pid_is_smoke_server; then SMOKE_PID=""; return 0; fi
  kill -TERM "$SMOKE_PID" 2>/dev/null || true
  for _ in {1..50}; do
    if ! process_is_running; then SMOKE_PID=""; break; fi
    sleep 0.1
  done
  if [[ -n "$SMOKE_PID" ]] && pid_is_smoke_server; then kill -KILL "$SMOKE_PID" 2>/dev/null || true; fi
  for _ in {1..20}; do
    if ! process_is_running; then SMOKE_PID=""; break; fi
    sleep 0.1
  done
  if [[ -z "$SMOKE_PID" ]]; then
    for _ in {1..20}; do
      if ! smoke_port_is_listening; then return 0; fi
      sleep 0.1
    done
  fi
  echo "Could not stop isolated smoke server PID $SMOKE_PID." >&2
  return 1
}

cleanup() {
  local status=$?
  trap - EXIT
  stop_smoke_server || status=1
  if smoke_port_is_listening; then
    echo "Smoke port remains occupied; retaining temporary data at $SMOKE_DIR." >&2
    status=1
  elif [[ "$SMOKE_DIR" == "${TMPDIR:-/tmp}"/nutrition-wsl-smoke.* && -d "$SMOKE_DIR" ]]; then
    rm -rf -- "$SMOKE_DIR"
  else
    echo "Refusing to remove unexpected smoke-test path: $SMOKE_DIR" >&2
    status=1
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

start_smoke_server() {
  local ready=0
  if smoke_port_is_listening; then
    echo "Smoke port $SMOKE_PORT is still occupied; refusing to start a second instance." >&2
    return 1
  fi
  (
    cd "$SMOKE_DIR"
    LOCAL_SYNC_COLLECTOR_KEYS="$COLLECTOR_ID:$COLLECTOR_KEY" \
    LOCAL_SYNC_ADMIN_KEY="$ADMIN_KEY" \
      nohup dart "$SERVER_SCRIPT" --host=127.0.0.1 --port="$SMOKE_PORT" \
        > "$SMOKE_DIR/server.log" 2>&1 < /dev/null &
    printf '%s\n' "$!" > "$SMOKE_DIR/server.pid"
  )
  SMOKE_PID="$(tr -d ' \r\n' < "$SMOKE_DIR/server.pid")"
  for _ in {1..40}; do
    if curl -sS --fail --max-time 1 -H "x-local-sync-key: $ADMIN_KEY" \
      "http://127.0.0.1:$SMOKE_PORT/health" >/dev/null 2>&1; then
      ready=1; break
    fi
    if ! pid_is_smoke_server; then break; fi
    sleep 0.25
  done
  if [[ "$ready" -ne 1 ]]; then
    echo "Isolated server did not become ready; synthetic test stopped." >&2
    sed -n '1,100p' "$SMOKE_DIR/server.log" >&2 || true
    return 1
  fi
}

if smoke_port_is_listening; then
  echo "Smoke port $SMOKE_PORT is already in use; set SMOKE_PORT to an unused port." >&2
  exit 1
fi

echo "Running isolated synthetic smoke test for release $VERSION on port $SMOKE_PORT."
start_smoke_server
SESSION_RESPONSE="$(curl -sS --fail -X POST "http://127.0.0.1:$SMOKE_PORT/collector/session" \
  -H 'Content-Type: application/json' -H "x-local-sync-key: $COLLECTOR_KEY" \
  -d "{\"collectorId\":\"$COLLECTOR_ID\"}")"
SESSION_TOKEN="$(printf '%s' "$SESSION_RESPONSE" | sed -n 's/.*"sessionToken":"\([^"]*\)".*/\1/p')"
[[ -n "$SESSION_TOKEN" ]] || { echo "Collector session negotiation failed." >&2; exit 1; }

NOW="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
PAYLOAD="$(cat <<EOF
{
  "id":"$RECORD_ID","idempotencyKey":"smoke-upload-$RECORD_ID","collectorId":"$COLLECTOR_ID","visitNumber":1,"revision":1,
  "createdAt":"$NOW","updatedAt":"$NOW","status":"submitted","syncState":"synced","reviewState":"pending",
  "participant":{"studyId":"C01-000101","name":"Synthetic Canary Participant","indianPhone":"+919876543210"},
  "confirmation":{"name":"Synthetic Canary Participant","indianPhone":"+919876543210","visitNumber":1,"confirmedAt":"$NOW"},
  "stepTwoMeasurement":{"value":160.0,"unit":"cm","recordedAt":"$NOW","note":"Canary measurement"},
  "questionnaire":{"studySite":"community_clinic","sex":"female","education":"secondary","employment":"employed",
    "fruitFrequency":"daily","vegetableFrequency":"daily","sugaryDrinkFrequency":"never","processedFoodFrequency":"one_to_two_days",
    "age":35,"activeDaysPerWeek":4,"activeMinutesPerDay":30,"sleepHours":8,"heightCm":160,"weightKg":64,"waistCm":80,
    "bpOneSystolic":120,"bpOneDiastolic":80,"bpTwoSystolic":118,"bpTwoDiastolic":78,
    "weeklyActiveMinutes":120,"bmi":25.0,"averageSystolic":119.0,"averageDiastolic":79.0},
  "submittedAt":"$NOW"
}
EOF
)"

RECORD_RESPONSE="$(curl -sS --fail -X POST "http://127.0.0.1:$SMOKE_PORT/records" \
  -H 'Content-Type: application/json' -H "x-local-sync-key: $COLLECTOR_KEY" \
  -H "x-local-session: $SESSION_TOKEN" -d "$PAYLOAD")"
[[ "$RECORD_RESPONSE" == *"\"id\":\"$RECORD_ID\""* ]] || { echo "Questionnaire fixture was not accepted." >&2; exit 1; }
ADMIN_RESPONSE="$(curl -sS --fail -H "x-local-sync-key: $ADMIN_KEY" "http://127.0.0.1:$SMOKE_PORT/records")"
[[ "$ADMIN_RESPONSE" == *"$RECORD_ID"* && "$ADMIN_RESPONSE" == *'"studySite":"community_clinic"'* ]] || {
  echo "Submitted questionnaire was not visible to the admin records API." >&2; exit 1;
}
echo "PASS: complete synthetic questionnaire accepted and visible to admin API."

stop_smoke_server
start_smoke_server
ADMIN_RESPONSE="$(curl -sS --fail -H "x-local-sync-key: $ADMIN_KEY" "http://127.0.0.1:$SMOKE_PORT/records")"
[[ "$ADMIN_RESPONSE" == *"$RECORD_ID"* && "$ADMIN_RESPONSE" == *'"studySite":"community_clinic"'* ]] || {
  echo "Questionnaire did not persist across isolated server restart." >&2; exit 1;
}
RETRY_RESPONSE="$(curl -sS --fail -X POST "http://127.0.0.1:$SMOKE_PORT/records" \
  -H 'Content-Type: application/json' -H "x-local-sync-key: $COLLECTOR_KEY" \
  -H "x-local-session: $SESSION_TOKEN" -d "$PAYLOAD")"
[[ "$RETRY_RESPONSE" == *"\"id\":\"$RECORD_ID\""* ]] || {
  echo "Persisted collector session could not retry after restart." >&2; exit 1;
}
ADMIN_RESPONSE="$(curl -sS --fail -H "x-local-sync-key: $ADMIN_KEY" "http://127.0.0.1:$SMOKE_PORT/records")"
RECORD_COUNT="$(printf '%s' "$ADMIN_RESPONSE" | grep -o "\"id\":\"$RECORD_ID\"" | wc -l | tr -d '[:space:]')"
[[ "$RECORD_COUNT" == 1 ]] || { echo "Expected exactly one stored canary record; found $RECORD_COUNT." >&2; exit 1; }
echo "PASS: questionnaire, collector session, and single-record idempotent retry survived restart."
echo "PASS: only a temporary synthetic data directory was used."
