# Project2

Project2 has two deliberately separate clients:

- a collector app for Android phones and mobile browsers (`lib/main.dart`);
- a browser-only administration portal (`lib/admin_main.dart`).

The collector app does not contain an admin route or admin login. It includes
a compact, custom interviewer-entered NCD-risk questionnaire for adults 18+:
demographics, tobacco/alcohol, diet, activity, sleep, reported diagnoses, and
height, weight, waist, and two blood-pressure readings. It borrows the shape
of established surveillance tools but is not a WHO STEPS implementation.

Participant name and phone are retained only for the operational repeat-visit
workflow. Questionnaire CSV exports use the study ID and deliberately omit
those direct identifiers.

Collector submissions are retained across app restarts in encrypted Android
storage. Pending and failed submissions remain available for manual retry while
the production cloud synchronization layer is still disconnected.

## Local collector app

Connect an Android phone by USB or wireless debugging, then run:

```powershell
flutter run -d <device-id> -t lib/main.dart
```

Local demo account:

- collector number: `1`

## Local admin webpage

Run the independent web entrypoint in Chrome:

```powershell
flutter run -d chrome -t lib/admin_main.dart
```

The admin portal reads from the local LAN adapter by default. Its Firebase
session and collector-account adapters are implemented; the Firebase visit
repository and hosted sign-in screen remain to be connected.

## Firebase collector build

The production collector selects Firebase explicitly and fails at startup when
any deployment value is missing:

```powershell
flutter build apk --release -t lib/main.dart `
  --dart-define=STUDY_RUNTIME_MODE=firebase-production `
  --dart-define=STUDY_ID=nutrition-study-2026 `
  --dart-define=FIREBASE_API_KEY=<web-api-key> `
  --dart-define=FIREBASE_APP_ID=<firebase-app-id> `
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=<sender-id> `
  --dart-define=FIREBASE_PROJECT_ID=nutrition-study-2026 `
  --dart-define=FIREBASE_AUTH_DOMAIN=nutrition-study-2026.firebaseapp.com `
  --dart-define=FIREBASE_FUNCTIONS_REGION=asia-south1
```

Do not distribute a Firebase production build until one test collector has
completed phone-to-admin synchronization in the deployed project.

## Collector and admin websites

Build both independently so the collector and administrator entrypoints can be
hosted at different addresses:

```powershell
powershell -ExecutionPolicy Bypass -File tool/build_web_clients.ps1
```

For a LAN-only build using the home-PC record service, supply its URL,
collector key, and optional collector identity (`-CollectorId C001` or `-CollectorNumber 1`). The admin website asks for its separate key at runtime:

```powershell
powershell -ExecutionPolicy Bypass -File tool/build_web_clients.ps1 `
  -LocalApiBaseUrl http://<computer-wifi-ip>:8787 `
  -CollectorApiKey <collector-key-at-least-16-characters> `
  -CollectorId C001
```

The outputs are `build/collector_web` and `build/admin_web`. The collector build
is an installable mobile web app. For low-memory local previews, serve either
already-built directory with the dependency-free Node server:

```powershell
node tool/static_site_server.js --root=build/collector_web --port=8085
node tool/static_site_server.js --root=build/admin_web --port=8086
```

Firebase Hosting has separate `collector` and `admin` targets configured in
`firebase.json`. Their actual Firebase site IDs will be assigned after the
Firebase project and billing account are available.

## Shared local records

For phone submissions to appear in the admin webpage, start the LAN service
with distinct collector keys and a separate administrator key (minimum 16 characters each).

> [!CAUTION]
> **Security Notice**: Cleartext LAN HTTP (`http://<ip>:8787`) and bearer keys are designed
> **strictly for trusted home or local Wi-Fi networks**. They are **NOT suitable for public internet
> exposure**. Never expose this service directly to the public internet.

### Collector Credential Binding & Server Start-Up

Collector credentials bind each bearer key to an explicit collector identity:
- Format: `LOCAL_SYNC_COLLECTOR_KEYS=C001:key1,C002:key2` (each key >= 16 characters).
- The server derives the authorized collector identity from the key; incoming upload payloads must match this `collectorId` or the server rejects the request.
- The administrator key is configured via `LOCAL_SYNC_ADMIN_KEY` (minimum 16 characters) and is **strictly entered at runtime** in the browser.

#### PowerShell (Windows):

```powershell
$env:LOCAL_SYNC_COLLECTOR_KEYS = "C001:collector1-secret-key-12345,C002:collector2-secret-key-67890"
$env:LOCAL_SYNC_ADMIN_KEY = "admin-secret-management-key-99999"
dart run tool/local_sync_server.dart --host=<computer-wifi-ip> --port=8787
```

#### Bash (Linux / macOS):

```bash
export LOCAL_SYNC_COLLECTOR_KEYS="C001:collector1-secret-key-12345,C002:collector2-secret-key-67890"
export LOCAL_SYNC_ADMIN_KEY="admin-secret-management-key-99999"
dart run tool/local_sync_server.dart --host=<computer-wifi-ip> --port=8787
```

### Collector Provisioning & Offline Safety

Field phones are provisioned and locked to their collector identity at build time or during first-time setup:

```powershell
# Collector app (embeds collector upload key and locks collector identity):
flutter run -d <device-id> -t lib/main.dart `
  --dart-define=LOCAL_API_BASE_URL=http://<computer-wifi-ip>:8787 `
  --dart-define=LOCAL_API_KEY=collector1-secret-key-12345 `
  --dart-define=LOCAL_COLLECTOR_ID=C001

# Admin web portal (prompts for admin key interactively at runtime in the browser):
flutter run -d chrome -t lib/admin_main.dart `
  --dart-define=LOCAL_API_BASE_URL=http://<computer-wifi-ip>:8787
```

Field staff can collect while offline. Submitted records are saved in Android secure storage. When the configured home-PC endpoint becomes reachable, the app retries pending submissions while it is open and active; the endpoint is not discovered automatically.

### Participant ID Scheme & Repeat Visits

- **Collector-Scoped Study IDs (No 200 Limit)**: Participant IDs follow the scheme `C01-000001`, `C02-000001`, etc. (collector prefix `C01`..`C99`, sequence starting at `000001` and growing as needed). Different collector numbers avoid cross-collector collisions; do not provision the same number on two independent phones. Legacy `P001` formats remain supported.
- **Online Repeat-Visit Lookup (`GET /participants/lookup`)**: When the configured server is reachable, collectors can look up participants by phone number to verify study IDs and prior visits.
- **Offline Repeat Visits**: Verify the participant's prior Study ID using the study's physical records or study card and enter it for Visit 2+. The app does not issue study cards or guarantee correct linking for a mistyped ID.

### Sync-Window Workflow (2–3 Hours/Day)

The home-PC server does not need to run continuously. A 2–3 hour daily window
may work if every collector returns, keeps the app active until pending sync reaches zero, and the administrator verifies a backup:
- **During the day**: Field collectors work offline. Visits are securely stored in encrypted local storage on each phone.
- **During the sync window**: Collectors connect to the local Wi-Fi network, open the app, and wait for pending visits to sync with the configured home-PC server.
- **Idempotency**: Retries and network drops are handled transparently using persistent idempotency keys without duplicate records or overwriting admin corrections.

### Real Server Conflict Inbox (`/conflicts`) & Admin Resolution

- Discrepancies (such as `participant_mismatch`, `duplicate_visit`, or `idempotency_collision`) return HTTP 409 Conflict and are stored in the server conflict inbox at `/conflicts` (`.local_data/conflicts.json`).
- On the phone, conflicting records remain locally stored with a **Sync conflict** state, and automatic retries are paused.
- In the Admin Portal (`lib/admin_main.dart`), administrators review conflicts in the **Sync conflicts** tab and resolve mismatches using the review controls. Verify the result against the retained phone copy.

### Off-Device Backups & Disaster Recovery

The automatic `.local_data/records.json.bak` snapshot is on the same disk and is
**not** an off-device backup. Drive failure or system corruption will destroy both files.
Regularly copy both `records.json` and `conflicts.json` to an external USB drive or network share:

#### PowerShell (Windows USB/Network Backup):

```powershell
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = "D:\StudyBackups"  # Path to external USB drive or network share
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

If the primary `records.json` is corrupted on disk, the server automatically recovers from `.local_data/records.json.bak`. For full disaster recovery steps and migration procedures, see [LOCAL_SYNC.md](tool/LOCAL_SYNC.md).

## Verification

```powershell
flutter analyze
flutter test
flutter build apk --debug -t lib/main.dart
flutter build web -t lib/admin_main.dart
```

## Android release package

Release builds use a private upload/signing key at
`android/app/study-release.jks` with credentials in
`android/key.properties`. Both files are ignored by source control. Back up
both files securely: Android and Google Play updates must be signed with the
same key.

Create the signing key once:

```powershell
powershell -ExecutionPolicy Bypass -File tool/create_release_signing.ps1
```

The command also creates a private ignored backup directory on this computer. Copy both backup files to a separate secure location before distributing an APK; a same-disk backup will not survive PC failure. Never distribute the signing files with the APK or commit them to source control.

Create both the directly installable APK and Play Store App Bundle with:

```powershell
powershell -ExecutionPolicy Bypass -File tool/package_android_release.ps1 `
  -BuildName 1.0.0 -BuildNumber 1 -SigningBackupConfirmed
```

For a LAN-connected collector package, add the home-PC service address,
collector key, and provisioned collector identity (`-CollectorId C001` or `-CollectorNumber 1`):

```powershell
powershell -ExecutionPolicy Bypass -File tool/package_android_release.ps1 `
  -BuildName 1.0.0 -BuildNumber 1 `
  -LocalApiBaseUrl http://<computer-wifi-ip>:8787 `
  -CollectorApiKey <collector-key-at-least-16-characters> `
  -CollectorId C001 -SigningBackupConfirmed
```

The service address, key, and provisioned collector identity are embedded in the APK. A package built with a
private Wi-Fi address will sync only while the phone can reach that network;
it is not suitable for public distribution as-is.

Versioned artifacts and their SHA-256 checksums are written to `dist/android/<collector-id>/` (or `unprovisioned/`). The script refuses to replace prior artifacts. Increase `BuildNumber` for every update to a given collector, and retain the same signing key and application ID. A LAN-keyed App Bundle is not suitable for public Play Store distribution as-is.

For each collector phone, assign a unique collector number, configure its matching server key, and run the packaging command separately with that collector's key. The current collector-number input accepts 1–99; this is not a participant-count limit or a requirement to provision any fixed number of phones. The switch `-SigningBackupConfirmed` is an acknowledgement, not an automated backup check: do not use it until both signing files have been copied off this PC and verified. Do not create or distribute a signed release while the only backup is the ignored directory on this PC.
