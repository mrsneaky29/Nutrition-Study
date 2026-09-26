#!/usr/bin/env bash
set -euo pipefail

ROOT=/opt/plus5-vps
STATE=/var/lib/plus5-vps/state
ETC=/etc/plus5-vps
ACCOUNT=plus5-vps

if [[ $(id -u) -ne 0 ]]; then
  echo "Run this reviewed layout script as root (for example, sudo bash tool/vps/install-host.sh)." >&2
  exit 1
fi
if ! id "$ACCOUNT" >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/plus5-vps --create-home --shell /usr/sbin/nologin "$ACCOUNT"
fi
install -d -o root -g root -m 0755 "$ROOT" "$ROOT/releases"
install -d -o "$ACCOUNT" -g "$ACCOUNT" -m 0700 "$STATE" "$STATE/.local_data"
install -d -o root -g "$ACCOUNT" -m 0750 "$ETC"
if [[ ! -e "$ETC/local-sync.env" ]]; then
  install -o root -g "$ACCOUNT" -m 0640 /dev/null "$ETC/local-sync.env"
  echo "Created empty $ETC/local-sync.env; generate and review credentials before starting the service." >&2
fi
echo "Created service account and directories. Review and install tool/vps/systemd/plus5-vps.service, then daemon-reload and enable it manually."
