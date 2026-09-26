# Ubuntu VPS Deployment & Operations Kit

Provider-neutral operations manual for deploying the **+5 Local Sync API and Admin Web Portal** on a small Ubuntu LTS cloud VM.

The reference production target is a **DigitalOcean Basic Droplet** with 2 GiB RAM in Bangalore, India (`blr1`). The service runs as an unprivileged single-process Dart daemon listening exclusively on loopback (`127.0.0.1:8787`), reverse-proxied by **Caddy** which terminates TLS, manages automatic Let's Encrypt certificates, and serves the Flutter admin single-page web app.

---

## 1. Project Owner Provisioning Checklist

Before running any deployment scripts, the project owner or administrator must purchase and configure the following infrastructure assets:

### A. VPS Hardware & Operating System Specifications
- **Provider**: DigitalOcean (or equivalent cloud VPS provider: Linode, Hetzner, AWS Lightsail).
- **Plan**: Basic Droplet — Regular or Premium Intel/AMD.
- **Specs**: **1 vCPU, 2 GiB RAM, 50 GiB NVMe SSD** (~$12/month).
  - *Note*: 2 GiB RAM provides comfortable headroom for the Dart runtime (~80–150 MB RSS) and Caddy (~30 MB RSS), leaving ample page cache for JSON record reads and backups.
- **Operating System**: **Ubuntu 24.04 LTS (Noble Numbat) x64**.
- **Region**: **Bangalore, India (`blr1`)** for optimal latency to field collector devices.
- **Authentication**: SSH Ed25519 key authentication only (disable root password authentication).

### B. Domain & DNS Records
1. Purchase a domain (e.g. through Cloudflare, Namecheap, Porkbun, or Google Domains).
2. Choose your two subdomains:
   ```text
   API_HOST=api.<your-domain.org>
   ADMIN_HOST=admin.<your-domain.org>
   ```
3. In your DNS provider's dashboard, create **two `A` records**:
   | Type | Hostname / Name | Points To (IPv4) | TTL |
   | :--- | :--- | :--- | :--- |
   | `A` | `api.<your-domain.org>` | `<VPS_PUBLIC_IPV4>` | 300s / Auto |
   | `A` | `admin.<your-domain.org>` | `<VPS_PUBLIC_IPV4>` | 300s / Auto |
4. *(Optional)*: Add `AAAA` records only if your VPS has a fully configured, routable IPv6 address.
5. **Propagation Check**: Confirm resolution from external networks before configuring TLS:
   ```bash
   dig +short api.<your-domain.org>
   dig +short admin.<your-domain.org>
   ```

### C. Firewall Rules (UFW & Cloud Firewall)
The VPS must strictly expose only SSH and public web traffic. The internal sync server port (`8787`) must **never** be accessible directly over the internet.

1. **DigitalOcean Cloud Firewall** (or host `ufw`):
   | Port / Protocol | Direction | Source | Purpose |
   | :--- | :--- | :--- | :--- |
   | `22 / TCP` | Inbound | All (or restricted admin IP) | SSH administration |
   | `80 / TCP` | Inbound | All (`0.0.0.0/0`, `::/0`) | HTTP (ACME challenge verification & HTTP->HTTPS redirect) |
   | `443 / TCP` | Inbound | All (`0.0.0.0/0`, `::/0`) | HTTPS (Caddy TLS reverse proxy & Web admin) |
   | `8787 / TCP` | Inbound | **BLOCKED** | Backend API (bound to `127.0.0.1` loopback only) |
   | All traffic | Outbound | All | DNS, package updates, ACME certificate issuance |

2. Configure Ubuntu host firewall (`ufw`):
   ```bash
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw allow 22/tcp comment 'SSH'
   sudo ufw allow 80/tcp comment 'Caddy HTTP & ACME'
   sudo ufw allow 443/tcp comment 'Caddy HTTPS'
   sudo ufw enable
   sudo ufw status verbose
   ```

### D. Offsite Backup Storage Provisioning
Because physical disk crashes or cloud droplet accidental termination will destroy local data, you must provision an independent storage target:
- **DigitalOcean Block Storage Volume**: Attach a 10–20 GB block volume (e.g. mounted at `/mnt/backups`), formatted as ext4 with an entry in `/etc/fstab`.
- **DigitalOcean Spaces (S3-compatible Object Storage)**: Provision a Spaces bucket (e.g. `study-backups-blr1`), and configure `s3cmd`, `rclone`, or `awscli` with restricted API tokens.
- **External SFTP/rsync host**: A remote server or secure NAS in a separate physical location.

---

## 2. Server Installation & Directory Layout

### Step 1: Install System Dependencies
Connect to the VPS as root and install the required tools, Dart SDK, and Caddy:

```bash
# Update base system
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y curl tar coreutils openssl ufw

# Install Dart SDK (official Google repository)
sudo apt-get install -y apt-transport-https
sudo sh -c 'wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/dart.gpg'
sudo sh -c 'echo "deb [signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main" > /etc/apt/sources.list.d/dart_stable.list'
sudo apt-get update && sudo apt-get install -y dart

# Install Caddy (official repository)
sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt-get update && sudo apt-get install -y caddy
```

### Step 2: Initialize System Layout & Service Account
Run `install-host.sh` as root to create the unprivileged system account and directory layout:

```bash
sudo bash tool/vps/install-host.sh
```

This creates:
- **Service account**: `plus5-vps` (system user without shell access, home `/var/lib/plus5-vps`).
- **Deployment root**: `/opt/plus5-vps/releases` (owned by `root:root`, mode `0755`).
- **Live state directory**: `/var/lib/plus5-vps/state` (owned by `plus5-vps:plus5-vps`, mode `0700`).
- **Configuration directory**: `/etc/plus5-vps` (owned by `root:plus5-vps`, mode `0750`).

### Step 3: Install the systemd Service
Copy and enable the systemd unit file:

```bash
sudo cp tool/vps/systemd/plus5-vps.service /etc/systemd/system/plus5-vps.service
sudo systemctl daemon-reload
sudo systemctl enable plus5-vps
```

---

## 3. Credentials & Environment Configuration

Generate strong, distinct cryptographic credentials for field collectors and the administrator.

### Step 1: Run Credential Generator
```bash
# Example: generate credentials for 5 collectors (C001 - C005)
sudo bash tool/vps/generate-credentials.sh 5 /etc/plus5-vps/local-sync.env
```

The script generates:
- A distinct 256-bit hexadecimal administrator secret key.
- 5 unique collector keys, bound to identifiers `C001` through `C005`.
- Restrictive file permissions: mode `0640`, owner `root`, group `plus5-vps` (or `0600` if owned directly by `plus5-vps`).

### Step 2: Edit Allowed Origin
Open `/etc/plus5-vps/local-sync.env` (or `/etc/plus5-vps/env`) and configure your exact production admin web origin:

```ini
LOCAL_SYNC_PUBLIC_MODE=true
LOCAL_SYNC_COLLECTOR_KEYS=C001:...,C002:...,C003:...,C004:...,C005:...
LOCAL_SYNC_ADMIN_KEY=...
LOCAL_SYNC_ALLOWED_ORIGINS=https://admin.<your-domain.org>
```

> [!CAUTION]
> - Never add trailing slashes to `LOCAL_SYNC_ALLOWED_ORIGINS`.
> - Never hardcode the admin secret into web builds.
> - Store the printed administrator key in a secure offsite password manager.

---

## 4. Reverse Proxy Setup (Caddy)

Caddy automatically obtains and renews TLS certificates via ACME (Let's Encrypt / ZeroSSL), proxies API requests to the loopback backend, and serves static admin assets.

### Step 1: Render the Caddy Configuration
```bash
bash tool/vps/render-caddy.sh api.<your-domain.org> admin.<your-domain.org> /opt/plus5-vps/current/build/admin_web > /tmp/Caddyfile
```

### Step 2: Inspect and Apply
```bash
# Review rendered configuration
cat /tmp/Caddyfile

# Install as system Caddyfile
sudo cp /tmp/Caddyfile /etc/caddy/Caddyfile
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl restart caddy
```

---

## 5. Deployment & Release Management

### Step 1: Run Preflight Checks
Before importing a release, execute read-only preflight checks:

```bash
sudo bash tool/vps/preflight.sh
```
Verify that all required commands, directories, and port statuses indicate `OK`.

### Step 2: Import Release Archive
Release archives are standard `.tar.gz` bundles produced by the project build pipeline containing `tool/local_sync_server.dart`, `build/admin_web/index.html`, and supporting source files.

```bash
sudo bash tool/vps/import-release.sh /path/to/release-2026-09-26.tar.gz
```
The script validates directory safety, unpacks to `/opt/plus5-vps/releases/<RELEASE_ID>`, locks permissions to read-only, and outputs the `<RELEASE_ID>`.

### Step 3: Activate Release
```bash
sudo bash tool/vps/activate-release.sh <RELEASE_ID>
```
Activation performs the following atomically:
1. Points `/opt/plus5-vps/previous` to the currently active release.
2. Updates `/opt/plus5-vps/current` to the new release directory using atomic symlink replacement (`mv -Tf`).
3. Restarts `plus5-vps.service`.
4. If service restart fails, it automatically reverts `/opt/plus5-vps/current` to `previous`.

### Step 4: Smoke Test & Health Check
```bash
# Run isolated synthetic smoke test on loopback
bash tool/vps/smoke-test.sh

# Verify the live production API endpoint over HTTPS
curl -fsS -H "x-local-sync-key: <ADMIN_KEY>" https://api.<your-domain.org>/health
```

---

## 6. Backup & Disaster Recovery Procedures

State files are stored persistently in `/var/lib/plus5-vps/state/.local_data/`:
- `records.json`: Synced participant visit records.
- `conflicts.json`: Conflict inbox records.
- `*.bak`: Previous atomic write snapshots.

### A. Performing a Verified Backup (`backup-state.sh`)

The `tool/vps/backup-state.sh` utility guarantees state quiescence and cryptographic verification:
- Requires a destination directory on an independent volume or mount (e.g. `/mnt/backups`).
- Refuses to write inside `/var/lib/plus5-vps` or the state directory.
- Checks via `stat`/`df` that the destination is on a separate filesystem (bypassed with `--force-same-filesystem` in test/CI environments).
- If `plus5-vps` is running, automatically quiesces (stops) the service before copying and traps `EXIT` to restore service execution immediately upon completion or failure.
- Computes SHA-256 cryptographic hashes for all state files into `SHA256SUMS`.
- Verifies checksums immediately to guarantee archive integrity.

```bash
# Standard backup to mounted external volume
sudo bash tool/vps/backup-state.sh /mnt/backups

# Testing or staging on same filesystem
sudo bash tool/vps/backup-state.sh --force-same-filesystem /tmp/test-backup
```

**Output Example**:
```text
Stopping plus5-vps to quiesce state files before copying...
Copying state files from /var/lib/plus5-vps/state to /mnt/backups/backup_20260926_120000...
==================================================
Backup Status:    SUCCESS
Backup Directory: /mnt/backups/backup_20260926_120000
Timestamp:        20260926_120000
Files Backed Up:  3
Integrity Status: VERIFIED (PASS)
Checksum Manifest:
a65c8...  ./.local_data/conflicts.json
97f69...  ./.local_data/records.json
78130...  ./.local_data/records.json.bak
==================================================
Restoring plus5-vps service status...
Service plus5-vps restarted successfully.
```

### B. Offsite Replication
To replicate backups to cloud object storage (e.g. DigitalOcean Spaces):

```bash
# Using rclone, s3cmd, or aws-cli:
rclone copy /mnt/backups/ spaces:study-backups-blr1/vps/
```

### C. Restoring State from Backup (`restore-state.sh`)

The `tool/vps/restore-state.sh` utility safely restores records and state files:
- Validates the backup directory and verifies all cryptographic checksums in `SHA256SUMS` **before modifying the target**.
- Stops the `plus5-vps` systemd service if running.
- **Automatic Rollback Snapshot**: If the target state directory contains existing records, it archives them to a timestamped safety folder (`pre_restore_safety_backup_<timestamp>`) before overwriting.
- Restores all state files to target (`/var/lib/plus5-vps/state`).
- Restores proper ownership (`plus5-vps:plus5-vps`) and mode `0700`.
- Verifies all restored files exist and match backup hashes.
- Automatically restarts `plus5-vps` if it was running prior to the restore.

```bash
# Usage:
sudo bash tool/vps/restore-state.sh /mnt/backups/backup_20260926_120000
```

**Output Example**:
```text
Step 1: Verifying backup integrity before touching target...
Backup integrity verified: all checksums matched.
Step 2: Service plus5-vps is active. Stopping service...
Step 3: Target state directory contains existing records.
        Creating automatic rollback safety snapshot in: /var/lib/plus5-vps/state/pre_restore_safety_backup_20260926_120500
Safety snapshot created and verified at /var/lib/plus5-vps/state/pre_restore_safety_backup_20260926_120500
Step 4: Restoring state files into /var/lib/plus5-vps/state...
Step 5: Restoring file ownership (plus5-vps:plus5-vps) and permissions...
Step 6: Verifying restored files and checksums...
OK  .local_data/conflicts.json
OK  .local_data/records.json
OK  .local_data/records.json.bak
All restored files exist and match backup checksums.
Step 7: Restarting service plus5-vps...
Service plus5-vps restarted successfully.
==================================================
Restore Status:   SUCCESS
Restored From:    /mnt/backups/backup_20260926_120000
Restored To:      /var/lib/plus5-vps/state
Safety Snapshot:  /var/lib/plus5-vps/state/pre_restore_safety_backup_20260926_120500
Integrity Status: VERIFIED (PASS)
==================================================
```

---

## 7. Emergency Rollback Procedures

### Application Rollback
If a newly activated software release introduces regressions:
```bash
# Roll back to the immediately prior release
sudo bash tool/vps/rollback.sh

# Or roll back to an explicit release ID
sudo bash tool/vps/rollback.sh 20260920T100000Z-a1b2c3d4e5f6
```

### Database State Rollback
If bad data was ingested or an incorrect restore occurred, roll back using the safety snapshot:
```bash
sudo bash tool/vps/restore-state.sh /var/lib/plus5-vps/state/pre_restore_safety_backup_20260926_120500
```

---

## 8. Operational Maintenance & Monitoring

- **Service Status & Logs**:
  ```bash
  sudo systemctl status plus5-vps
  sudo journalctl -u plus5-vps -f
  sudo journalctl -u caddy -f
  ```
- **Automated Daily Backups (Cron Example)**:
  Edit `/etc/cron.d/plus5-backups`:
  ```cron
  # Run daily at 02:00 AM UTC
  0 2 * * * root /opt/plus5-vps/current/tool/vps/backup-state.sh /mnt/backups >> /var/log/plus5-backup.log 2>&1
  ```
- **Security Updates**:
  Apply Ubuntu security updates regularly during scheduled maintenance windows:
  ```bash
  sudo apt-get update && sudo apt-get dist-upgrade -y
  ```
