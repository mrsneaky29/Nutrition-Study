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
cleanup() {
  if [[ -n "${tmp:-}" && -d "${tmp:-}" ]]; then
    rm -rf -- "$tmp"
  fi
}
trap cleanup EXIT

tar --extract --gzip --file "$archive" --directory "$tmp" --no-same-owner --no-same-permissions

# Verify that required release files exist
for required in tool/local_sync_server.dart build/admin_web/index.html; do
  [[ -f "$tmp/$required" ]] || { echo "Release missing required path: $required" >&2; exit 1; }
done

# Set explicit safe permissions:
# - Directories: 0755 (traversable and readable by root, plus5-vps, and Caddy)
chmod 0755 "$tmp"
find "$tmp" -type d -exec chmod 0755 {} +

# - Files: 0644 (readable by all, writable only by root), or 0755 for executables/scripts if any
find "$tmp" -type f \( -name "*.sh" -o -perm -0100 \) -exec chmod 0755 {} +
find "$tmp" -type f ! \( -name "*.sh" -o -perm -0111 \) -exec chmod 0644 {} +

# - Prevent world/group write permissions across the entire tree
chmod -R go-w "$tmp"

# - Set explicit safe ownership (e.g. root:root when run as root, or configurable via RELEASE_OWNER_USER:RELEASE_OWNER_GROUP)
owner_user=${RELEASE_OWNER_USER:-}
owner_group=${RELEASE_OWNER_GROUP:-}
if [[ -z "$owner_user" && $(id -u) -eq 0 ]]; then
  owner_user="root"
  owner_group=${owner_group:-root}
fi
if [[ -n "$owner_user" ]]; then
  if [[ -n "$owner_group" ]]; then
    chown -R "$owner_user:$owner_group" "$tmp"
  else
    chown -R "$owner_user" "$tmp"
  fi
fi

mv -- "$tmp" "$dest"
# Ensure the final release directory $dest has 0755 permissions
chmod 0755 "$dest"
tmp=''
printf '%s\n' "$release_id"
