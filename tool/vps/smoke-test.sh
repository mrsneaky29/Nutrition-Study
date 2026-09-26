#!/usr/bin/env bash
set -euo pipefail

server="$(cd "$(dirname "$0")/.." && pwd)/local_sync_server.dart"
[[ -f "$server" ]] || { echo "Backend source not found: $server" >&2; exit 1; }
command -v dart >/dev/null && command -v curl >/dev/null || { echo "dart and curl are required" >&2; exit 1; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/plus5-smoke.XXXXXX")
if command -v shuf >/dev/null 2>&1; then
  port=$(shuf -i 20000-45000 -n 1)
else
  port=$(( 20000 + RANDOM % 25000 ))
fi

if command -v openssl >/dev/null 2>&1; then
  admin_key=$(openssl rand -hex 32)
  collector_key=$(openssl rand -hex 32)
else
  admin_key=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
  collector_key=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
fi

device_id="device-test-1"
record_id="smoke-rec-$(date +%s)-$$"
pid=''

stop_server() {
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null || true
    if command -v taskkill >/dev/null 2>&1; then
      taskkill //F //T //PID "$pid" 2>/dev/null || true
    fi
    for _ in $(seq 1 30); do
      if ! kill -0 "$pid" 2>/dev/null; then break; fi
      sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
    pid=''
    sleep 0.5
  fi
}

cleanup() {
  stop_server
  rm -rf -- "$tmp"
}
trap cleanup EXIT

start_server() {
  (
    cd "$tmp"
    LOCAL_SYNC_PUBLIC_MODE=true \
    LOCAL_SYNC_COLLECTOR_KEYS="C001:$collector_key" \
    LOCAL_SYNC_ADMIN_KEY="$admin_key" \
    LOCAL_SYNC_ALLOWED_ORIGINS=https://admin.invalid \
      dart run "$server" --host=127.0.0.1 --port="$port"
  ) >"$tmp/server.log" 2>&1 &
  pid=$!

  local ready=0
  for _ in $(seq 1 40); do
    if curl --silent -H 'X-Forwarded-Proto: https' -H "x-local-sync-key: $admin_key" "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 0.25
  done
  if [[ $ready -ne 1 ]]; then
    cat "$tmp/server.log" >&2
    echo "Synthetic service did not become ready" >&2
    exit 1
  fi
}

echo "Starting isolated local sync server in $tmp on port $port..."
start_server

# (b) Tests unauthenticated health check returns 401
unauth_code=$(curl --silent --output /dev/null --write-out '%{http_code}' -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$port/health")
[[ "$unauth_code" == "401" ]] || { echo "Expected unauthenticated health status 401; got $unauth_code" >&2; exit 1; }
echo "PASS: unauthenticated health check returned 401."

# (c) Tests admin health check with x-local-sync-key: $admin_key and X-Forwarded-Proto: https returns 200 and records count 0
admin_health=$(curl --fail --silent -H "x-local-sync-key: $admin_key" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$port/health")
[[ "$admin_health" == *'"status":"ok"'* && "$admin_health" == *'"records":0'* ]] || {
  echo "Unexpected synthetic health response: $admin_health" >&2
  exit 1
}
echo "PASS: admin health check returned 200 and records count 0."

# (d) Bootstraps a collector session via POST /sync/session/bootstrap with collector key and device id
bootstrap_resp=$(curl --fail --silent -X POST \
  -H 'Content-Type: application/json' \
  -H "x-local-sync-key: $collector_key" \
  -H 'X-Forwarded-Proto: https' \
  -d "{\"deviceId\":\"$device_id\",\"collectorId\":\"C001\"}" \
  "http://127.0.0.1:$port/sync/session/bootstrap")

session_token=$(printf '%s' "$bootstrap_resp" | sed -n 's/.*"sessionToken":"\([^"]*\)".*/\1/p')
[[ -n "$session_token" ]] || { echo "Failed to obtain session token: $bootstrap_resp" >&2; exit 1; }
echo "PASS: collector session bootstrap returned session token."

# (e) Submits a synthetic questionnaire record via POST /sync/records using session token and X-Forwarded-Proto: https
now=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
payload=$(cat <<EOF
{
  "id": "$record_id",
  "idempotencyKey": "smoke-upload-$record_id",
  "collectorId": "C001",
  "visitNumber": 1,
  "revision": 1,
  "createdAt": "$now",
  "updatedAt": "$now",
  "status": "submitted",
  "syncState": "synced",
  "reviewState": "pending",
  "participant": {
    "studyId": "C01-000101",
    "name": "Synthetic Canary Participant",
    "indianPhone": "+919876543210"
  },
  "confirmation": {
    "name": "Synthetic Canary Participant",
    "indianPhone": "+919876543210",
    "visitNumber": 1,
    "confirmedAt": "$now"
  },
  "stepTwoMeasurement": {
    "value": 160.0,
    "unit": "cm",
    "recordedAt": "$now",
    "note": "Canary measurement"
  },
  "questionnaire": {
    "studySite": "community_clinic",
    "sex": "female",
    "education": "secondary",
    "employment": "employed",
    "fruitFrequency": "daily",
    "vegetableFrequency": "daily",
    "sugaryDrinkFrequency": "never",
    "processedFoodFrequency": "one_to_two_days",
    "age": 35,
    "activeDaysPerWeek": 4,
    "activeMinutesPerDay": 30,
    "sleepHours": 8,
    "heightCm": 160,
    "weightKg": 64,
    "waistCm": 80,
    "bpOneSystolic": 120,
    "bpOneDiastolic": 80,
    "bpTwoSystolic": 118,
    "bpTwoDiastolic": 78,
    "weeklyActiveMinutes": 120,
    "bmi": 25.0,
    "averageSystolic": 119.0,
    "averageDiastolic": 79.0
  },
  "submittedAt": "$now"
}
EOF
)

record_resp=$(curl --fail --silent -X POST \
  -H 'Content-Type: application/json' \
  -H "x-local-sync-key: $collector_key" \
  -H "x-local-session: $session_token" \
  -H 'X-Forwarded-Proto: https' \
  -d "$payload" \
  "http://127.0.0.1:$port/sync/records")
[[ "$record_resp" == *"\"id\":\"$record_id\""* ]] || { echo "Record submission failed: $record_resp" >&2; exit 1; }
echo "PASS: synthetic questionnaire record submitted via POST /sync/records (200 OK)."

# (f) Verifies admin health or record query reports the record
admin_health_after_submit=$(curl --fail --silent -H "x-local-sync-key: $admin_key" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$port/health")
[[ "$admin_health_after_submit" == *'"records":1'* ]] || {
  echo "Admin health did not report 1 record: $admin_health_after_submit" >&2
  exit 1
}
admin_records=$(curl --fail --silent -H "x-local-sync-key: $admin_key" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$port/sync/records")
[[ "$admin_records" == *"$record_id"* ]] || {
  echo "Admin records query did not contain record $record_id: $admin_records" >&2
  exit 1
}
echo "PASS: admin health and record query confirmed record present."

# (g) Simulates restart: kills the server process, starts a new server instance pointing to the same temp directory and port
echo "Restarting server to test persistence..."
stop_server
start_server

# (h) Verifies that after restart, the record is still present (persistence verified)
admin_health_after_restart=$(curl --fail --silent -H "x-local-sync-key: $admin_key" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$port/health")
[[ "$admin_health_after_restart" == *'"records":1'* ]] || {
  echo "Admin health after restart did not report 1 record: $admin_health_after_restart" >&2
  exit 1
}
admin_records_after_restart=$(curl --fail --silent -H "x-local-sync-key: $admin_key" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$port/sync/records")
[[ "$admin_records_after_restart" == *"$record_id"* ]] || {
  echo "Admin records after restart did not contain record $record_id: $admin_records_after_restart" >&2
  exit 1
}
echo "PASS: record persistence verified after server restart."

echo "Synthetic public-mode smoke test passed: isolated store verified with persistence across restart."
