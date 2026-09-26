# Nutrition Study

Nutrition Study 1.0.0+6 adds mandatory QR sign-in for production collector
builds. The project has two separate clients: the Android collector app
(`lib/main.dart`) and the browser-only administrator portal (`lib/admin_main.dart`).
The collector app has no admin route; the portal prompts for its admin key at
runtime. First-time collector sign-in is QR-only: the app does not ask for a
collector number, server URL, or key and offers no manual sign-in bypass. The
production API is `https://api.nutrition.achantalabs.com`; the admin portal is
`https://admin.nutrition.achantalabs.com`.

The +6 phone build is a separate side-by-side test app
(`org.nutritionstudy.project2.plus5test`, app label `Study Collector +6 Test`,
version code 6). It is not the standard production package or a production
release artifact; no normal production +6 APK has been built yet.
The existing installed app and historical release kits were left unchanged.
Do not treat the completed subset of phone checks as approval to collect real
participant data; several acceptance checks remain outstanding.

The collector keeps unsent submissions in encrypted Android storage and
retries them when its configured service is reachable. Collector credentials
and identity are entered at sign-in; the shared APK does not permanently bind
an account to a phone. Signing in on another phone takes over that collector's
session. Recover pending records from the old phone before clearing or
replacing it. Generated Study IDs use a collision-resistant 16-digit random
suffix; the server checks for duplicates at sync, and the app has no
participant-count cap.

The questionnaire records reasons (`unable` or `declined`) for missing
height, weight, waist, and blood-pressure measurements. BMI is calculated only
when height and weight are present; average blood pressure is calculated only
when both readings are present. The admin record details and CSV export retain
the missing reasons while leaving missing numeric values empty. Exports omit
participant name and phone.

## Current +6 deployment and acceptance status

The production DigitalOcean Ubuntu VPS is active. The backend listens on
`127.0.0.1:8787` behind Caddy, which provides public HTTPS at the API and admin
domains above. Public mode requires HTTPS, an exact allowed admin origin,
distinct collector credentials, and an admin key, each at least 32 characters.
Never expose port 8787 directly or relax these checks for testing.

Automated +6 QR/authentication and UI tests passed (35 tests), public HTTPS
saved-session restoration passed (1 test), and the generic local-session suite
passed (14 tests), for 50 passing tests total. Static analysis completed with
no issues. The +6 physical test app was installed on a Galaxy M14. The user
confirmed a real QR sign-in, creation of a synthetic record while offline,
automatic sync after mobile data was enabled, persistence of the synced record
after closing and reopening the app, and one synthetic record visible on the
server. This verifies that test flow only; it does not establish full release
acceptance.

Physical camera permission grant/denial and settings recovery, invalid QR
handling, background/resume and portrait behavior, session restoration,
sync-idempotency, and another-phone latest-login takeover still need acceptance.
Authenticated admin login, record edits, CSV export, and logout also remain
pending. Signing in on another phone takes over that collector's session; login
is not bound to a phone, and this behavior has not yet been physically
verified. Recover pending records from the old phone before clearing or
replacing it.

Encrypted backup completed a successful manual run after activation, with
remote verification. The scheduled timer's first run has not been observed and
backup retention policy is undecided. Signing keys, server credentials, Drive
recovery material, and participant records must stay out of the repository and
release archives. No Play Store publication is planned.

See [the historical pre-deployment report](PLUS5_PREDEPLOYMENT_REPORT.md),
[the server checkpoint](PLUS5_SERVER_CHECKPOINT.md), and
[the private setup checkpoint](PLUS5_PRIVATE_SETUP_CHECKPOINT.md) for the
recorded verification checkpoints. Later encrypted-backup progress is recorded
in [the backup setup status](tool/vps/OFFSITE_BACKUP_SETUP.md); older checkpoint
documents retain their earlier state rather than serving as live status.

## Build and deploy

Build the public admin site against the production API HTTPS origin:

```powershell
powershell -ExecutionPolicy Bypass -File tool/build_web_clients.ps1 `
  -AdminOnly -PublicRelease `
  -AdminApiBaseUrl https://api.nutrition.achantalabs.com -NoPub
```

This builds only `build/admin_web` and passes the API origin as
`LOCAL_API_BASE_URL`. It does not embed admin or collector keys or collector
identity. `-NoPub` assumes Flutter dependencies are already resolved. Do not
deploy an admin bundle built against a placeholder domain.

Production collector builds use `LOCAL_GENERIC_RELEASE=true`,
`LOCAL_PUBLIC_RELEASE=true`, and the production HTTPS API origin. The first-time
sign-in screen remains QR-only; collector identity and key are supplied by a
collector's QR code. Do not add identity, key, or server fields to the screen
or distribute credentials in the app. If producing a standard signed
production APK, the packaging script requires the existing private signing
files, an off-device signing-backup confirmation, and a build number greater
than any existing artifact. The separately installed +6 test app is not that
production package. For a deliberate new production package:

```powershell
powershell -ExecutionPolicy Bypass -File tool/package_android_release.ps1 `
  -BuildName 1.0.0 -BuildNumber 6 -PublicRelease `
  -LocalApiBaseUrl https://api.nutrition.achantalabs.com `
  -SigningBackupConfirmed -NoPub
```

Use a higher build number if 6 already exists in `dist/android/shared/`. Never
pass collector credentials or identity to the package script.

Follow [the VPS deployment guide](tool/vps/README.md) for credential
generation, exact CORS-origin configuration, Caddy setup, release import,
activation, and health checks. Configure the admin origin without a trailing
slash. The backend must remain bound to loopback, with Caddy as its public TLS
reverse proxy. Full physical and admin acceptance, observation of a scheduled
backup, and a decided retention policy remain release readiness work before
any live use.

## Acceptance checks

The acceptance kit has synthetic fixtures, Android and admin checklists, a
results template, release gates, and the +6 QR verification record under
[tool/acceptance](tool/acceptance/README.md). Use synthetic records for
acceptance. For functional admin UI testing against an isolated local backend,
use Option A in [the admin checklist](tool/acceptance/03_ADMIN_ACCEPTANCE_CHECKLIST.md).
Do not point that harness at the production VPS.

Run the recorded web build configuration regression check with:

```powershell
powershell -ExecutionPolicy Bypass -File tool/tests/test_web_build_configuration.ps1
```

The suite verifies HTTPS-origin validation for public admin builds and checks
that collector secrets and identity are absent from the admin Flutter build
arguments. See [the +6 QR verification record](tool/acceptance/PLUS6_QR_VERIFICATION.md)
and [release gate checklist](tool/acceptance/06_RELEASE_GATE_CHECKLIST.md) for
the test evidence and remaining checks. Historical +2/+3/+4/+5 kits and reports
retain their original checkpoint contents; use the current deployment and
acceptance status here rather than treating older snapshots as live status.

## Older local and Firebase paths

The local LAN sync server and Firebase collector integration are separate
development alternatives, not the current +6 public deployment path. LAN HTTP
is restricted to trusted private networks and must never be exposed to the
internet. The Firebase visit repository and hosted sign-in flow are not yet
connected end-to-end. See [LOCAL_SYNC.md](tool/LOCAL_SYNC.md) for LAN-only
development instructions.
