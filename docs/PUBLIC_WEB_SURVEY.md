# Public Vivayu research estimates and optional survey

The Achanta Labs public website calls POST `/public/research-estimate` with only
the ten model inputs. It uses `scoreIhdsResearchRisk` unchanged and never calls
record/account/session methods. Names and phones are rejected on this route.
Results describe newly reported diagnoses over the historical IHDS waves,
not current disease status or validated individual clinical predictions.

POST `/public/survey` requires explicit consent version
`vivayu-web-survey-2026-11-v1`, a complete schema-4 questionnaire, repeated
matching identity and random in-memory submission/installation tokens.
Validation precedes persistent writes. Derived BMI, waist/hip ratio, weekly
activity and average BP are calculated on the server. Missing measurements need
explicit unable/declined reasons. Self-submitted visits use a restricted Volunteer
account and the existing survey schema; provenance and consent time are retained
in the existing note. No app update, admin UI change or record migration is needed.

Retrying identical data with the same tokens returns the existing receipt.
Changed data or another token cannot overwrite a prior submission. An uncertain
save should be retried on the same page before closing it; nothing is put in
browser storage. The public receipt contains no name, phone or access credential.

Only these public routes accept the Achanta Labs origin. Existing private API
origin/auth/session controls remain unchanged. JSON-only POST, no query strings,
4 KiB/16 KiB body limits, per-client 60/10 requests per minute and no-store
responses bound the public surface. Public request failures do not log bodies or
exception stack traces. The web page discloses indefinite record/backup retention.
This storage choice is separate from study consent handled outside the app.

Verification: `test/local_sync/public_research_test.dart` uses disposable stores
and synthetic answers to check no-save writes, shared-score parity, eligibility,
consent, malformed input, rate limits, CORS/TLS, calculations, normal admin
visibility, idempotency and restart persistence. No live synthetic survey is
created during deployment verification.

## Verification checkpoint — 10 November 2026

- Full Flutter regression suite: 320 passed, 15 existing skips.
- Production-configured collector login/session checks: 11 passed.
- Public endpoint integration tests: 7 passed (included in the full suite).
- Website event-flow unit tests: 6 passed; JavaScript syntax check passed.
- Changed Dart source/tests and staged server source: static analysis clean.
- DigitalOcean release `vivayu-public-web-20261110`: HTTPS page/assets/model
  routes passed, prior/unknown diagnosis responses correct, missing consent
  rejected, private API auth/CORS retained, admin website available.
- Deployment preserved 43 records. Estimate-only live checks left all state
  files unchanged and created zero synthetic survey records.
- Visual browser/mobile verification remains unverified: browser automation
  stopped because it could not determine the current URL safely. Browser-free
  event tests do not substitute for visual layout or real-browser acceptance.
