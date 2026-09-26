#!/usr/bin/env bash
set -euo pipefail
set -a
source /etc/plus5-vps/local-sync.env
set +a
check() {
  local expected=$1 label=$2
  shift 2
  local code
  code=$(curl --max-time 10 -s -o /dev/null -w '%{http_code}' "$@" http://127.0.0.1:8787/health)
  [[ "$code" == "$expected" ]] || { echo "FAIL: $label ($code)"; exit 1; }
  echo "PASS: $label"
}
check 403 'HTTPS forwarding guard' -H "X-Local-Sync-Key: $LOCAL_SYNC_ADMIN_KEY"
check 401 'unauthenticated access rejected' -H 'X-Forwarded-Proto: https'
check 200 'authenticated private health' -H 'X-Forwarded-Proto: https' -H "X-Local-Sync-Key: $LOCAL_SYNC_ADMIN_KEY"
systemctl restart plus5-vps
sleep 3
check 200 'health after real service restart' -H 'X-Forwarded-Proto: https' -H "X-Local-Sync-Key: $LOCAL_SYNC_ADMIN_KEY"
systemctl is-enabled plus5-vps
[[ $(systemctl is-active caddy || true) == inactive ]]
echo 'PASS: public proxy remains inactive'
