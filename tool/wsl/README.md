# Nutrition Study WSL2 operator kit

This repository contains a portable Ubuntu on WSL2 operator kit for a synthetic phone trial. The kit imports matched server-source and admin-site archives as versioned releases, then runs one selected release against one persistent data directory and one persistent set of credentials. It does not package or alter APKs, modify Windows firewall rules, or create Windows port proxies.

Use fictional participant data only. The local sync server uses cleartext HTTP and bearer keys. Keep it on a trusted private network and do not expose it to the public internet.

## What stays in one place

By default, generated runtime state lives in `tool/wsl/var/`:

```text
var/
├── .credentials.env       # generated once, mode 600
├── .local_data/           # records, conflicts, and server session state
├── active_release         # selected source/admin version
├── logs/                  # service logs; keys are not intentionally printed
└── releases/              # imported versions; never overwritten by import
```

`var/` is ignored by Git. Set `NUTRITION_WSL_HOME` to an absolute Linux path before running commands to keep runtime data outside the repository. Use the same value for every command and every upgrade. The `+2`, `+3`, and `+4` labels identify release content; they do not create separate data directories.

The credential file contains the collector and administrator keys. Upgrades never regenerate it. The server's current collector session is stored with `.local_data`, so a clean service restart using the same data directory preserves the session. Session tokens are authorization state: restoring a record backup does not restore tokens, and collectors sign in again after disaster recovery.

## Prepare Ubuntu on WSL2

Copy this `tool/wsl` directory into the target PC's Ubuntu filesystem, preferably under the Linux home directory. From Ubuntu:

```bash
cd ~/nutrition-study/tool/wsl
chmod +x scripts/*.sh
./scripts/setup.sh
```

Setup checks for Bash, Dart, Node.js, `curl`, `flock`, `findmnt`, `stat`, `unzip`, and `sha256sum`. It creates the persistent directories and generates keys only if no credential file exists. If a required tool is missing, install it in Ubuntu and repeat setup. Do not put the runtime directory in a synchronized/shared folder.

## Import and test the +2 baseline

Obtain the matching `+2` source archive, admin-site archive, and release checksum manifest. In the directory containing the package, verify the manifest before importing. For example:

```bash
sha256sum -c SHA256SUMS.txt
```

Then import the server and admin archives. Use their exact filenames from that release package:

```bash
./scripts/import_release.sh 1.0.0+2 \
  /path/to/nutrition-study-source-first-test.zip \
  /path/to/nutrition-study-admin-web-first-test.zip
```

Imports are extracted into a new version directory and checked for the expected server, backup utility, and admin files. An existing version is never replaced. Activate the baseline:

```bash
./scripts/activate_release.sh 1.0.0+2
```

Activation starts both services and waits for their health checks before reporting success. The sync service listens on port `8787`; the admin site listens on `8086`. Logs are in `var/logs/`. To enter keys on the phone or admin browser, reveal them directly in an interactive Ubuntu terminal:

```bash
./scripts/show_credentials.sh
```

The collector uses number `1`, the PC's Wi-Fi LAN address, and the displayed collector key. Keep the credential display private. The script refuses redirected output and clears the terminal when you press Enter.

Before connecting a phone, run the isolated server smoke test:

```bash
./scripts/smoke_test.sh 1.0.0+2
```

It uses a temporary directory and synthetic keys, submits a complete questionnaire, confirms it appears in the admin API, restarts an isolated server on the same temporary data, confirms the record and session persist, and checks an idempotent retry. It does not touch `var/.local_data` or use operational credentials. Set `SMOKE_PORT` if its default port is occupied.

## Upgrade to +3 or +4

Obtain the matching source and admin archives for the exact version, plus that release's checksum manifest. Verify the package first, then import it as a new version:

```bash
sha256sum -c SHA256SUMS.txt
./scripts/import_release.sh 1.0.0+3 /path/to/source-plus3.zip /path/to/admin-web-plus3.zip
```

For the later release, use the release's actual version identifier and matching archives, such as `1.0.0+4` when that is the package's version:

```bash
./scripts/import_release.sh 1.0.0+4 /path/to/source-plus4.zip /path/to/admin-web-plus4.zip
```

Before switching versions, wait for all phone uploads to finish and make a verified off-device backup (see below). Then:

```bash
./scripts/activate_release.sh 1.0.0+3
./scripts/smoke_test.sh 1.0.0+3
```

Replace `1.0.0+3` with the version being installed. Activation stops the old services, switches the version marker, starts and checks the new server/admin pair, and restores the previous version if startup fails. All versions use the same `var/.local_data` and `var/.credentials.env`; importing or activating a release does not reset data or keys. Keep the old release folder for rollback.

On the phone, install the higher-version APK over the existing app. Do not uninstall the prior app or clear its storage. Confirm the app version, retained sign-in and records, offline pending submission, later sync, and the matching admin site with synthetic data. WSL server smoke tests do not prove Android secure-storage migration; only the physical phone trial can establish that.

## Start, stop, and restart

```bash
./scripts/start.sh
./scripts/stop.sh
./scripts/restart.sh
```

The scripts use an operator lock to serialize lifecycle and backup operations. They verify the saved PID's `/proc` command line before signaling it, use graceful termination first, and only force-stop a process whose identity still matches. Start checks the sync health endpoint and admin `index.html`; a failed admin start also stops the sync process it started.

## Admin access boundary

The packaged admin page's API URL defaults to `127.0.0.1:8787`. It is therefore suitable for an admin browser running on the same PC, where the page can reach that PC's server. Opening the page from another LAN computer does not make its API request reach the WSL host; that browser treats `127.0.0.1` as its own computer. Remote-LAN admin access needs an admin build configured with a reachable server address and an appropriate trusted transport/security setup. This kit does not change the admin client or claim remote-browser access works.

Android phones on Wi-Fi may also need reviewed Windows firewall and WSL routing configuration. These scripts make no firewall, port-forwarding, or router changes. Have the target-PC operator review and apply any required networking changes separately; do not expose these HTTP services to the internet.

## Off-device backup and recovery

Back up after the daily sync window, when pending phone submissions have reached zero. Mount a USB drive or remote backup share in Ubuntu and pass an absolute path on that storage. For example, if Windows mounted a USB drive as `E:`, WSL often exposes it at `/mnt/e`:

```bash
mkdir -p /mnt/e/StudyBackups
./scripts/backup.sh /mnt/e/StudyBackups evening_sync
```

The backup wrapper compares filesystem devices and mount points. For Windows-mounted drives, it also asks Windows for physical disk identities and rejects the same disk; if identity cannot be checked, it refuses the backup. For a WSL virtual disk, it compares a Windows destination against the Windows system disk, where WSL commonly stores its virtual disk. A custom-moved WSL virtual disk may be on another host volume; in that configuration, confirm the actual VHDX storage location before relying on the check. Distinct partitions on unusual storage arrangements may not be conclusively attributable from WSL. A checksum proves file integrity, not physical independence.

The wrapper stops the sync server only when its saved process identity is verified, creates and verifies a timestamped backup, and always attempts to restart the server if it had been running before the backup. If backup or verification fails, the command still returns failure even when service restart succeeds. If restart itself fails, inspect `var/logs/sync_server.log` before allowing phone sync to resume. The admin site remains available during a backup, but record changes through it cannot be saved while sync is stopped.

The record backup contains the store's records and conflict inbox. Keep the collector and administrator keys in an approved password manager or other protected secret store; they are deliberately separate from the participant-data backup. If both the deployment home and credential file are lost, generate replacement keys, update the phone setup, and sign collectors in again. Existing backed-up visits remain intact; pending visits remain on the phones. Restored collectors must establish new sessions.

Use the matching imported release's backup utility to verify or restore an archive. Stop services first. Always verify a backup before restoring. Restore into the persistent `var/.local_data` directory, use its explicit overwrite confirmation, and follow the utility's interrupted-restore recovery instructions before restarting. After restore, start services, check record/conflict counts in the admin portal, and have collectors sign in again.

## Scope and limitations

- Synthetic trial only until physical-phone sync, backup/restore rehearsal, offline workflow, and operational procedures are signed off.
- The kit runs one active server/admin version at a time. Do not run two versions on the same ports.
- Retain signed APKs separately. Check that the new APK uses the same application ID and signing certificate, has a higher version code, and installs as an in-place update before relying on app-local data preservation.
- The local server and admin page use HTTP on a trusted LAN. They are not an internet deployment or a production identity system.
- WSL stop/restart resilience cannot protect against a Windows host shutdown, WSL termination, storage failure, or power loss during a write. Keep verified off-device backups.
