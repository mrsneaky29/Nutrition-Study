# Agy verification prompt: admin console +6.1

Verify the admin +6.1 update in
`C:\Users\LENOVO\Documents\ChatGPT\Project2\.worktrees\plus5-integration`.
Use at most two agents. Do not change or reinstall the collector phone app.
Do not commit, push, deploy, rotate keys, or clear state. Report findings first.

The live admin console is https://admin.nutrition.achantalabs.com.
New release: 20260926T145831Z-76b4c5ccba4b. Existing Collector 1 key is unchanged,
and live API checks found one retained synthetic record. The installed phone app
is still +6; only its future source display name was changed to +6.1.

Completed: 21 backend/admin regression tests plus 3 QR-console widget tests;
clean Flutter analysis; release admin web build; live safe collector listing,
no-store QR response, unchanged Collector 1 key, and authenticated health checks.

On an ISOLATED temporary backend with synthetic credentials, verify:
- Admin-only collector creation, sequential unique numbers, and persistence
  after refresh and backend restart.
- Active collector cards show Generate sign-in QR and Reset session.
- QR decoded locally matches the existing +6 CollectorQrPayload format and
  authenticates the intended collector. No online QR services.
- Disabled collectors cannot fetch a QR or authenticate, including after restart.
- Reset session invalidates the old token while the existing QR works again.
- Mobile layout, small-screen dialog scrolling, closing the QR dialog, loading
  state, network failure, and generic errors without credential leakage.
- Collector-role API calls cannot access admin collector endpoints.
- Existing visit records and credentials are preserved throughout.

LIVE checks must be read-only: opening existing Collector 1 QR is allowed,
but do not create/disable/reset collectors or open new collector sessions.
Never include QR pixels, keys, or participant details in screenshots/reports.
Creating or disabling a real collector requires separate user direction.

Production gateway now uses LocalApiVisitRepository in admin_main.dart;
demo InMemoryCollectorAccountGateway must not be used for production.
New sensitive state file: .local_data/collector_accounts.json (Linux mode 0600,
parent directory 0700). This belongs in encrypted backups, never in release kits.
Check Git history and Drive kit metadata for the +6.1 publication status;
do not assume publication merely from the presence of local files.
