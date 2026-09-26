#!/usr/bin/env bash
set -euo pipefail

ROOT=${VPS_ROOT:-/opt/plus5-vps}
release_id=${1:?Usage: activate-release.sh RELEASE_ID}
[[ $release_id =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid release ID" >&2; exit 2; }
release="$ROOT/releases/$release_id"
[[ -d $release && -f "$release/tool/local_sync_server.dart" ]] || { echo "Not a valid release: $release" >&2; exit 1; }
[[ $(id -u) -eq 0 ]] || { echo "Run activation as root so it can update the service-owned release pointer." >&2; exit 1; }
if [[ -L "$ROOT/current" ]]; then
  old=$(readlink -f "$ROOT/current")
  if [[ $old != "$release" ]]; then
    ln -sfn "$old" "$ROOT/previous.new"
    mv -Tf "$ROOT/previous.new" "$ROOT/previous"
  fi
fi
ln -s "$release" "$ROOT/current.new"
mv -Tf "$ROOT/current.new" "$ROOT/current"
if systemctl restart plus5-vps.service; then
  echo "Activated $release_id"
else
  echo "Service restart failed; restoring previous pointer" >&2
  if [[ -L "$ROOT/previous" ]]; then
    prior=$(readlink -f "$ROOT/previous")
    ln -s "$prior" "$ROOT/current.rollback"
    mv -Tf "$ROOT/current.rollback" "$ROOT/current"
    systemctl restart plus5-vps.service || true
  fi
  exit 1
fi
