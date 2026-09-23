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

For local previews, run the script without collector-specific parameters. Its
older optional keyed-build parameters are not part of the shared-APK release
flow. The separate admin website asks for its key at runtime.

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

Replace every angle-bracketed value below with a different, privately generated secret before starting the server; the text shown is not a usable credential.

```powershell
$env:LOCAL_SYNC_COLLECTOR_KEYS = "C001:<unique-random-secret-for-collector-1>,C002:<unique-random-secret-for-collector-2>"
$env:LOCAL_SYNC_ADMIN_KEY = "<unique-random-admin-secret>"
dart run tool/local_sync_server.dart --host=<computer-wifi-ip> --port=8787
```

#### Bash (Linux / macOS):

```bash
export LOCAL_SYNC_COLLECTOR_KEYS="C001:<unique-random-secret-for-collector-1>,C002:<unique-random-secret-for-collector-2>"
export LOCAL_SYNC_ADMIN_KEY="<unique-random-admin-secret>"
dart run tool/local_sync_server.dart --host=<computer-wifi-ip> --port=8787
```

### Collector Sign-In & Offline Safety

Install the same collector APK on each phone. On the sign-in screen, a
collector enters their assigned number (for example, `1`), the home-PC server
URL, and their access key. These details are not embedded in the APK. A
successful sign-in on another phone becomes the current session for that
collector; there is no permanent device binding. The previous phone cannot
sync under its superseded session. Its unsynced records stay on that phone,
so recover and sync them before replacing or clearing the device. Explicit
sign-out clears the saved collector key and session token, not visit records.

```powershell
# Collector app: enter server URL, collector number, and key on screen.
flutter run -d <device-id> -t lib/main.dart

# Admin web portal (prompts for admin key interactively at runtime in the browser):
flutter run -d chrome -t lib/admin_main.dart `
  --dart-define=LOCAL_API_BASE_URL=http://<computer-wifi-ip>:8787
```

Field staff can collect while offline after setup. Submitted records are saved
in Android secure storage. When the configured home-PC endpoint becomes
reachable, the app retries pending submissions while it is open and active;
the endpoint is not discovered automatically.

### Participant ID Scheme & Repeat Visits

- **Collision-safe Study IDs (No 200 Limit)**: The app generates a new Study ID from the collector prefix and a random 16-digit suffix, such as `C01-4827163094582731`, rather than a per-phone sequence. The same collector can therefore switch phones without suggesting the same next ID. The server still checks for collisions at sync time. Legacy `C01-000001` and `P001` IDs remain valid for existing participants. Study IDs are separate from the simple visit number shown for repeat visits.
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
Use the official backup utility (`tool/backup_utility.ps1` or `tool/backup_utility.dart`) to create cryptographic SHA-256 verified off-device backups to an external USB drive or network share:

Stop the sync server after all phones have synced and before backing up. On Windows, the command rejects destinations it cannot identify as removable, USB-attached, or remote network storage; a same-PC fixed-disk path is not accepted.

- **Backup (post-sync window)**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File tool/backup_utility.ps1 -Action Backup -Destination "E:\StudyBackups"
  ```
- **Verify integrity**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File tool/backup_utility.ps1 -Action Verify -BackupPath "E:\StudyBackups\backup_20260923_180000"
  ```
- **Safe restore**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File tool/backup_utility.ps1 -Action Restore -BackupPath "E:\StudyBackups\backup_20260923_180000" -ConfirmOverwrite
  ```
- **Recover after an interrupted restore, before restarting the server**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File tool/backup_utility.ps1 -Action Recover -Target ".local_data"
  ```
- **Automated self-test**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File tool/backup_utility.ps1 -Action SelfTest
  ```

*(Direct Dart alternatives: `dart run tool/backup_utility.dart backup|verify|restore|test`)*.

If the primary `records.json` is corrupted on disk, the server automatically recovers from `.local_data/records.json.bak`. For full operator instructions, see [BACKUP_INSTRUCTIONS.md](tool/BACKUP_INSTRUCTIONS.md) and [LOCAL_SYNC.md](tool/LOCAL_SYNC.md).

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

For a LAN-connected collector package, you may include a default home-PC
service address, but not a collector key or collector identity:

```powershell
powershell -ExecutionPolicy Bypass -File tool/package_android_release.ps1 `
  -BuildName 1.0.0 -BuildNumber 1 `
  -LocalApiBaseUrl http://<computer-wifi-ip>:8787 `
  -SigningBackupConfirmed
```

The optional service address is a default, not a device assignment. Collectors
enter their own number and key at runtime and can change phones by signing in
on the new phone. A private Wi-Fi service address works only while the phone
can reach that network; this LAN configuration is not a public-internet sync
service.

Versioned artifacts and their SHA-256 checksums are written to
`dist/android/shared/`. The script refuses to replace prior artifacts. Increase
`BuildNumber` for every update, and retain the same signing key and
application ID. The same APK can be installed on every collector phone.

Assign collector numbers and matching server keys to people, not phones. Each
person enters their number and key when signing in; the most recent successful
sign-in takes over that collector session. The switch
`-SigningBackupConfirmed` is an acknowledgement, not an automated backup
check: do not use it until both signing files have been copied off this PC and
verified. The generic login and collision-safe ID paths have automated tests;
before real-data distribution, configure the actual home-PC server and admin
portal, verify an off-PC participant-data backup and restore, and run an
offline-to-sync trial on more than one physical phone.
