# Vivayu 1.0.4+12 — volunteer login and public APK

Verified 2026-11-09. Visible app name remains Vivayu. Existing schema 4,
research estimates, measurement corrections and signing identity are retained.

## Behavior and access boundaries

- Production login offers QR sign-in or **Continue as volunteer**. The latter
  asks for no details. First sign-in needs internet. English and Telugu copy
  are bundled; no keyboard-language changes are made.
- The app generates a secure 256-bit installation key and saves it before
  networking. Registration is idempotent for that key. Logout preserves this
  volunteer identity and saved records; restart restores the usual session.
- Internal C-prefixed IDs remain distinct per installation. The server derives
  Volunteer labels from its account registry, not from submitted record labels.
  The app, admin account cards, record lists/details and search show Volunteer.
  The raw ID is retained for ownership and CSV audit continuity.
- Volunteer lookup is scoped to its own records. Volunteer submissions must
  use their own Study ID prefix and cannot target another collector's record,
  upload key, Study ID or resolved conflict. Administrative read/edit/archive,
  collector management and research endpoints remain protected.
- The anonymous bootstrap is behind the existing public HTTPS/origin checks,
  returns no-store responses and accepts only an installation key. Registration
  is capped at 20 attempts/IP/minute, uploads at 60/identity/minute, and new
  registrations at 10,000 volunteer accounts. Disabled identities cannot resume.
  These controls reduce abuse; anonymous access does not establish a person's
  identity or guarantee spam-free submissions.
- `collector_accounts.json` stores the role with existing protected credentials;
  participant records and questionnaire formats are not migrated. Old staff
  credentials and sessions continue to work. The new activation helper disables
  volunteer keys before a legacy rollback because old servers lack this role.

## Verification

- Full default Flutter suite: **313 passed, 15 configuration-dependent skips**.
- Production-configured login/session tests: **11 passed**, including a new
  no-fields volunteer login, logout/reuse and restored app session test.
- Volunteer HTTP/store tests: **4 passed**, using real isolated loopback HTTP,
  temporary stores and synthetic records. Includes persistence, session rotation,
  disabled access, restricted lookup, cross-identity submission denial, no admin
  access, registration throttling and HTTP client bootstrap.
- Admin dashboard + volunteer API focused suites: **23 passed**. Includes UI
  search/labels and archive/restore retaining the Volunteer label.
- Translation key/placeholder check passed. Server static analysis is clean.
  App analysis reports one pre-existing style info in
  `questionnaire_measurement_editor.dart:115`; no errors or warnings.
- Signed APK and AAB built. APK signature, package ID
  `org.nutritionstudy.project2`, version `1.0.4`, build 12 and cleartext guard
  verified. Same certificate SHA256 as the existing official APK:
  `36b7e26028c228305181b060a64e9e3d5e72747236214b7ec553d007a58cefb9`.
- Admin production bundle built with the existing service-worker retirement
  and no-cache bootstrap handling. No admin credential is embedded.

## Artifacts

- APK SHA256: `1455e62f7894ad4560fdececb22540778034295920b226751d863b12d42b19f0`
- AAB SHA256: `0eda8f49d24cc542cff5ad430e809c9e75b525869c1c8df814832ebd6ae5ca06`
- Admin JS SHA256: `896e049ab34359ea62f0e7287dced6f2e1868dfcb9d359d151f1e37a27bce357`
- Public download: `https://achantalabs.com/downloads/Vivayu.apk`.

The download is published only after the backend and admin deployment succeeds.
It is stored separately from static releases under the existing DigitalOcean
public-site directory. No record store, QR, access key or signing key is hosted
there. Existing site design, analytics and rice services are preserved.

Physical Android installation/camera operation was not tested in this run. The
existing official app can be updated in place; do not uninstall or clear data.
Live deployment and public-download checks are recorded in the local release
verification output; test counts above are software checks, not phone approval.

## Live verification and completion — 2026-11-10

- Backend/admin release: `vivayu-volunteer-1.0.4-12-4a7aac96`.
- Static homepage release: `vivayu-download-20261109-12`.
- Deployment on 9 November preserved all 43 existing records (43 before and 43
  after activation). No synthetic production accounts or survey records were
  created for verification. Both Caddy and `plus5-vps.service` are active.
- On 10 November the public APK and admin page returned HTTPS 200. The homepage
  contained the Download APK anchor. The APK is served with the Android package
  MIME type and is 72,825,708 bytes. Its deployed SHA256 and the deployed admin
  JavaScript SHA256 match the artifacts listed above.
- The live volunteer endpoint rejected an empty request with 400; anonymous
  record listing remained 401. Authenticated isolated tests, not real survey
  accounts, were used for the complete volunteer workflow.
- Completion rerun: 313 Flutter tests passed (15 configuration skips), plus two
  isolated rollback-policy unit tests. No production rollback was triggered.
