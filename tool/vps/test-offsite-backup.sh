#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WRAPPER="$SCRIPT_DIR/offsite-backup.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/offsite-backup-test.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/state" "$TEST_ROOT/staging" "$TEST_ROOT/remote-root"
touch "$TEST_ROOT/rclone.conf"
chmod 0600 "$TEST_ROOT/rclone.conf"
printf '%s\n' '{"synthetic":"only"}' > "$TEST_ROOT/state/records.json"
printf '%s\n' 'backup:' > "$TEST_ROOT/expected-remotes"
export TEST_ROOT

cat > "$TEST_ROOT/bin/rclone" <<'MOCK_RCLONE'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  listremotes) cat "$TEST_ROOT/expected-remotes" ;;
  lsf) [[ ${FAIL_LSF:-0} != 1 ]] ;;
  copy)
    [[ ${FAIL_COPY:-0} != 1 ]]
    src=$2
    dest=$3
    remote_path=${dest#backup:}
    mkdir -p "$TEST_ROOT/remote-root/$remote_path"
    cp -a "$src"/. "$TEST_ROOT/remote-root/$remote_path/"
    ;;
  check)
    [[ ${FAIL_CHECK:-0} != 1 ]]
    src=$2
    remote_path=${3#backup:}
    diff -qr "$src" "$TEST_ROOT/remote-root/$remote_path" >/dev/null
    ;;
  *) exit 2 ;;
esac
MOCK_RCLONE

cat > "$TEST_ROOT/bin/systemctl" <<'MOCK_SYSTEMCTL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_ROOT/systemctl.log"
case "$1" in
  is-active) exit 0 ;;
  stop|start) exit 0 ;;
  *) exit 2 ;;
esac
MOCK_SYSTEMCTL

cat > "$TEST_ROOT/backup-state.sh" <<'MOCK_BACKUP'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == --force-same-filesystem ]]
dest=$2
systemctl is-active plus5-vps --quiet
systemctl stop plus5-vps
restore_service() { systemctl start plus5-vps; }
trap restore_service EXIT
backup="$dest/backup_20260926_060000"
mkdir -m 0700 "$backup"
cp "$TEST_ROOT/state/records.json" "$backup/records.json"
printf '%s\n' 'mock checksum manifest' > "$backup/SHA256SUMS"
MOCK_BACKUP

chmod 0700 "$TEST_ROOT/bin/rclone" "$TEST_ROOT/bin/systemctl" "$TEST_ROOT/backup-state.sh"
export PATH="$TEST_ROOT/bin:$PATH"
export RCLONE_CONFIG="$TEST_ROOT/rclone.conf"
export RCLONE_DESTINATION='backup:encrypted-plus5'
export VPS_OFFSITE_STAGING_ROOT="$TEST_ROOT/staging"
export VPS_OFFSITE_LOCK_FILE="$TEST_ROOT/backup.lock"
export VPS_BACKUP_SCRIPT="$TEST_ROOT/backup-state.sh"
export RCLONE_BIN=rclone SYSTEMCTL_BIN=systemctl

assert_failure() {
  if "$@" >/dev/null 2>&1; then
    echo "FAIL: expected command to fail: $*" >&2
    exit 1
  fi
}

# Missing local config and inaccessible destination must fail before service stop.
mv "$RCLONE_CONFIG" "$TEST_ROOT/rclone.conf.saved"
assert_failure "$WRAPPER"
[[ ! -e "$TEST_ROOT/systemctl.log" ]] || { echo 'service was touched before config validation' >&2; exit 1; }
mv "$TEST_ROOT/rclone.conf.saved" "$RCLONE_CONFIG"
export FAIL_LSF=1
assert_failure "$WRAPPER"
[[ ! -e "$TEST_ROOT/systemctl.log" ]] || { echo 'service was touched before destination preflight' >&2; exit 1; }
unset FAIL_LSF

"$WRAPPER"
grep -q '^stop plus5-vps$' "$TEST_ROOT/systemctl.log"
grep -q '^start plus5-vps$' "$TEST_ROOT/systemctl.log"
remote_backup=$(find "$TEST_ROOT/remote-root/encrypted-plus5" -mindepth 1 -maxdepth 1 -type d -print -quit)
[[ -n "$remote_backup" ]]
cmp "$TEST_ROOT/state/records.json" "$remote_backup/records.json"

# Verification errors must leave the just-created local backup in place.
export FAIL_CHECK=1
assert_failure "$WRAPPER"
local_retained=$(find "$TEST_ROOT/staging" -mindepth 3 -maxdepth 3 -name SHA256SUMS -print -quit)
[[ -n "$local_retained" ]] || { echo 'failed local backup was not retained' >&2; exit 1; }

echo 'Offsite backup wrapper tests passed.'
