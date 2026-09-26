# Nutrition Study

Nutrition Study 1.0.0+5 is a synthetic-data pre-deployment release. It has two
separate clients: the shared Android collector app (`lib/main.dart`) and the
browser-only administrator portal (`lib/admin_main.dart`). The collector app
has no admin route; the portal prompts for its admin key at runtime. Do not
treat this checkpoint as approval to collect live study data.

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

## Current +5 deployment status

The prepared DigitalOcean Ubuntu VPS runs the backend as a private loopback
service. Caddy is installed but inactive. Private backend checks have passed; the
admin origin is reserved as `https://admin.pending.invalid`. The real domain,
public Caddy routes, TLS certificates, and public admin deployment are still
pending. Public mode requires HTTPS, an exact allowed admin origin, distinct
collector credentials and an admin key, each at least 32 characters. Never expose
port 8787 directly or relax these checks for testing.

Encrypted Google Drive backup and isolated restore checks have passed. The
systemd backup unit completed a successful manual run and its journal confirmed
remote verification. The recovery key is stored separately in an owner-only
Drive folder and on the user's USB copy. The daily timer is enabled for 03:30
UTC with up to 15 minutes of randomized delay (09:00–09:15 IST); its first
scheduled execution has not yet been observed. Keep signing keys, server
credentials, Drive recovery material, and participant records out of the
repository and release archives. No Play Store publication is planned.

See [the historical pre-deployment report](PLUS5_PREDEPLOYMENT_REPORT.md),
[the server checkpoint](PLUS5_SERVER_CHECKPOINT.md), and
[the private setup checkpoint](PLUS5_PRIVATE_SETUP_CHECKPOINT.md) for the
recorded verification checkpoints. Later encrypted-backup progress is recorded
in [the backup setup status](tool/vps/OFFSITE_BACKUP_SETUP.md); older checkpoint
documents retain their earlier state rather than serving as live status.

## Build and deploy

Build the public admin site against the actual API HTTPS origin after the real
domain is configured:

```powershell
powershell -ExecutionPolicy Bypass -File tool/build_web_clients.ps1 `
  -AdminOnly -PublicRelease -AdminApiBaseUrl https://api.YOUR-DOMAIN -NoPub
```

This builds only `build/admin_web` and passes the API origin as
`LOCAL_API_BASE_URL`. It does not embed admin or collector keys or collector
identity. `-NoPub` assumes Flutter dependencies are already resolved. The
placeholder `YOUR-DOMAIN` must be replaced; do not deploy an admin bundle built
against `api.example.org` or any placeholder domain.

The signed shared Android APK is 1.0.0+5 and accepts the final HTTPS API URL at
sign-in, so it does not need to be rebuilt just for domain setup. If a new APK
is needed, the packaging script requires the existing private signing files,
an off-device signing-backup confirmation, and a build number greater than any
existing artifact. Build number 5 is shown only as a release example; the
script refuses to replace an existing package. For a deliberate new package:

```powershell
powershell -ExecutionPolicy Bypass -File tool/package_android_release.ps1 `
  -BuildName 1.0.0 -BuildNumber 5 -PublicRelease `
  -LocalApiBaseUrl https://api.YOUR-DOMAIN `
  -SigningBackupConfirmed -NoPub
```

Use a higher build number when 5 already exists in `dist/android/shared/`.
Collectors enter their own number and key at runtime; never pass collector
credentials or an identity to the package script.

Follow [the VPS deployment guide](tool/vps/README.md) for credential
generation, exact CORS-origin configuration, Caddy setup, release import,
activation, and health checks. Configure the admin origin without a trailing
slash. The backend must remain bound to loopback, with Caddy as its public TLS
reverse proxy. Finish DNS, TLS, final admin build, phone-to-admin sync, and
synthetic backup/restore checks before any live use.

## Acceptance checks

The acceptance kit has synthetic fixtures, Android and admin checklists, a
results template, and release gates under [tool/acceptance](tool/acceptance/README.md).
For functional admin UI testing before a public domain exists, use Option A in
[the admin checklist](tool/acceptance/03_ADMIN_ACCEPTANCE_CHECKLIST.md): it
requires a fresh local private-mode backend and a private admin web build. Do
not point that harness at the production VPS. Option B and public deployment
remain blocked until the domain, DNS, and TLS are ready.

Run the recorded web build configuration regression check with:

```powershell
powershell -ExecutionPolicy Bypass -File tool/tests/test_web_build_configuration.ps1
```

The suite verifies HTTPS-origin validation for public admin builds and checks
that collector secrets and identity are absent from the admin Flutter build
arguments. For all release gates and previously recorded test totals, see
[the release gate checklist](tool/acceptance/06_RELEASE_GATE_CHECKLIST.md).

## Older local and Firebase paths

The local LAN sync server and Firebase collector integration are separate
development alternatives, not the current +5 public deployment path. LAN HTTP
is restricted to trusted private networks and must never be exposed to the
internet. The Firebase visit repository and hosted sign-in flow are not yet
connected end-to-end. See [LOCAL_SYNC.md](tool/LOCAL_SYNC.md) for LAN-only
development instructions.
