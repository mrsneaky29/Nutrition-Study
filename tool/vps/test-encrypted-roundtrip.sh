#!/usr/bin/env bash
# Writes only synthetic fixtures; never touches the production service/state.
set -euo pipefail
umask 077
config=/etc/rclone/rclone.conf
test_root=$(mktemp -d /var/tmp/plus5-crypt-test.XXXXXX)
mkdir "$test_root/source" "$test_root/download"
printf '%s\n' '[{"synthetic":true,"participantId":"SYNTHETIC-ENCRYPTION-TEST","heightCm":170,"weightKg":65}]' > "$test_root/source/records.json"
(cd "$test_root/source"; sha256sum records.json > SHA256SUMS)
remote_path="study-crypt:synthetic-verification/$(basename "$test_root")"
rclone copy "$test_root/source" "$remote_path" --config "$config"
rclone check "$test_root/source" "$remote_path" --download --config "$config"
rclone copy "$remote_path" "$test_root/download" --config "$config"
(cd "$test_root/download"; sha256sum -c SHA256SUMS)
cmp "$test_root/source/records.json" "$test_root/download/records.json"
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir "$test_root/restored"
env VPS_SERVICE_NAME="plus5-synthetic-restore-$$" VPS_ACCOUNT="plus5-synthetic-account-$$" VPS_SAFETY_BACKUP_DIR="$test_root/safety" bash "$script_dir/restore-state.sh" "$test_root/download" "$test_root/restored/state" >/dev/null
cmp "$test_root/source/records.json" "$test_root/restored/state/records.json"
echo "PASS: encrypted upload/download/checksum and isolated restore; local test at $test_root"
echo 'Synthetic remote fixture retained. Production records and service were untouched.'
