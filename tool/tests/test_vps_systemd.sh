#!/usr/bin/env bash
set -euo pipefail
[[ $(id -u) -eq 0 ]] || { echo 'Run on the test VM as root'; exit 1; }
source_file=${1:?Pass backend source path}
unit="nutrition-v5-test-$(date +%s)-$$"
staging=$(mktemp -d /opt/nutrition-v5-systemd.XXXXXX)
chmod 0755 "$staging"
cp "$source_file" "$staging/server.dart"
chmod 0644 "$staging/server.dart"
if [[ -n ${2:-} ]]; then
  cp "$2" "$staging/pubspec.yaml"
  chmod 0644 "$staging/pubspec.yaml"
fi
admin=$(openssl rand -hex 32)
collector=$(openssl rand -hex 32)
port=28785
if ss -ltn | grep -q ":$port "; then echo 'Test port already occupied'; exit 1; fi
cleanup() {
  systemctl stop "$unit.service" >/dev/null 2>&1 || true
  [[ "$staging" == /opt/nutrition-v5-systemd.* ]] && rm -rf -- "$staging"
}
trap cleanup EXIT
systemd-run --quiet --unit="$unit" --property=DynamicUser=yes \
  --property="StateDirectory=$unit" --property="WorkingDirectory=/var/lib/$unit" \
  --property=ProtectSystem=strict --property=ProtectHome=yes --property=PrivateTmp=yes \
  --property=NoNewPrivileges=yes --property=UMask=0077 \
  --setenv=LOCAL_SYNC_PUBLIC_MODE=true --setenv="LOCAL_SYNC_ADMIN_KEY=$admin" \
  --setenv="LOCAL_SYNC_COLLECTOR_KEYS=C001:$collector" \
  --setenv=LOCAL_SYNC_ALLOWED_ORIGINS=https://admin.invalid \
  /usr/bin/dart "$staging/server.dart" --host=127.0.0.1 --port="$port"
url="http://127.0.0.1:$port"
health() { curl -fsS -H 'X-Forwarded-Proto: https' -H "x-local-sync-key: $admin" "$url/health"; }
wait_ready() {
  for _ in $(seq 1 40); do if health >/dev/null 2>&1; then return; fi; sleep 0.25; done
  echo 'Service health timeout'; systemctl status "$unit.service" --no-pager; return 1
}
wait_ready
echo 'PASS: real systemd sandbox starts unprivileged backend'
pid=$(systemctl show "$unit.service" -p MainPID --value)
uid=$(ps -o uid= -p "$pid" | tr -d ' ')
[[ "$uid" != 0 ]] || { echo 'Service unexpectedly root'; exit 1; }
echo 'PASS: backend process is not root'
[[ $(curl -s -o /dev/null -w '%{http_code}' "$url/health") == 403 ]] || { echo 'Expected HTTPS proxy enforcement'; exit 1; }
echo 'PASS: missing HTTPS proxy header rejected'
session=$(curl -fsS -H 'X-Forwarded-Proto: https' -H "x-local-sync-key: $collector" -H 'Content-Type: application/json' \
  -d '{"collectorId":"C001","deviceId":"synthetic-systemd-test"}' "$url/collector/session" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sessionToken"])')
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
payload="{\"id\":\"systemd-synthetic\",\"idempotencyKey\":\"systemd-synthetic\",\"collectorId\":\"C001\",\"visitNumber\":1,\"revision\":1,\"createdAt\":\"$now\",\"updatedAt\":\"$now\",\"status\":\"submitted\",\"participant\":{\"studyId\":\"synthetic-systemd\",\"name\":\"Synthetic Test\",\"indianPhone\":\"+919876543210\"},\"confirmation\":{\"name\":\"Synthetic Test\",\"indianPhone\":\"+919876543210\",\"visitNumber\":1,\"confirmedAt\":\"$now\"},\"stepTwoMeasurement\":{\"value\":160,\"unit\":\"cm\",\"recordedAt\":\"$now\"}}"
payload=$(printf '%s' "$payload" | python3 -c 'import json,sys; p=json.load(sys.stdin); p.update(syncState="synced",reviewState="pending",submittedAt=p["createdAt"]); p["participant"]["studyId"]="C01-000101"; print(json.dumps(p))')
curl --fail-with-body -sS -H 'X-Forwarded-Proto: https' -H "x-local-sync-key: $collector" -H "x-local-session: $session" -H 'Content-Type: application/json' -d "$payload" "$url/records" >/dev/null
health | python3 -c 'import json,sys; assert json.load(sys.stdin)["records"] == 1'
echo 'PASS: sandboxed service persists synthetic record'
systemctl restart "$unit.service"
wait_ready
health | python3 -c 'import json,sys; assert json.load(sys.stdin)["records"] == 1'
echo 'PASS: real systemd restart preserves record'
echo "Synthetic test state retained separately at /var/lib/$unit (no production state touched)"
