# +5 private server setup checkpoint

## Verified on the Ubuntu VM

- Backend installed at `/opt/plus5-vps/releases/plus5-private-predeployment` and linked as current.
- `plus5-vps.service` active and enabled at boot; binds only `127.0.0.1:8787`.
- Ten initial collector credentials and a separate admin credential generated on the VM; this is not a collector or participant limit. Credentials remain in protected `/etc/plus5-vps/local-sync.env`, never in this repository or test kit.
- Reserved admin origin `https://admin.pending.invalid` prevents accidental browser deployment. Replace it with the actual admin HTTPS origin during domain setup.
- Authenticated health returns 200; missing HTTPS forwarding header returns 403; missing authentication returns 401. Real service restart and subsequent health check passed.
- Caddy remains inactive. No public API or admin website is deployed.
- Runtime home is explicitly the writable service state directory; this resolves Dart's analytics configuration startup failure under ProtectHome. Release directories are traversable by the unprivileged service account; secrets remain restricted.
- Offsite wrapper integration tests passed using synthetic data and fake rclone/systemctl on Ubuntu. Unique remote backup paths prevent same-second overwrite; copy is additive and local backups are retained.
- Backup service and timer installed and unit verification passed, but timer is disabled pending Google OAuth and a real synthetic offsite restore.

## Still required

1. Authorise rclone for the owner's Google Drive and configure encryption with safely retained recovery material.
2. Test real synthetic upload, download, checksum verification, and isolated restore before enabling the timer.
3. Configure the purchased domain, actual CORS origin, HTTPS proxy and final admin build.
4. Complete admin browser tests and mobile-data/two-phone acceptance tests. Do not call this survey-ready until they pass.

No real participant records were added during this setup. Existing release/test Drive folders were not changed.
