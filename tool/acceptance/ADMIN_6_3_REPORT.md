# Admin console +6.3 — verification and release notes

Date: 2026-09-27. Collector phone APK unchanged (+6).

## Changes

- Sign out on desktop/mobile closes the browser API client and removes the
  dashboard, returning to blank key entry. It does not revoke or rotate the
  shared admin key, invalidate other browsers, or implement timed expiry.
- Server record decoding is isolated per record. Malformed rows stay on the
  server; valid rows load with an explicit warning and excluded-record count.
- The banner states that counts cover valid rows only. Editing, archive and CSV
  export pause until the malformed records are repaired and refreshed.
- Invalid envelopes fail with a safe error rather than masquerading as an empty
  dataset. Record parsing failures do not expose raw participant values.
- Exact Study ID fixes from +6.2 are retained.

## Verification

- 95 focused admin/backend/Study-ID tests passed; static analysis found no issues.
- Regression tests cover mixed malformed/valid input, invalid Study ID, repair
  recovery, export disabling, and sign-out controls on 390/1200-pixel widths.
- Isolated browser test: deliberately invalid synthetic phone caused one warning,
  three valid records stayed visible, CSV was disabled, and detail edit/archive
  buttons were disabled. The invalid phone itself was not exposed.
- Repairing the record restored all four rows and export access. Logout returned
  to blank key entry and removed the records from the page.
- Earlier +6.2 browser matrix covered details, missing reasons/calculations,
  search/filter/CSV, archive/restore, collector creation/QR/reset/disable, mobile
  scrolling, backend restart persistence, and outage recovery.
- Two-phone takeover support remains; its test was waived by the user. No claim
  of two-phone browser verification or approval for real study enrollment.

## Remaining boundaries

Malformed-record recovery does not edit or delete the unreadable server rows;
repair needs a controlled administrative/server workflow. Backend ingestion can
still accept phone values the admin model rejects, so the warning is a safety
boundary, not a comprehensive backend-schema migration. Existing acceptance
sample JSON needs added confirmation/submission/derived fields before upload.
The admin key is a shared credential and sign-out is local, not server revocation.

## Cleanup

The only identified live Synthetic Test record was removed from active state;
zero live records remained at the cleanup check. A root-only recovery copy is
kept at /root/synthetic-cleanup-recovery-20260927/records.json. Historical encrypted
backups and phone storage were not purged. Dedicated local acceptance state is
removed after testing. Source fixtures and regression tests remain in Git.

Release packages exclude credentials, private QR codes, participant state,
recovery/signing material, and private live screenshots.
