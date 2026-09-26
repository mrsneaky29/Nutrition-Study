#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || ! $1 =~ ^[1-9][0-9]*$ ]]; then
  echo "Usage: $0 COLLECTOR_COUNT [OUTPUT_FILE]" >&2
  exit 2
fi
count=$1
output=${2:-/etc/plus5-vps/local-sync.env}
command -v openssl >/dev/null 2>&1 || { echo "openssl is required" >&2; exit 1; }
[[ ! -e "$output" ]] || { echo "Refusing to overwrite existing file: $output" >&2; exit 1; }
umask 077
tmp=$(mktemp "${TMPDIR:-/tmp}/plus5-credentials.XXXXXX")
trap 'rm -f "$tmp"' EXIT
admin=$(openssl rand -hex 32)
keys=''
for ((i=1; i<=count; i++)); do
  printf -v collector_id 'C%03d' "$i"
  key=$(openssl rand -hex 32)
  [[ -z $keys ]] || keys+=,
  keys+="$collector_id:$key"
done
{
  printf 'LOCAL_SYNC_PUBLIC_MODE=true\n'
  printf 'LOCAL_SYNC_COLLECTOR_KEYS=%s\n' "$keys"
  printf 'LOCAL_SYNC_ADMIN_KEY=%s\n' "$admin"
  printf 'LOCAL_SYNC_ALLOWED_ORIGINS=https://admin.example.org\n'
} > "$tmp"
if [[ $(id -u) -eq 0 ]]; then
  install -o root -g plus5-vps -m 0640 "$tmp" "$output"
else
  install -m 0600 "$tmp" "$output"
fi
printf 'Wrote %s with %s collector credential(s). Replace LOCAL_SYNC_ALLOWED_ORIGINS with the exact HTTPS admin origin before starting the service.\n' "$output" "$count"
printf 'Admin key (store securely): %s\n' "$admin"
printf 'Collector keys are stored only in the protected environment file.\n'
