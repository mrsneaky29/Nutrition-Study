#!/usr/bin/env bash
# Creates encryption credentials on the VM; never prints them.
set -euo pipefail
umask 077
[[ $(id -u) == 0 ]] || exit 1
config=/etc/rclone/rclone.conf
recovery=/etc/rclone/study-backup-recovery.txt
[[ -f "$config" && ! -e "$recovery" ]] || { echo 'Missing Drive config or recovery file already exists; refusing overwrite.' >&2; exit 1; }
if rclone listremotes --config "$config" | grep -qx 'study-crypt:'; then
  echo 'Encryption remote already exists; refusing replacement.' >&2
  exit 1
fi
password=$(openssl rand -hex 32)
salt=$(openssl rand -hex 32)
{
  printf 'Nutrition Study backup recovery - KEEP PRIVATE\n'
  printf 'Drive folder ID: 15d5eERaJkkGFy96c_MmucG3Lx3GZr3zG\n'
  printf 'Underlying remote: study-drive:encrypted-state\n'
  printf 'filename_encryption=standard\ndirectory_name_encryption=true\n'
  printf 'password=%s\npassword2=%s\n' "$password" "$salt"
  printf 'Reauthorise Google Drive if needed, then recreate the crypt remote using both exact secrets above.\n'
} > "$recovery"
obscured_password=$(printf '%s' "$password" | rclone obscure -)
obscured_salt=$(printf '%s' "$salt" | rclone obscure -)
rclone config create study-crypt crypt remote study-drive:encrypted-state filename_encryption standard directory_name_encryption true password "$obscured_password" password2 "$obscured_salt" --no-obscure --config "$config" >/dev/null
unset password salt obscured_password obscured_salt
chmod 0600 "$config" "$recovery"
rclone mkdir study-crypt: --config "$config"
rclone lsf study-crypt: --config "$config" >/dev/null
echo 'Encrypted remote configured. Recovery key remains root-private on VM; second copy required before scheduling.'
