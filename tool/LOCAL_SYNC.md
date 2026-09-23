# Local Sync Service

`local_sync_server.dart` is a LAN-only bridge for intermittent home-PC sync. It
uses only `dart:io` and writes its entire state to `.local_data/records.json` and
`.local_data/conflicts.json`. It is intentionally separate from the Flutter app and
Firebase backend.

> [!CAUTION]
> **LAN Security Notice**: Cleartext LAN HTTP (`http://<ip>:8787`) and bearer keys are designed
> **strictly for trusted home or local Wi-Fi networks**. They are **NOT suitable for public internet
> exposure**. Do not expose the server port to the internet via port forwarding, DMZ, or public hosting
> without an encrypted TLS reverse proxy or secure VPN (e.g. Tailscale/WireGuard).

---

## 1. Local Server Start-Up & Credential Binding

The server supports distinct access keys for multiple field collectors and the study administrator. All keys must be at least 16 characters in length, and the administrator key must not equal any collector key.

### Collector Credential Binding

Collector identities are bound directly to their respective bearer keys:
- Syntax: `LOCAL_SYNC_COLLECTOR_KEYS=C001:key1,C002:key2` (each key >= 16 characters).
- **Identity Derivation & Enforcement**: The server derives the authorized collector identity (e.g., `C001`, `C002`) directly from the bearer key passed in the `x-local-sync-key` request header.
- **Payload Verification**: When a collector uploads a record (`POST /records`), the payload's `collectorId` must match the identity bound to that key. If a collector key for `C001` attempts to upload a record with `collectorId: "C002"`, the server rejects the request with HTTP 403 Forbidden.
- Single-key configuration can also be specified as `LOCAL_SYNC_COLLECTOR_KEYS=C001:key1` or via `LOCAL_SYNC_COLLECTOR_KEY=key1`.

### Admin Key & Runtime Entry

- **Admin Key**: Set via `LOCAL_SYNC_ADMIN_KEY` (minimum 16 characters).
- **STRICTLY ENTERED AT RUNTIME**: The administrator key must **never** be hardcoded or compiled into web builds via `--dart-define`. When opening the admin portal in a browser (`lib/admin_main.dart`), an interactive login dialog prompts for the administrator key at runtime.
- The admin key grants record viewing (`GET /records`), updates (`PUT /records/:id`), archiving (`POST /records/:id/archive`), and conflict management (`GET /conflicts`), but cannot upload new records as a collector.
- The service deliberately never exposes `DELETE` (`DELETE` requests return HTTP 405 Method Not Allowed).

### Server Start-Up Examples

#### PowerShell (Windows):

```powershell
$env:LOCAL_SYNC_COLLECTOR_KEYS = "C001:collector1-secret-key-12345,C002:collector2-secret-key-67890"
$env:LOCAL_SYNC_ADMIN_KEY = "admin-secret-management-key-99999"
dart run tool/local_sync_server.dart --host=0.0.0.0 --port=8787
```

#### Bash (Linux / macOS):

```bash
export LOCAL_SYNC_COLLECTOR_KEYS="C001:collector1-secret-key-12345,C002:collector2-secret-key-67890"
export LOCAL_SYNC_ADMIN_KEY="admin-secret-management-key-99999"
dart run tool/local_sync_server.dart --host=0.0.0.0 --port=8787
```

---

## 2. Collector Provisioning & Offline Field Operations

Field collectors operate in communities with intermittent or zero internet and cellular connectivity. The system is architected for offline safety:

1. **Device Provisioning & Identity Locking**:
   - Each collector's device is provisioned with their assigned collector number locked to the app.
   - Locking is achieved at build time via `--dart-define=LOCAL_COLLECTOR_ID=C001` (or `-CollectorId C001` / `-CollectorNumber 1` in release packaging scripts), or during first-time setup on the phone.
   - Once locked, the app automatically stamps all newly created records with the provisioned collector identity.
2. **Offline Data Collection**:
   - Field collectors work completely offline throughout the day.
   - Submitted records are stored in Android secure storage on the device. This implementation does not use SQLite.
   - The app operates autonomously without requiring real-time contact with the home server.

---

## 3. Participant ID Scheme & Repeat-Visit Protocol

### Collector-Scoped Participant IDs (No 200 Limit)

To prevent ID collisions across devices without central coordination, participant Study IDs use a deterministic collector-scoped scheme:

$$\text{Format: } \mathbf{C\langle colNum\rangle\text{-}\langle sequence\rangle} \quad \text{(e.g., } \mathbf{C01\text{-}000001}, \mathbf{C02\text{-}000001}\text{)}$$

- **Collector Prefix**: 2 digits (`C01` through `C99`).
- **Sequence Number**: At least 6 digits, growing beyond `999999` when needed. There is no configured 200-participant block or 999,999-person cap.
- **Collision Avoidance**: Distinct collector numbers give distinct prefixes. A collector must keep its assigned number on one device; provisioning the same collector number on two independent phones can still create duplicate IDs.
- **Legacy Compatibility**: Legacy participant ID formats such as `P001`, `P002`, and `P0001` remain fully supported and validated.

### Repeat-Visit Workflow

Linking repeat visits (Visit 2+) to the correct participant requires specific procedures depending on network availability:

- **Online Repeat-Visit Lookup (`GET /participants/lookup`)**:
  - When the collector device can reach the configured LAN sync server, the app queries `GET /participants/lookup` by phone number.
  - The server returns matching participant records, verified Study IDs, and previous visit counts so the collector can initiate follow-up visits accurately.
- **Offline Verified Study Card Entry**:
  - When working offline in the field, online lookup is unavailable.
  - A physical study card with the prior Study ID can assist manual verification, but card issuance is an operational procedure outside the app.
  - The collector must verify the participant and enter the prior Study ID for Visit 2+ when offline. The app cannot guarantee correct linking if the entered ID is wrong.

---

## 4. Sync-Window Workflow (Intermittent PC Operation)

The home-PC server is designed for intermittent operation and does not need to run 24 hours a day:

```
[Field Collection: Offline]  --->  [Return to Base: Wi-Fi]  --->  [Admin Review & Backup]
• Questionnaires recorded           • PC starts (2-3 hr window)    • Review /conflicts inbox
• Android secure storage            • Retry with idempotency      • USB/Network off-device backup
• Collector-scoped IDs              • Pending sync: 0              • PC shutdown
```

1. **Daily Sync Window (2–3 hours/day)**:
   - The study coordinator powers on the home PC and starts `local_sync_server.dart` during a designated daily window (e.g., 5:00 PM – 8:00 PM) when field teams return from data collection.
2. **Local Wi-Fi Synchronization**:
   - Upon returning to base, collectors connect their mobile devices to the home Wi-Fi network.
   - The collector app uses the sync endpoint embedded at build time (`http://<computer-wifi-ip>:8787`); it does not discover the PC address automatically. Pending records retry while the app is open and active.
   - Idempotency keys ensure network interruptions or repeated attempts safely return the existing record without duplicating entries or overwriting admin edits.
3. **Window Closing & Shutdown**:
   - Once all collectors confirm `Pending sync: 0`, the administrator reviews incoming records and conflicts, makes an off-device backup, and shuts down the service. Backup commands below are manual; there is no scheduled backup script.

---

## 5. Server Conflict Inbox (`/conflicts`) & Admin Resolution

When multiple collectors operate offline, data discrepancies may occasionally occur (e.g., mismatched demographic details for the same study ID, or duplicate visit numbers).

### Conflict Detection & Server Inbox

- **Conflict Triggers**:
  - `participant_mismatch`: Same Study ID submitted with differing names or phone numbers, or same phone assigned to different Study IDs.
  - `duplicate_visit`: Same participant Study ID and visit number already recorded on the server.
  - `idempotency_collision`: A record ID was uploaded with different content or keys.
- **Server Response**:
  - The server rejects the conflicting upload with HTTP 409 Conflict.
  - The conflicting payload is recorded in the server's conflict inbox at `/conflicts` and persisted to `.local_data/conflicts.json`.
- **Client Handling**:
  - The conflicting record remains safely preserved on the collector's device in local storage.
- The record is marked as a **Sync conflict** in the app.
  - Automatic retries are paused for that record to prevent log spam, while allowing the collector to manually review or retry.

### Admin Resolution Workflow

1. In the Admin Portal (`lib/admin_main.dart`), an alert banner and the **Sync conflicts** filter tab highlight unresolved conflicts.
2. Administrators review the conflicting submission against existing database records side-by-side.
3. Using the guarded edit sheet, the administrator can correct phone/name typos, reassign study IDs, or approve the correct record.
4. Verify the corrected server record and keep the rejected phone record until it is safely reconciled. This workflow is not a guarantee against device loss or operator error.

---

## 6. Backup & Disaster Recovery

### Single-Disk `.bak` vs. Off-Device Backups

> [!IMPORTANT]
> The server maintains `.local_data/records.json.bak` and `.local_data/conflicts.json.bak` after subsequent writes as previous snapshots on disk.
> However, **these reside on the same physical drive as the primary data**.
> While `.bak` snapshots protect against process crashes or power interruptions during atomic file writes, **they are NOT off-device backups**.
> A drive failure, operating system crash, ransomware infection, or accidental deletion will destroy both primary and `.bak` files simultaneously.

### Scheduled Off-Device Backup Procedure

After each daily sync window, copy `.local_data/records.json` and `.local_data/conflicts.json` to an external USB drive or dedicated network share with an ISO timestamp.

#### PowerShell (Windows USB/Network Backup):

```powershell
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = "D:\StudyBackups"  # Path to external USB drive or network share (e.g. \\nas\backups)
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force }
Copy-Item -Path ".local_data\records.json" -Destination "$backupDir\records-$timestamp.json"
if (Test-Path ".local_data\conflicts.json") {
  Copy-Item -Path ".local_data\conflicts.json" -Destination "$backupDir\conflicts-$timestamp.json"
}
Write-Host "Off-device backup completed to $backupDir at $timestamp"
```

#### Bash (Linux / macOS USB/Network Backup):

```bash
timestamp=$(date +%Y%m%d-%H%M%S)
backupDir="/media/usb/StudyBackups"  # Path to external mount or network share
mkdir -p "$backupDir"
cp .local_data/records.json "$backupDir/records-${timestamp}.json"
if [ -f ".local_data/conflicts.json" ]; then
  cp .local_data/conflicts.json "$backupDir/conflicts-${timestamp}.json"
fi
echo "Off-device backup completed to $backupDir at $timestamp"
```

### Disaster Recovery Procedures

#### Scenario A: Corrupt Primary File (`records.json` corrupted on disk)

1. Stop the server if running (`Ctrl+C`).
2. The server's built-in loader automatically detects corrupt JSON upon launch. It moves the corrupt file aside to `records.json.corrupt-<pid>-<rand>` and falls back to `.local_data/records.json.bak` (same for `conflicts.json`).
3. Restart the server:
   ```powershell
   dart run tool/local_sync_server.dart --host=0.0.0.0 --port=8787
   ```
4. Verify server health and record count via `GET /health` (`http://localhost:8787/health`).

#### Scenario B: Total Hardware Failure or Drive Loss

1. Provision a replacement computer and clone or install the project repository.
2. Insert the external USB backup drive containing the timestamped backups.
3. Locate the most recent clean backup files (e.g., `records-20260923-180000.json` and `conflicts-20260923-180000.json`).
4. Recreate the `.local_data/` directory and restore both files:
   ```powershell
   New-Item -ItemType Directory -Path ".local_data" -Force
   Copy-Item -Path "D:\StudyBackups\records-20260923-180000.json" -Destination ".local_data\records.json"
   if (Test-Path "D:\StudyBackups\conflicts-20260923-180000.json") {
     Copy-Item -Path "D:\StudyBackups\conflicts-20260923-180000.json" -Destination ".local_data\conflicts.json"
   }
   ```
5. Launch the local sync server with the configured collector and admin keys:
   ```powershell
   dart run tool/local_sync_server.dart --host=0.0.0.0 --port=8787
   ```
6. Open the Admin Portal, enter the administrator key, and verify all records are restored.
7. Instruct field collectors to reconnect during the next sync window. Any visits completed by collectors since the last backup will be uploaded cleanly; previously synced visits will be recognized via their idempotency keys without duplicate records.

---

## 7. Client Build & Packaging Commands

### Web Clients (`tool/build_web_clients.ps1`)

Build both the collector web app and the admin portal, optionally binding the collector identity:

```powershell
powershell -ExecutionPolicy Bypass -File tool/build_web_clients.ps1 `
  -LocalApiBaseUrl http://<computer-wifi-ip>:8787 `
  -CollectorApiKey collector1-secret-key-12345 `
  -CollectorId C001 -SigningBackupConfirmed
```

*(You may alternatively pass `-CollectorNumber 1`, which formats as `C001` automatically).*

### Android Release Packages (`tool/package_android_release.ps1`)

Package a signed release APK and App Bundle with embedded LAN configuration and provisioned collector identity. Create the release signing key once using `tool/create_release_signing.ps1`, then copy its private backup to a separate secure location:

```powershell
powershell -ExecutionPolicy Bypass -File tool/package_android_release.ps1 `
  -BuildName 1.0.0 -BuildNumber 1 `
  -LocalApiBaseUrl http://<computer-wifi-ip>:8787 `
  -CollectorApiKey collector1-secret-key-12345 `
  -CollectorId C001
```

Each collector's artifacts go under `dist/android/C001/` (or its assigned collector ID). The script refuses to overwrite a prior artifact and requires a higher build number for that collector's next release. Keep the same application ID and signing key for updates. The LAN address and collector key are compiled into each package; distribute only to the intended collector on a trusted network. Do not publish a LAN-keyed App Bundle publicly.

For however many collector phones are actually used, assign each a unique collector number and package once per collector with its matching server key. The current collector-number input accepts 1–99; this does not limit participant records. `-SigningBackupConfirmed` only records the operator's acknowledgement; first make and verify an off-PC backup of both `android/app/study-release.jks` and `android/key.properties`. The script does not create that off-device backup, and signed distribution must wait until it exists.

---

## 8. Decommissioning & Production Migration

To transition from the local home-PC sync to cloud production persistence:

1. Stop `local_sync_server.dart`.
2. Migrate `.local_data/records.json` into the production database using the canonical schema:
   ```text
   id, participant { studyId, name, indianPhone }, visitNumber, collectorId,
   createdAt, updatedAt, status, syncState, reviewState, revision,
   confirmation?, stepTwoMeasurement?, stepTwoPlaceholderNote?,
   submittedAt?, archivedAt?, archivedBy?
   ```
3. Remove disposable LAN prototype files:
   - `tool/local_sync_server.dart`
   - `tool/LOCAL_SYNC.md`
   - `lib/local_sync/`
   - `lib/admin/local_api_visit_repository.dart`
   - `.local_data/records.json`, `.local_data/conflicts.json`, and `.bak` snapshots
4. Update entrypoints to select the production cloud repository implementations.
