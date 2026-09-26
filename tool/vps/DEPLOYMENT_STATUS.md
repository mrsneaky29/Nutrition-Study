# +5 deployment verification — 2026-09-26

## Active deployment

- Admin: https://admin.nutrition.achantalabs.com
- API: https://api.nutrition.achantalabs.com
- VM: 206.189.140.255 (Ubuntu 24.04 LTS)
- Active release: `20260926T132101Z-526d28b71cb0`
- Backend listens on `127.0.0.1:8787`; public access is through Caddy.
- Existing credentials and state were preserved; initial provisioning was not rerun.

## Verified live

- Both DNS A records resolve to the VM.
- Both HTTPS endpoints pass normal certificate validation; Caddy issued certificates.
- Admin page responds 200; HTTP redirects to HTTPS (308).
- API health returns 401 without authentication and 200 with the existing admin key.
- Exact admin origin is allowed; unrelated origin receives no permissive CORS header.
- A raw collector credential cannot list admin records (401). This is not a
  substitute for a valid-session collector authorization test.
- Backend, Caddy and daily encrypted-backup timer are active.
- Manual encrypted backup after activation completed with Result=success,
  ExecMainStatus=0. First scheduled timer run remains unobserved.

## Phone test status

The normal +5 APK could not update the phone's existing package because its
signing certificate differed. No uninstall or data clearing was performed.
A separate `org.nutritionstudy.project2.plus5test` package was installed instead.
Its initial storage startup failure was traced to missing Android generated
plugin registration. Running `flutter pub get` regenerated the registration;
the corrected APK was installed successfully. Field sync is not yet verified.

Android test builds use `STUDY_SIDE_BY_SIDE_TEST=true`, version 1.0.0+5,
LOCAL_GENERIC_RELEASE=true, LOCAL_PUBLIC_RELEASE=true and the HTTPS API origin.
The phone test package has independent local storage but uses the same server.
Never enter real participant data until acceptance is complete.

## Remaining acceptance and release work

- QR collector authentication integration and tests (Antigravity work).
- Portrait behaviour and revised login verification on the phone.
- Mobile-data offline collection, retry/idempotency, reopen/persistence and
  latest-login takeover tests with synthetic records.
- Authenticated live admin browser login/logout and record workflow acceptance.
- Observe first scheduled backup; decide local/remote retention before real data.
- Publish final reviewed source and artifacts to GitHub/Drive. Existing +2/+3/+4
  kits remain unchanged. No credentials belong in those artifacts.
