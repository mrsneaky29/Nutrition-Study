#!/usr/bin/env bash
set -euo pipefail

ROOT=${VPS_ROOT:-/opt/plus5-vps}
archive=${1:?Usage: import-release.sh RELEASE.tar.gz}
[[ -f $archive ]] || { echo "Archive not found: $archive" >&2; exit 2; }
[[ -d "$ROOT/releases" && -w "$ROOT/releases" ]] || { echo "Release directory missing or not writable: $ROOT/releases" >&2; exit 1; }
command -v tar >/dev/null && command -v sha256sum >/dev/null || { echo "tar and sha256sum are required" >&2; exit 1; }

if tar -tzf "$archive" | awk '
  /^\// {bad=1}
  {n=split($0, a, "/"); for (i=1; i<=n; i++) if (a[i] == "..") bad=1}
  END {exit bad ? 0 : 1}
'; then
  echo "Unsafe absolute or parent traversal path in archive" >&2
  exit 1
fi
sha=$(sha256sum "$archive" | awk '{print $1}')
release_id="$(date -u +%Y%m%dT%H%M%SZ)-${sha:0:12}"
dest="$ROOT/releases/$release_id"
[[ ! -e $dest ]] || { echo "Release already exists: $dest" >&2; exit 1; }
tmp=$(mktemp -d "$ROOT/releases/.incoming.XXXXXX")
cleanup() { [[ -n ${tmp:-} && -d $tmp ]] && rm -rf -- "$tmp"; }
trap cleanup EXIT
tar --extract --gzip --file "$archive" --directory "$tmp" --no-same-owner --no-same-permissions
for required in tool/local_sync_server.dart build/admin_web/index.html; do
  [[ -f "$tmp/$required" ]] || { echo "Release missing required path: $required" >&2; exit 1; }
done
chmod -R a-w "$tmp"
mv -- "$tmp" "$dest"
tmp=''
printf '%s\n' "$release_id"
