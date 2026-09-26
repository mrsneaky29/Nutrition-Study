#!/usr/bin/env bash
# Initial, domain-independent backend preparation. No public proxy is enabled.
set -euo pipefail
umask 077
[[ $(id -u) -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
source_dir=${1:?Usage: prepare-private-backend.sh REVIEWED_SOURCE_DIRECTORY}
[[ -f "$source_dir/tool/local_sync_server.dart" ]] || exit 1
env_file=/etc/plus5-vps/local-sync.env
release=/opt/plus5-vps/releases/plus5-private-predeployment
[[ ! -e "$release" ]] || { echo 'Release exists; refusing overwrite.' >&2; exit 1; }
if grep -q '^LOCAL_SYNC_ADMIN_KEY=.' "$env_file"; then
  echo 'Credentials already configured; refusing overwrite.' >&2
  exit 1
fi
mkdir -p "$release/tool/vps"
chmod 0755 "$release" "$release/tool" "$release/tool/vps"
install -m 0644 "$source_dir/tool/local_sync_server.dart" "$release/tool/local_sync_server.dart"
install -m 0755 "$source_dir/tool/vps/backup-state.sh" "$release/tool/vps/backup-state.sh"
install -m 0755 "$source_dir/tool/vps/offsite-backup.sh" "$release/tool/vps/offsite-backup.sh"
install -m 0640 "$env_file" /etc/plus5-vps/local-sync.env.predeployment-template
bash "$source_dir/tool/vps/generate-credentials.sh" 10 /etc/plus5-vps/local-sync.env.prepared >/dev/null
# This reserved origin deliberately blocks browser access until domain setup.
sed -i 's|https://admin.example.org|https://admin.pending.invalid|' /etc/plus5-vps/local-sync.env.prepared
mv /etc/plus5-vps/local-sync.env.prepared "$env_file"
ln -s "$release" /opt/plus5-vps/current
systemctl daemon-reload
systemctl enable --now plus5-vps >/dev/null
sleep 2
systemctl is-active --quiet plus5-vps
# Load only the generated env file, never print credential material.
set -a
source "$env_file"
set +a
code=$(curl -s -o /dev/null -w '%{http_code}' -H 'X-Forwarded-Proto: https' -H "X-Local-Sync-Key: $LOCAL_SYNC_ADMIN_KEY" http://127.0.0.1:8787/health)
[[ "$code" == 200 ]] || { echo "Private health check failed: $code" >&2; exit 1; }
echo 'Private backend active; authenticated health PASS; credentials remain on VM.'
echo 'Admin assets and public HTTPS are deferred until domain configuration.'
