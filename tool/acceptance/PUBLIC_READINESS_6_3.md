# +6.3 public-deployment verification — 2026-09-27

Application release: `411389803c892baddc577371ea5205d848b89b06`.
Active VM release: `20260927T064454Z-b35735ee7d46`.
Collector phone APK remains +6, unchanged.

## Confirmed

- Production build and static analysis passed. 95 focused admin/sync/Study-ID
  tests passed. Additional store/restore suites returned 64 passed, one skipped;
  the skipped test is not counted as verified.
- Isolated browser acceptance covered login, permissions, search/filter/details,
  measurements, edits, archive/restore, CSV, QR administration, mobile scrolling,
  restart persistence, outage recovery, malformed-row isolation and logout.
- Live HTTPS passes normal certificate validation. Admin returns 200; API
  `/health`, `/records`, `/collectors`, `/conflicts` return 401 without a key.
- CORS preflight allows only the configured admin origin; an unrelated origin
  returns 403. Backend listens only on `127.0.0.1:8787`. Active firewall allows
  SSH/HTTP/HTTPS; backend port is not publicly exposed.
- Live browser displays +6.3, authenticated login succeeds, zero active records
  are present, and logout returns to blank key entry.
- Deployed main.dart.js SHA256 matches the local verified production build:
  `4580a21654b5cd2ddfd3350cd2cc18cdd7efbb15aa68b96431395ebb4f2ac422`.
- Backend, Caddy and daily backup timer are active. The earlier scheduled backup
  failed because an older shell script had CRLF line endings. +6.3 uses LF;
  rerunning the systemd backup job succeeded at 06:51:50 UTC with Result=success,
  ExecMainStatus=0 and downloaded-content verification. The next scheduled run
  remains to be observed; manual verification does not prove a future run.
- Offsite destination uses rclone's `study-crypt` encryption layer. Local staging
  is plaintext, root-only (0700), not an encrypted local archive. VM disk is 7%
  used with about 45 GB available. No automatic backup deletion is enabled.
- GitHub main and integration branch contain the application release. The +6.3
  Drive kit and its folder are private, and contain no live state or credentials.
- Identified live synthetic record removed from active state; dedicated local
  acceptance state removed after stopping both test servers. Source fixtures,
  phone storage and historical backups are preserved. Live cleanup has a private
  root-only recovery copy, not included in release artifacts.

## Operational boundaries before real study enrollment

This verifies authenticated deployment, not ethics approval or a comprehensive
security audit. Keep admin credentials and setup QR codes private. Admin logout
is local, not shared-key revocation, and no automatic session expiry exists.
Unreadable records stay on the server for controlled repair; partial exports and
edits are paused. Two-phone takeover verification was waived, not passed.

The study owner must approve participant consent/privacy procedures, authorized
staff, and a local/offsite backup retention schedule. Retained plaintext staging
needs disk monitoring and controlled cleanup; do not indiscriminately purge
recovery copies. An independent recovery drill using the saved recovery key is
recommended before depending on backups for real participant data.
