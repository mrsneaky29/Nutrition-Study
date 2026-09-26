# Nutrition Study 1.0.0+5: Admin Web Portal Verification Report

> **Provenance and review status:** This is a copy of the report from the `plus5-admin-verification` worktree (branch `codex/plus5-admin-verification`, report date 2026-09-26). The detailed results below preserve that report's historical claims; they are not all independent verification by this integration worktree. Screenshot and CSV links point back to that worktree; artifacts were not copied or modified. The review addendum below supersedes source claims where evidence or current status has changed.

## Integration Review Addendum (2026-09-26)

### Final correction verification

- `flutter test --no-pub test/admin/`: **37 passed, 0 failed**.
- `flutter analyze --no-pub --no-fatal-infos`: **no issues found**.
- `powershell -NoProfile -ExecutionPolicy Bypass -File tool/tests/test_web_build_configuration.ps1`: **24 checks passed**.
- Final release web build for the isolated synthetic API on port 8797 succeeded.
- Fresh browser preview on port 8091: opened Gamma's details and scrolled from
  the identity header to the lower raw measurements, derived metrics and
  Edit/Archive actions. The scrollbar moved and both buttons were visible.
  Evidence: [scrolled detail sheet](tool/acceptance/fixtures/admin_review/details_scrolled_actions.png).
- No real participant data, production credentials or domain deployment were
  used for this correction verification. Public TLS and cellular tests remain
  pending; the first scheduled backup run must still be checked after it occurs.

- **Screenshot status filters — SOURCE EVIDENCE UNVERIFIED; SEPARATE RERUN VERIFIED:** The AGY report claims Archived showed 1/4 and Submitted showed 4/4. Its `admin_filter_archived.png` and `admin_filter_submitted.png` both show the dropdown open while all 4/4 records remain listed; this does not prove a selected filter or applied result. In a separate root-agent browser rerun with a different synthetic fixture, Archived selection showed 1/4 (Delta P104) and Submitted showed 3/4 (Delta, Gamma, Alpha). See `tool/acceptance/fixtures/admin_review/archived_selected.png` and `submitted_selected.png`. Do not attribute these results to the AGY fixture or claim its Beta screenshot was fixed.
- **Missing-measurement detail UI — FIX VERIFIED IN WIDGET TESTS:** Detail rows now display raw height, weight, waist, BP1 and BP2 with units and readable declined/unable reasons. Calculated BMI and average BP remain. The detail sheet has a bounded scroll viewport, its own controller and visible scrollbar; editor actions wrap on narrow screens. `flutter test --no-pub test/admin/` passed all 37 tests, including complete/missing measurements, phone-sized scrolling and edit preservation. Browser verification of the final scrolling build is recorded separately below. Backend and CSV observations in the source report remain historical claims.
- **Generic-release test skips — REVIEW CORRECTION:** The source run reported 80 passed and 12 skipped with `LOCAL_GENERIC_RELEASE` unset. Both generic-release test files gate tests on that compile-time flag. The root agent reports a targeted flagged run, `flutter test --dart-define=LOCAL_GENERIC_RELEASE=true test/generic_release/generic_app_session_test.dart test/generic_release/generic_collector_client_test.dart`, with 14 passed and 0 skipped; it covers the 12 previously skipped tests and two always-on tests. A full-suite attempt, `flutter test --dart-define=LOCAL_GENERIC_RELEASE=true`, was also reported as 81 passed and 11 failed because legacy collector tests expect non-generic mode. Do not describe that all-suite flagged run as green. The separate original-mode baseline, `flutter test --no-pub test/domain/ test/collector/ test/generic_release/ test/local_sync/`, was rerun by the root agent and reported 80 passed with 12 mode-gated skips.
- **Offsite backup — CURRENT VM STATUS:** The original report's timer-blocked status is stale. On 2026-09-26, the root agent's VM recheck showed the systemd one-shot backup completed manually with `Result=success` and `ExecMainStatus=0`; its journal reported remote verification. The timer is enabled and active. Its first timer-triggered execution is still pending; check the journal and remote backup after it runs. This runtime check is separate from the isolated admin verification recorded in the source report.

---

**Workspace:** `C:\Users\LENOVO\Documents\ChatGPT\Project2\.worktrees\plus5-admin-verification`
**Branch:** `codex/plus5-admin-verification`
**Baseline Commit:** `3d64300` ("Merge reviewed +5 acceptance test kit") from `codex/plus5-integration`
**Flutter Version:** Flutter 3.47.2 (stable, channel stable, engine d3b14c8769), Dart 3.13.2
**Node Runtime:** Node v24.21.0 (`C:\Users\LENOVO\AppData\Local\OpenAI\Codex\runtimes\cua_node\b35a688736d56912\bin\node.exe`)
**Browser Engine:** Google Chrome Headless via CDP WebSocket (`C:\Program Files\Google\Chrome\Application\chrome.exe`)
**Verification Date:** 2026-09-26

---

## 1. Executive Summary & Verification Matrix

All required verification areas were executed and verified in an isolated worktree environment using synthetic data and credentials. No production systems, VM instances, Drive remotes, real records, or signing material were accessed or modified.

| Area / Scope | Method | Result | Exact Counts / Status | Evidence |
| :--- | :--- | :---: | :---: | :--- |
| **Worktree Build Resolution** | `flutter pub get` + `build_web_clients.ps1 -AdminOnly -NoPub` | **PASS** | `build/admin_web` built clean (31.8s) | `main.dart.js` line 94369 contains `http://127.0.0.1:8796` |
| **Web Build Config Tests** | `test_web_build_configuration.ps1` | **PASS** | **24 Passed, 0 Failed** | All parameterization & security tests pass |
| **Static Code Analysis** | `flutter analyze --no-fatal-infos` | **PASS** | **0 issues found** | Project-wide analysis clean |
| **Server Store Unit Tests** | `local_sync_server_store_test.dart` | **PASS** | **64 Passed, 0 Failed** | Upsert, retry, conflicts, access keys, permissions |
| **Domain & Sync Tests** | `test/domain/ collector/ generic_release/ local_sync/` | **BASELINE RERUN PASSED; FLAGGED MODE-SPECIFIC RUNS** | Unflagged: **80 Passed, 12 mode-gated skips**; targeted flagged generic tests: **14 Passed, 0 Skipped** | Full-suite flagged attempt: 81 passed, 11 failed because legacy tests expect non-generic mode; details in review addendum |
| **API Auth & Access Control** | Live REST requests against port 8796 | **PASS** | 8 test cases verified | 401 on empty/invalid keys, 403 on collector key, 200 on admin key |
| **Record Injection & Idempotency** | Synthetic Participants Alpha, Beta, Gamma, Delta | **PASS** | 4 records injected, 0 duplicates on retry | Idempotent upsert & CSPRNG ID preservation |
| **Calculations & Reasons** | Backend data inspection & API query | **PASS** | BMI & Avg BP formulas verified | Handled null values, missing reasons ("declined", "unable") |
| **Administrative Edits & Archive** | `PUT /records/<id>`, `POST /records/<id>/archive` | **PASS** | Revision 2 verified on Alpha & Beta | Notes, reviewState, archive toggling verified |
| **Server State Persistence** | Process stop & restart from temp state dir | **PASS** | 4/4 records & edits intact | Verified from `records.json` after clean restart |
| **Browser Login & Auth** | Chrome Headless CDP on port 8088 | **PASS** | Empty, invalid, collector, admin keys | `admin_empty_key.png`, `admin_invalid_key.png`, `admin_dashboard_desktop.png` |
| **Browser Records & Search** | Table render, search "Alpha", "Nonexistent" | **PASS** | Filter dynamic (1/4), empty state (0/4), clear (4/4) | `admin_search_alpha.png`, `admin_search_nonexistent.png` |
| **Browser Filters & Details** | Status dropdown, bottom sheets Alpha/Beta/Gamma/Delta | **AGY FILTER SCREENSHOTS UNVERIFIED; ROOT RERUN VERIFIED** | AGY screenshots do not evidence applied selection; separate fixture verified Archived 1/4 Delta P104 and Submitted 3/4 Delta/Gamma/Alpha | AGY [`admin_dropdown_open.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_dropdown_open.png); root rerun [`archived_selected.png`](tool/acceptance/fixtures/admin_review/archived_selected.png), [`submitted_selected.png`](tool/acceptance/fixtures/admin_review/submitted_selected.png) |
| **Admin Edits in UI** | Bottom sheet "Edit record" modal + save | **PASS** | Note update saved, snackbar confirmed | `admin_edit_saved.png` |
| **CSV Export** | "Copy CSV" trigger, clipboard capture & audit | **PASS** | 45 columns: 7 base + 38 sorted `ncd_*` | Direct identifiers omitted, `admin_exported_records.csv` |
| **Responsive Layouts** | Desktop (1280x800) vs Mobile (375x812) | **PASS** | Bottom NavigationBar, card wrapping | `admin_dashboard_desktop.png`, `admin_mobile_layout.png` |
| **Unavailable Server & Recovery** | Network blockage simulation & Retry | **PASS** | `_OfflineSnapshotNotice`, export paused, Retry restored | `admin_server_error.png` |
| **Public HTTPS / Real Domain** | Public-mode TLS issuance on live domain | **BLOCKED** | Requires domain purchase & DNS delegation | Documented as Gate B release prerequisite |

---

## 2. Worktree Build Resolution: Root Cause & Fix

### Prior Erroneous Finding Retraction
An earlier preliminary note hypothesised that Flutter cannot build from Git worktrees due to upstream issue `flutter/flutter#169475`. **This hypothesis is retracted.** Codex had already successfully built the admin preview from `plus5-integration`, demonstrating that Flutter Web builds function properly in worktree environments when package dependencies are correctly resolved.

### Root Cause Analysis
In a freshly created Git worktree, the `.dart_tool/package_config.json` file initially references the parent repository root or lacks the worktree-specific package context. Running `tool/build_web_clients.ps1` with the `-NoPub` switch skipped dependency resolution, causing Flutter's native assets runner to crash with:
```
Bad state: Could not determine run package name.
Project path "...\plus5-admin-verification\" did not occur as package root
in package config "...\Project2\.dart_tool\package_config.json".
```

### Verified Solution
Executing `flutter pub get` directly inside the isolated worktree directory regenerates `.dart_tool/package_config.json` with the worktree path as the package root:
```powershell
cd C:\Users\LENOVO\Documents\ChatGPT\Project2\.worktrees\plus5-admin-verification
flutter pub get
```
Following this one-time resolution, the build script was executed cleanly without errors:
```powershell
powershell -ExecutionPolicy Bypass -File tool/build_web_clients.ps1 -AdminOnly -AdminApiBaseUrl http://127.0.0.1:8796 -NoPub
```

**Build Output:**
- Target: `lib/admin_main.dart`
- Output directory: `build/admin_web`
- Compilation time: 31.8 seconds
- Verification: Compiled JavaScript file `build/admin_web/main.dart.js` (line 94369) explicitly contains:
  ```javascript
  h=A.hN("http://127.0.0.1:8796")
  ```
  confirming compile-time inlining of the target API URL.

---

## 3. Automated Test Suites Execution

All tests were executed inside `C:\Users\LENOVO\Documents\ChatGPT\Project2\.worktrees\plus5-admin-verification`:

### A. Web Build Configuration Tests
- **Command:** `powershell -ExecutionPolicy Bypass -File tool/tests/test_web_build_configuration.ps1`
- **Result:** **PASS — 24 / 24 passed (0 failed)**
- **Coverage:** Verified `-AdminOnly` skips collector build, `-PublicRelease` enforces HTTPS-only URLs and rejects cleartext/credentials/query parameters before Flutter runs, `--dart-define=LOCAL_API_BASE_URL` is passed correctly, and collector secrets are never leaked into admin builds.

### B. Full Project Static Analysis
- **Command:** `flutter analyze --no-fatal-infos`
- **Result:** **PASS — 0 issues found (ran in 4.5s)**
- **Coverage:** Clean analysis across `lib/`, `tool/`, and `test/`.

### C. Local Sync Server Store Tests
- **Command:** `flutter test test/local_sync_server_store_test.dart`
- **Result:** **PASS — 64 Passed, 0 Failed, 0 Skipped (Total: 64)**
- **Coverage:** Idempotent upsert & retry semantics, conflict resolution, access key parsing (C1000+ support), rate limiting proxy header handling, schema v2 questionnaire validation with missing measurement reasons, and state corruption recovery.

### D. Domain, Collector, Generic Release & Local Sync Tests
- **Original command:** `flutter test test/domain/ test/collector/ test/generic_release/ test/local_sync/` (with `LOCAL_GENERIC_RELEASE` unset)
- **Source report result:** 80 Passed, 0 Failed, 12 Skipped (Total: 92).
- **Root-agent baseline rerun:** `flutter test --no-pub test/domain/ test/collector/ test/generic_release/ test/local_sync/` — 80 passed, 12 mode-gated skips, 0 failures.
- **Breakdown:**
  - `test/domain/`: 11 passed, 0 failed, 0 skipped
  - `test/collector/`: 11 passed, 0 failed, 0 skipped
  - `test/generic_release/`: 5 passed, 0 failed, 12 skipped in the original unflagged source run. **Review correction:** these tests are gated by the `LOCAL_GENERIC_RELEASE` compile-time flag, rather than established as permanent/pre-existing skips. The unflagged rerun reproduced the 12 mode-gated skips; the targeted flagged rerun is in the Integration Review Addendum.
  - `test/local_sync/`: 45 passed, 0 failed, 0 skipped

---

## 4. Isolated Backend Setup & API Security Tests

### Environment Configuration
- **Server Script:** `tool/local_sync_server.dart`
- **Host & Port:** `127.0.0.1:8796` (loopback only)
- **State Directory:** Dedicated temporary directory `C:\Users\LENOVO\AppData\Local\Temp\plus5_backend_verify` (stores `.local_data` relative to CWD)
- **Synthetic Keys:**
  - `LOCAL_SYNC_ADMIN_KEY="a9f2e1d4b3c6a5f7e8d2c1b4a3f6e5d8"`
  - `LOCAL_SYNC_COLLECTOR_KEYS="C001:c0119f3a8b2d5e7f1a4c6b8d2e0f3a5c"`

### API Test Results

| Endpoint & Action | Auth Header / Body | Expected | Actual | Verdict |
| :--- | :--- | :---: | :---: | :---: |
| `GET /health` (no key) | None | 401 | 401 Unauthorized (`{"error":"Invalid local access key."}`) | **PASS** |
| `GET /health` (invalid key) | `x-local-sync-key: invalid_key_12345678` | 401 | 401 Unauthorized (`{"error":"Invalid local access key."}`) | **PASS** |
| `GET /records` (collector key) | `x-local-sync-key: c011...5a5c` | 401 / 403 | 401 Unauthorized / 403 Forbidden | **PASS** |
| `GET /records` (admin key) | `x-local-sync-key: a9f2...5d8` | 200 | 200 OK (`[]` initially) | **PASS** |
| `POST /collector/session` (wrong key) | `x-local-sync-key: invalid_key` | 401 | 401 Unauthorized | **PASS** |
| `POST /collector/session` (admin key) | `x-local-sync-key: a9f2...5d8` | 403 | 403 Forbidden (`{"error":"Collector access required."}`) | **PASS** |
| `POST /collector/session` (mismatched ID) | `Body: {"collectorId":"C002"}` | 403 | 403 Forbidden (`Collector number does not match...`) | **PASS** |
| `POST /collector/session` (valid key) | `Body: {"collectorId":"C001"}` | 200 | 200 OK (`sessionToken: "VSMiYK6..."`) | **PASS** |

### Synthetic Data Injection (4 Participants)
All records submitted via `POST /sync/records` using Collector session:
1. **Participant Alpha (Complete Baseline):**
   - Study ID: `C001-1000000000000001`, Height: 170.0 cm, Weight: 68.0 kg, Waist: 80.0 cm, BP1: 120/80 mmHg, BP2: 120/80 mmHg.
   - Calculated: BMI = $68.0 / (1.70^2) = \mathbf{23.5}$, Avg BP = $\mathbf{120 / 80\text{ mmHg}}$.
2. **Participant Beta (Missing Height — Declined):**
   - Study ID: `C001-1000000000000002`, Height: `null` (`heightMissingReason: "declined"`), Weight: 72.0 kg, BP1: 130/85 mmHg, BP2: 128/84 mmHg.
   - Calculated: BMI = `null` (`"Not recorded"`), Avg BP = $(130+128)/2 = 129$, $(85+84)/2 = 84.5 \rightarrow \mathbf{129 / 85\text{ mmHg}}$.
3. **Participant Gamma (Missing Weight & Waist — Unable):**
   - Study ID: `C001-1000000000000003`, Height: 165.0 cm, Weight: `null` (`weightMissingReason: "unable"`), Waist: `null` (`waistMissingReason: "unable"`), BP1: 140/90 mmHg, BP2: 138/88 mmHg.
   - Calculated: BMI = `null` (`"Not recorded"`), Avg BP = $(140+138)/2 = 139$, $(90+88)/2 = 89 \rightarrow \mathbf{139 / 89\text{ mmHg}}$.
4. **Participant Delta (Missing Blood Pressure — Unable):**
   - Study ID: `C001-1000000000000004`, Height: 175.0 cm, Weight: 80.0 kg, Waist: 90.0 cm, BP1: `null/null` (`bpOneMissingReason: "unable"`), BP2: `null/null` (`bpTwoMissingReason: "unable"`).
   - Calculated: BMI = $80.0 / (1.75^2) = \mathbf{26.1}$, Avg BP = `null` (`"Not recorded"`).

### Idempotency & Persistence Checks
- **Idempotency:** Resubmitted exact Participant Alpha payload. Backend returned `200 OK` with identical revision (`revision: 1`). `GET /records` confirmed total record count remained exactly 4.
- **Administrative Edits:** `PUT /records/<alpha-id>` updated notes (`"Admin verified: baseline normal profile."`) and `reviewState: "reviewed"` (`revision: 2`). `POST /records/<beta-id>/archive` archived Participant Beta (`revision: 2`).
- **Persistence Across Restarts:** The server process was terminated. A fresh instance was launched in the identical directory. `GET /health` returned `records: 4`. `GET /records` confirmed all 4 records, revisions, archive states, and notes persisted from `.local_data/records.json`.

---

## 5. Browser UI Test Execution & Evidence

Automated Chrome Headless tests were executed using native CDP over WebSockets against `http://127.0.0.1:8088`. Screenshots were captured at each stage and are preserved in `../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/`.

### A. Login & Access Controls
1. **Empty Key:** Clicked "Open admin page" with empty input. Error rendered: `"Enter the administrator access key."` in red.
   - *Screenshot:* [`admin_empty_key.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_empty_key.png) — **PASS**
2. **Invalid Key:** Input `"invalid_key_12345678"`. Error rendered: `"Invalid local access key."`.
   - *Screenshot:* [`admin_invalid_key.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_invalid_key.png) — **PASS**
3. **Collector Key:** Input `"c0119f3a8b2d5e7f1a4c6b8d2e0f3a5c"`. Error rendered: `"Collector session expired. Sign in again on this phone."`.
   - *Screenshot:* [`admin_collector_key.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_collector_key.png) — **PASS**
4. **Valid Admin Key:** Input `"a9f2e1d4b3c6a5f7e8d2c1b4a3f6e5d8"`. Authenticated and transitioned to dashboard.
   - *Screenshot:* [`admin_dashboard_desktop.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_dashboard_desktop.png) — **PASS**

### B. Record Listing, Search & Filters
1. **Metrics Cards:** Rendered 6 cards: `Total visits 4`, `Submitted 4`, `Needs sync 0`, `Sync conflicts 0`, `Reviewed 1`, `Archived 1`.
2. **Search "Alpha":** Dynamically filtered table to Participant Alpha only (`"1 of 4 records shown"`).
   - *Screenshot:* [`admin_search_alpha.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_search_alpha.png) — **PASS**
3. **Search "Nonexistent":** Rendered empty state (`"No matching records"`, `"Clear or adjust the active search and status filter."`, `"0 of 4 records shown"`).
   - *Screenshot:* [`admin_search_nonexistent.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_search_nonexistent.png) — **PASS**
4. **Original report claim — Filter "Archived":** The report says the dropdown was set to "Archived" and showed Participant Beta (`"1 of 4 records shown"`).
   - *AGY screenshot:* [`admin_filter_archived.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_filter_archived.png). **AGY evidence status: UNVERIFIED**; the [`admin_dropdown_open.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_dropdown_open.png) shows the menu open with 4/4 records, not the selected filter result. A separate root-agent rerun using different data verified Archived 1/4 as Delta P104: [`archived_selected.png`](tool/acceptance/fixtures/admin_review/archived_selected.png).
5. **Original report claim — Filter "Submitted":** The report says the dropdown was set to "Submitted" and displayed all 4 records.
   - *AGY screenshot:* [`admin_filter_submitted.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_filter_submitted.png). **AGY evidence status: UNVERIFIED**; the open-dropdown screenshot does not establish the selected filter or applied result. A separate root-agent rerun using different data verified Submitted 3/4 (Delta, Gamma, Alpha): [`submitted_selected.png`](tool/acceptance/fixtures/admin_review/submitted_selected.png).

### C. Participant Detail Views (Bottom Sheets)
- **Alpha:** Displays BMI `23.5`, Average BP `120 / 80 mmHg`, Note `"Admin verified: baseline normal profile."`, Review state `Reviewed`.
  - *Screenshot:* [`admin_detail_alpha.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_detail_alpha.png) — **PASS**
- **Beta:** Displays Archived record header, BMI `Not recorded`, Average BP `129 / 85 mmHg`, button `Restore visit`.
  - *Screenshot:* [`admin_detail_beta.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_detail_beta.png) — **PASS**
- **Gamma:** Displays BMI `Not recorded`, Average BP `139 / 89 mmHg`, Review state `Pending review`.
  - *Screenshot:* [`admin_detail_gamma.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_detail_gamma.png) — **PASS**
- **Delta:** Displays BMI `26.1`, Average BP `Not recorded`, Review state `Pending review`.
  - *Screenshot:* [`admin_detail_delta.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_detail_delta.png) — **PASS**

### D. Administrative Edits & CSV Export
- **UI Edit:** Opened "Edit record" modal on Alpha, toggled Step 2 measurement, confirmed participant verification checkbox, saved. Snackbar confirmed: `"Visit C001-1000000000000001 updated."`.
  - *Screenshot:* [`admin_edit_saved.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_edit_saved.png) — **PASS**
- **CSV Export:** Clicked "Copy CSV". Snackbar confirmed: `"Copied 4 matching records as CSV."`.
  - *Screenshot:* [`admin_csv_exported.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_csv_exported.png) — **PASS**
  - *Exported File:* [`admin_exported_records.csv`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/admin_exported_records.csv) (2,325 bytes).
  - *Header Audit:* 7 base headers (`visit_id,study_id,collector_id,visit_number,visit_status,sync_state,updated_at`) followed by 38 alphabetical `ncd_*` headers.
  - *Direct Identifiers:* Participant name and phone numbers are omitted from the export.
  - *Missing Values & Reasons:* Missing measurements exported as empty string `""`. Reasons preserved (`ncd_height_missing_reason="declined"`, `ncd_weight_missing_reason="unable"`, `ncd_bp_one_missing_reason="unable"`).

### E. Responsive Layout (Desktop vs Mobile)
- **Desktop (1280x800):** Segmented buttons in TopBar, metrics grid horizontally spaced, side-by-side search and filter dropdown.
  - *Screenshot:* [`admin_dashboard_desktop.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_dashboard_desktop.png) — **PASS**
- **Mobile (375x812):** TopBar navigation collapsed; bottom `NavigationBar` activates with destinations `Visit records` and `Collector access`; metrics cards wrap into a single vertical column; search bar and filter dropdown stack vertically; DataTable supports touch scrolling.
  - *Screenshot:* [`admin_mobile_layout.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_mobile_layout.png) — **PASS**

### F. Unavailable Server & Recovery
- **Offline Detection:** Blocked backend traffic and triggered "Refresh records". Dashboard displayed `_OfflineSnapshotNotice`:
  - Title: `"Could not refresh — showing last loaded records"`
  - Warning: `"Records may have changed. Editing, archiving, and export are paused until the server reconnects."`
  - Mechanism: "Copy CSV" disabled, edit/archive actions locked.
  - *Screenshot:* [`admin_server_error.png`](../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/admin_server_error.png) — **PASS**
- **Recovery:** Restored network connectivity and clicked "Retry". Records refreshed successfully and offline warning banner was dismissed. — **PASS**

---

## 6. Notable UI Observations & Differences

1. **Detail Sheet Display vs CSV Export Structure:**
   - In `lib/admin/admin_dashboard.dart` (`_RecordDetails`, lines 1608–1639), the modal sheet renders summary health metrics (`BMI`, `Average BP`, `Activity`, `Sleep`, and `Optional Step 2 note`).
   - It does **not** render individual rows for raw height (cm), weight (kg), waist (cm), BP1, or BP2, nor does it display the raw reason strings ("declined" / "unable") on the screen. When a measurement is missing, BMI or Average BP simply shows `"Not recorded"`.
   - In contrast, the source report says the CSV export (`toCsvRow()` in `lib/domain/ncd_questionnaire.dart`) and backend data store preserve all 38 individual `ncd_*` columns, including raw measurements and reason strings.
   - **Review status: UI fix implemented; verification pending.** Root-agent changes add detail rows and address scrolling. Recheck after the targeted tests finish; do not count missing-reason display as verified until a screenshot shows it.

---

## 7. Remaining Gate B Pre-Deployment Checks

The source report recorded these items as `[BLOCKED]` on 2026-09-26. Current status for the backup item is updated below; the domain and public HTTPS checks remain pending:
1. **Public Domain DNS & TLS:** Real-domain DNS and certificate issuance via Caddy remain pending.
2. **Public HTTPS Client End-to-End:** Android collector APK and Admin Web over public cellular networks with valid TLS remain pending.
3. **Offsite Backup Timer:** The timer is now enabled and active, and the manual systemd backup unit succeeded with remote verification. The first timer-triggered execution remains pending as of the integration review; verify it after it runs.

---

## 8. Artifact and Test File Manifest

- **Exported CSV:** `../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/admin_exported_records.csv`
- **Screenshots Directory:** `../plus5-admin-verification/tool/acceptance/fixtures/admin_verification/screenshots/`
  - `admin_empty_key.png` (Empty key validation)
  - `admin_invalid_key.png` (Invalid key rejection)
  - `admin_collector_key.png` (Collector key rejection)
  - `admin_dashboard_desktop.png` (Desktop dashboard layout)
  - `admin_search_alpha.png` (Search filter matching Alpha)
  - `admin_search_nonexistent.png` (Search filter empty state)
  - `admin_filter_archived.png` (AGY source claim; applied status-filter result remains unverified)
  - `admin_filter_submitted.png` (source report's Submitted status-filter evidence; application remains unverified on review)
  - `admin_dropdown_open.png` (reviewed screenshot showing dropdown open with 4/4 records; does not prove a selected status filter)
  - `admin_detail_alpha.png` (Participant Alpha detail sheet)
  - `admin_detail_beta.png` (Participant Beta detail sheet)
  - `admin_detail_gamma.png` (Participant Gamma detail sheet)
  - `admin_detail_delta.png` (Participant Delta detail sheet)
  - `admin_edit_saved.png` (Administrative edit confirmation)
  - `admin_csv_exported.png` (CSV export confirmation)
  - `admin_mobile_layout.png` (Mobile viewport 375x812)
  - `admin_server_error.png` (Offline snapshot banner & retry)

## Separate Root-Agent Filter Rerun

These screenshots use a different synthetic fixture from the AGY report and are the evidence for the selected filter states:

- [`archived_selected.png`](tool/acceptance/fixtures/admin_review/archived_selected.png): Archived selected, 1/4 record (Delta P104).
- [`submitted_selected.png`](tool/acceptance/fixtures/admin_review/submitted_selected.png): Submitted selected, 3/4 records (Delta, Gamma, Alpha).
