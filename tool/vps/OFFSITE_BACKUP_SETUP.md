# Private Google Drive backup setup

Destination: **Nutrition Study - Private Server Backups** (`15d5eERaJkkGFy96c_MmucG3Lx3GZr3zG`). The folder is private to `susru99@gmail.com`.

## Provisioning and activation checklist

1. Install and configure `rclone` on the VM for Google Drive. Complete its one-time OAuth authorization in a browser you control, then transfer the resulting rclone configuration to the VM over SSH. Codex's Google Drive connector authorization does not authorize rclone on the VM.
2. Keep OAuth tokens, rclone configuration, encryption passwords, and recovery material out of chat, Git, APKs, and release kits. Restrict the VM configuration file to root. Revoke the rclone authorization if the VM or token is compromised.
3. Configure an rclone `crypt` remote over this Drive folder before uploading participant data. Store its recovery password and salt separately in a secure location you control; losing them makes encrypted backups unreadable. Do not put the recovery material in the same Drive folder.
4. Create each backup with `tool/vps/backup-state.sh` into a fresh local staging directory. Upload it with `rclone copy` to a timestamped remote directory. Do not use `rclone sync`, `purge`, or another operation that removes prior remote backups.
5. Before scheduling, make a synthetic-only backup, upload it, download it into a clean temporary location, and run `tool/vps/restore-state.sh` against that copy in an isolated test setup. Confirm the restored synthetic record is present and readable. Never test a restore over live study state.
6. Only after the upload and isolated restore both pass, install and enable a systemd timer. Keep logs limited to status, timestamps, and backup identifiers; do not log record contents or secrets. After enabling, confirm the next scheduled run and verify its new remote backup.

## Current status

The backend is running on VM loopback only and enabled at boot. The backup wrapper and systemd units are installed; fake-rclone integration tests passed on Ubuntu. Google OAuth is complete, and the `study-crypt:` encrypted remote is configured. The systemd one-shot backup unit was run manually and completed successfully (ExecStart exit status 0); its journal reported the remote backup verified. A separate synthetic-only encrypted backup was uploaded to Drive, downloaded, decrypted, and restored in isolation. Recovery details are stored in a separate owner-only Drive folder, and the user has saved a USB copy. The daily timer is enabled for 03:30 UTC with up to 15 minutes of randomized delay (09:00–09:15 IST). The first timer-triggered run has not yet been observed; verify its journal result and remote backup after it runs.

## Inspecting scheduled backup health

Run these on the Ubuntu VM; they show service status without printing credentials:

```bash
systemctl is-active plus5-vps
systemctl is-enabled plus5-offsite-backup.timer
systemctl list-timers --all plus5-offsite-backup.timer --no-pager
systemctl show plus5-offsite-backup.service -p Result -p ExecMainStatus
journalctl -u plus5-offsite-backup.service -n 20 --no-pager
```

The backup service is a one-shot job, so `inactive` after a successful run is
normal. Look for `Result=success`, `ExecMainStatus=0`, and a `verified backup`
journal entry. An active timer alone does not prove that a backup succeeded.
`Persistent=true` catches up a missed scheduled run when the timer starts again;
the VM must be running for any backup to execute.

Local staging copies are retained under `/var/lib/plus5-offsite-backups` with
root-only permissions. They are not encrypted by rclone at rest on the VM;
encryption applies to the uploaded Drive objects. Monitor local disk space and
plan retention before collecting real participant data. No automatic deletion
or retention policy is enabled yet.
