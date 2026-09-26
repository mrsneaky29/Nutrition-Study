# Private Google Drive backup setup

Destination: **Nutrition Study - Private Server Backups** (`15d5eERaJkkGFy96c_MmucG3Lx3GZr3zG`). The folder is private to `susru99@gmail.com`.

## Before enabling backups

1. Install and configure `rclone` on the VM for Google Drive. Complete its one-time OAuth authorization in a browser you control, then transfer the resulting rclone configuration to the VM over SSH. Codex's Google Drive connector authorization does not authorize rclone on the VM.
2. Keep OAuth tokens, rclone configuration, encryption passwords, and recovery material out of chat, Git, APKs, and release kits. Restrict the VM configuration file to root. Revoke the rclone authorization if the VM or token is compromised.
3. Configure an rclone `crypt` remote over this Drive folder before uploading participant data. Store its recovery password and salt separately in a secure location you control; losing them makes encrypted backups unreadable. Do not put the recovery material in the same Drive folder.
4. Create each backup with `tool/vps/backup-state.sh` into a fresh local staging directory. Upload it with `rclone copy` to a timestamped remote directory. Do not use `rclone sync`, `purge`, or another operation that removes prior remote backups.
5. Before scheduling, make a synthetic-only backup, upload it, download it into a clean temporary location, and run `tool/vps/restore-state.sh` against that copy in an isolated test setup. Confirm the restored synthetic record is present and readable. Never test a restore over live study state.
6. Only after the upload and isolated restore both pass, install and enable a systemd timer for the morning backup. Keep logs limited to status, timestamps, and backup identifiers; do not log record contents or secrets. Check the next scheduled run and confirm the new remote backup and its checksum.

## Current status

The backend is running on VM loopback only and enabled at boot. The backup wrapper and systemd units are installed; fake-rclone integration tests passed on Ubuntu. Google OAuth is complete, and the `study-crypt:` encrypted remote is configured. A real synthetic upload, download, checksum comparison, and isolated restore passed on Ubuntu without touching production records or service state. Recovery details were copied to a separate owner-only Drive folder at the user's request; the user intends to retain a USB copy. The timer remains disabled: unattended production-state backups have not yet been activated or verified through the systemd backup unit.
