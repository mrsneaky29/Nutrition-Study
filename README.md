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

For a LAN-only demo in which both websites use the disposable local record
service, supply its URL and matching development key:

```powershell
powershell -ExecutionPolicy Bypass -File tool/build_web_clients.ps1 `
  -LocalApiBaseUrl http://<computer-wifi-ip>:8787 `
  -LocalApiKey <at-least-16-character-private-key>
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

For phone submissions to appear in the admin webpage, start the disposable LAN
bridge with a private development key:

```powershell
$env:LOCAL_SYNC_KEY='<at-least-16-character-private-key>'
dart run tool/local_sync_server.dart --host=<computer-wifi-ip> --port=8787
```

Build or run both clients with the matching key and service address:

```powershell
flutter run -d <device-id> -t lib/main.dart --dart-define=LOCAL_API_BASE_URL=http://<computer-wifi-ip>:8787 --dart-define=LOCAL_API_KEY=<private-key>
flutter run -d chrome -t lib/admin_main.dart --dart-define=LOCAL_API_BASE_URL=http://<computer-wifi-ip>:8787 --dart-define=LOCAL_API_KEY=<private-key>
```

This bridge is for a trusted local network only. Its isolated files and removal
steps are documented in `tool/LOCAL_SYNC.md`.

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

The command also creates a private ignored backup directory. Never distribute
that directory with the APK or commit it to source control.

Create both the directly installable APK and Play Store App Bundle with:

```powershell
powershell -ExecutionPolicy Bypass -File tool/package_android_release.ps1 `
  -BuildName 1.0.0 -BuildNumber 1
```

Versioned artifacts and their SHA-256 checksums are written to `dist/android`.
Increase `BuildNumber` for every distributed update.
