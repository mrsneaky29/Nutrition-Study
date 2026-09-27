# Admin console +6.2 browser verification — 2026-09-27

Testing used an isolated loopback backend with four fictional records and
synthetic credentials, not production participant submissions. Desktop testing
used the in-app browser; responsive checks used a 390 × 844 viewport. The
installed collector APK remains +6. No phone storage was cleared.

## Verified

- Empty and invalid admin keys fail; collector credentials cannot open admin.
- Valid admin login loads four records. Reload returns to key entry.
- Search matches and no-match states, submitted filter, and filtered CSV work.
- CSV omits participant name and phone; missing measurements retain reasons.
- Details distinguish declined height, unavailable weight/waist/BP, absent BMI
  or average BP, and calculated BMI/BP when inputs are available.
- Participant edits invalidate confirmation; saving is blocked until confirmed.
  Confirmed name editing succeeds and questionnaire data remains present.
- Archive asks for confirmation, retains the record, and increments the archive
  count. Restore asks for confirmation and returns the archive count to zero.
- Collector creation produces the next number. Private QR is rendered locally
  with a warning and close control. Reset and disable have confirmation dialogs.
  Disabled collectors lose the QR and disable controls. Accounts survive backend
  restart; the two-phone session takeover is not a browser-only test.
- Mobile collector controls wrap, QR dialog fits, navigation changes sections,
  and record details scroll to the bottom edit/archive controls.
- Backend outage keeps cached records visible with a warning and disables
  editing, archive, and CSV. Restart reconnects and restores export access.
- 91 focused admin/backend/Study-ID automated tests passed. Static analysis
  reported no issues. Release admin web build succeeded.

## Fixed in this checkpoint

The browser rounded C01-9283019284710293 to C01-9283019284710292.
The backend retained the correct original string, but browser views/search/CSV
used the rounded string. Normalization now uses BigInt for collector-scoped
suffixes and legacy IDs; the admin parser uses an exact immutable string policy
instead of converting the suffix into an integer range. Regression coverage
includes IDs beyond 64-bit length and the admin REST parsing path.
Existing source fixtures and earlier releases are preserved.

## Open limitations / failed checks

- No explicit administrator logout control or timed session expiry. Reload
  clears the runtime key; this is not equivalent to timed expiry or revocation.
- API can accept malformed Indian phone numbers that the admin model rejects.
  A single malformed fixture prevented list loading and displayed a raw
  validation error. This compatibility/privacy issue is not fixed here.
- Collector-key rejection without a phone session uses a misleading
  "Collector session expired" message instead of an admin-only explanation.
- The older sample JSON in 04_SYNTHETIC_TEST_FIXTURES.md needs derived fields,
  submission time, and confirmation before POST ingestion. The isolated seeder
  supplied these fields; the document is not a directly runnable upload kit.
- Browser tests do not establish two-phone takeover, real camera QR scanning,
  or approval to collect real study data. API and widget tests cover conflict
  resolution; no new browser conflict fixture was injected in this run.

## Cleanup boundary

Dedicated local test state and the identified live Synthetic Test record are
the operational cleanup targets. Source fixtures and regression tests remain.
Encrypted historical backups, recovery keys, collector credentials, and phone
storage must not be broadly purged. Any retained recovery copy is private and
not part of the release package.
