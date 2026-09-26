# Acceptance Test Results Record (Nutrition Study 1.0.0+5)

**Document Identifier:** `ATR-1.0.0+5-YYYYMMDD`  
**Evaluation Scope:** Complete Client, Multi-Device Handover, Server, and Administrative Web Gating  
**Standard Status Legend:**
- `[AUTOMATED PASS]` – Verified via automated unit/integration/smoke test runner in worktree (244 regression, 64 store, 80 domain/sync, 24 web packaging, flutter analyze).
- `[CODEX REPORTED PASS]` – Verified on Ubuntu VPS by Codex (systemd sandbox, firewall rules, encrypted Drive roundtrip).
- `[MANUAL PASS]` – Verified via manual operator execution following protocol checklist.
- `[NOT TESTED]` – Step awaiting manual execution or deferred to subsequent release gate.
- `[BLOCKED]` – Test execution halted or blocked by missing prerequisites (e.g. domain/DNS, TLS certificates, or public mode origin security guards).

---

## 1. Test Execution Environment Details

| Attribute | Recorded Value | Auditor Notes |
| :--- | :--- | :--- |
| **Git Baseline Commit** | `8f170a74e8e08d11c819958b94f467f3448d56e8` | Branch `codex/plus5-acceptance-kit` |
| **Android APK Version** | `1.0.0+5` | `study-collector-1.0.0+5.apk` |
| **Android APK SHA256** | `1859d3afa4cef1da09987b443b9c107f20de7560cb0adc0ac05538c7f46c2982` | Verified signed generic release |
| **Test Device 1 (Phone 1)** | *e.g., Samsung Galaxy A14 (SM-A145F)* | Android OS Version: *13 (API 33)* |
| **Test Device 2 (Phone 2)** | *e.g., Xiaomi Redmi Note 11* | Android OS Version: *12 (API 31)* |
| **Admin Workstation** | *e.g., Windows 11 Pro 23H2 / Chrome 124* | Workstation IP / Origin |
| **Server Host & OS** | *e.g., Ubuntu 24.04.4 LTS (Host VPS)* | Kernel / Dart 3.x standalone runtime |
| **API Endpoint URL** | *e.g., https://api.nutritionstudy.org (or Option A local harness at http://127.0.0.1:8787)* | Strictly HTTPS in public mode; Option A local private harness permits cleartext HTTP for UI testing. Raw SSH tunnel to public VPS is [BLOCKED] by public mode security guards. |
| **Test Execution Date** | *YYYY-MM-DD* | Local Time: |
| **Lead Acceptance Auditor**| | Role: Acceptance Kit Author / QA Lead |

---

## 2. Protocol Execution Results

### 2.1 Android Client Checklist (01_ANDROID_ACCEPTANCE_CHECKLIST.md)

| Test ID | Procedure Description | Expected Outcome | Status | Evidence Reference |
| :--- | :--- | :--- | :---: | :--- |
| **AND-01** | Cold start & Public HTTPS form presentation | Field labeled "Server address", hint `https://...` | `[           ]` | SCR-01 |
| **AND-02** | HTTP cleartext rejection | Insecure scheme `http://` blocked with error message | `[           ]` | SCR-02 |
| **AND-03** | Malformed URL & query rejection | Query strings, paths, and fragments rejected | `[           ]` | SCR-03 |
| **AND-04** | Valid HTTPS address entry | Clean acceptance without validation error | `[           ]` | SCR-04 |
| **AND-05** | Collector login with positive integer (e.g. `1` -> `C001`) | Maps to `C001`, accepts 32-char hex key, starts session | `[           ]` | LOG-01 |
| **AND-06** | Invalid / non-positive collector ID rejection | Values <= 0 or non-numeric rejected with prompt | `[           ]` | SCR-05 |
| **AND-07** | Short access key (<16 chars) rejection | Blocks submission with error | `[           ]` | SCR-06 |
| **AND-08** | Offline Airplane Mode data collection | App creates draft and records Step 1 without network | `[           ]` | SCR-07 |
| **AND-09** | 16-digit CSPRNG Study ID generation | Study ID matches `C01-<16 digits>` format | `[           ]` | LOG-02 |
| **AND-10** | Normal Physical Measurements (Participant Alpha) | Accepts Height, Weight, Waist, BP1, BP2 | `[           ]` | SCR-08 |
| **AND-11** | BMI calculation formula verification | $68.0 / (1.70)^2 \approx 23.5$ (rounded to 1 decimal) | `[           ]` | SCR-09 |
| **AND-12** | Average BP calculation verification | $(120+120)/2 / (80+80)/2 = 120/80\text{ mmHg}$ | `[           ]` | SCR-10 |
| **AND-13** | Missing Height (`declined`) handling | Numeric field hidden; BMI shows `Not calculated` | `[           ]` | SCR-11 |
| **AND-14** | Missing Weight (`unable`) handling | Numeric field hidden; BMI shows `Not calculated` | `[           ]` | SCR-12 |
| **AND-15** | Missing Blood Pressure (`unable`) handling | Numeric fields hidden; Avg BP shows `Not calculated` | `[           ]` | SCR-13 |
| **AND-16** | Submission receipt rendering | Shows UUID, Study ID, calculated metrics, Pending chip | `[           ]` | SCR-14 |
| **AND-17** | Process kill / RAM eviction persistence | Pending records persist across force-close & reboot | `[           ]` | SCR-15 |
| **AND-18** | Network reconnect & sync upload | Pending record uploads, transitions to Synced (green) | `[           ]` | LOG-03 |
| **AND-19** | Idempotency & duplicate submission check | Retrying sync returns 200 OK without creating duplicate | `[           ]` | LOG-04 |

---

### 2.2 Two-Phone Handover Test (02_TWO_PHONE_COLLECTOR_HANDOVER_TEST.md)

| Test ID | Procedure Description | Expected Outcome | Status | Evidence Reference |
| :--- | :--- | :--- | :---: | :--- |
| **HND-01** | Phone 1 logs in as Collector `C01` | Session token `Token_Alpha` established | `[           ]` | LOG-05 |
| **HND-02** | Phone 1 collects 2 visits offline | Records saved locally with `syncState = pending` | `[           ]` | SCR-16, SCR-17 |
| **HND-03** | Phone 2 logs in as Collector `C01` | Server issues `Token_Beta`, invalidating `Token_Alpha` | `[           ]` | LOG-06 |
| **HND-04** | Phone 1 reconnects and attempts sync | Server returns HTTP 401 `collector_session_expired` | `[           ]` | LOG-07 |
| **HND-05** | Phone 1 UI session takeover alert | SnackBar: "signed in on another phone" | `[           ]` | SCR-18 |
| **HND-06** | Phone 1 local database preservation | 2 offline records remain safe; zero deletion | `[           ]` | SCR-19 |
| **HND-07** | Phone 1 re-authentication / reclaim | Signs in again; receives fresh `Token_Gamma` | `[           ]` | LOG-08 |
| **HND-08** | Preserved records uploaded successfully | Both offline visits uploaded; state becomes `synced` | `[           ]` | LOG-09 |
| **HND-09** | 16-digit CSPRNG Study ID collision check | No duplicate IDs in sampled phone records; server duplicate/conflict handling verified separately | `[           ]` | LOG-10 |

---

### 2.3 Admin Web Portal Checklist (03_ADMIN_ACCEPTANCE_CHECKLIST.md)

*(Testing Strategy Note: Functional UI verification of ADM-01 through ADM-14 can proceed locally under Option A [Isolated Local Test Harness, LOCAL_SYNC_PUBLIC_MODE=false]. Against the production VPS [Option B], direct testing over an HTTP SSH tunnel is marked `[BLOCKED]` because public mode rejects plain HTTP with 403 Forbidden and enforces exact HTTPS origin matching.)*

| Test ID | Procedure Description | Expected Outcome | Status | Evidence Reference |
| :--- | :--- | :--- | :---: | :--- |
| **ADM-01** | Admin Portal authentication | 32-character admin key grants dashboard access | `[           ]` | SCR-20 |
| **ADM-02** | Invalid admin key rejection | Rejects with HTTP 403 Forbidden | `[           ]` | SCR-21 |
| **ADM-03** | Exact CORS origin enforcement | Rejects unauthorized origins; allows exact admin origin | `[           ]` | LOG-11 |
| **ADM-04** | Record table listing & metrics | All active and draft visits displayed with counts | `[           ]` | SCR-22 |
| **ADM-05** | Status filtering (All, Submitted, Pending, Archived)| Correct dynamic filtering in dashboard | `[           ]` | SCR-23 |
| **ADM-06** | Search by participant name / Study ID | Instant substring filtering across record table | `[           ]` | SCR-24 |
| **ADM-07** | Record Detail drawer - Normal measurements | Shows Participant Alpha: BMI 23.5, Avg BP 120/80 | `[           ]` | SCR-25 |
| **ADM-08** | Record Detail drawer - Missing measurements | Shows `Not recorded` for missing BMI and missing BP | `[           ]` | SCR-26 |
| **ADM-09** | CSV Export - Base headers verification | Base 7 headers match `visit_id,study_id...` | `[           ]` | CSV-01 |
| **ADM-10** | CSV Export - Sorted `ncd_*` questionnaire headers | Alphabetically sorted 38 questionnaire columns | `[           ]` | CSV-01 |
| **ADM-11** | CSV Export - Missing measurement handling | Empty string `""` for value; reason string populated | `[           ]` | CSV-01 |
| **ADM-12** | Admin record editing & note update | Edit note saved with confirmation; revision incremented | `[           ]` | SCR-27 |
| **ADM-13** | Questionnaire preservation after edit | Hard browser refresh confirms questionnaire intact | `[           ]` | SCR-28 |
| **ADM-14** | Reversible archive toggle | Visit archived without permanent deletion | `[           ]` | SCR-29 |

---

### 2.4 Infrastructure, Sandbox & Backup Verification (06_RELEASE_GATE_CHECKLIST.md)

| Test ID | Procedure Description | Expected Outcome | Status | Evidence Reference |
| :--- | :--- | :--- | :---: | :--- |
| **INF-01** | Full regression & store test suite | `flutter test` passes 244 tests (64 store, 80 domain/sync) | `[AUTOMATED PASS]` | LOG-AUT-01 |
| **INF-02** | Static analysis & linting | `flutter analyze` passes with 0 errors, 0 warnings | `[AUTOMATED PASS]` | LOG-AUT-02 |
| **INF-03** | Web packaging configuration | `test_web_build_configuration.ps1` passes 24 tests | `[AUTOMATED PASS]` | LOG-AUT-03 |
| **INF-04** | Signed Android release APK integrity | SHA256 matches `1859d3afa4cef1da09987b443b9c107f20de7560cb0adc0ac05538c7f46c2982` | `[AUTOMATED PASS]` | LOG-AUT-04 |
| **INF-05** | Isolated state restore drill | `tool/vps/test-restore.sh` passes 35 assertions in clean sandbox | `[CODEX REPORTED PASS]` | LOG-CDX-01 |
| **INF-06** | Encrypted offsite Drive backup roundtrip | `tool/vps/test-offsite-backup.sh` and `tool/vps/test-encrypted-roundtrip.sh` verify Google Drive OAuth, `study-crypt:`, encrypted upload, download, checksum, and isolated restore | `[CODEX REPORTED PASS]` | LOG-CDX-02 |
| **INF-07** | VPS host firewall & systemd sandbox | UFW incoming DENY, 22/80/443 inbound, 8787 internal only; systemd sandbox verified on Ubuntu VPS | `[CODEX REPORTED PASS]` | LOG-CDX-03 |
| **INF-08** | Admin Web over SSH tunnel on public VPS | Direct port-forwarded HTTP fails public mode `X-Forwarded-Proto` and exact HTTPS origin matching | `[BLOCKED]` | SEC-01 |

---

## 3. Evidence Artifact Log

| Reference ID | Artifact Type | Filename / URI / Checksum | Description / Content |
| :--- | :--- | :--- | :--- |
| `SCR-01` | Screenshot | `evidence/scr_01_public_launch.png` | Android App Launch with "Server address" |
| `SCR-09` | Screenshot | `evidence/scr_09_alpha_bmi.png` | App Review Screen displaying BMI 23.5 |
| `SCR-18` | Screenshot | `evidence/scr_18_session_expired.png`| "Signed in on another phone" SnackBar |
| `SCR-25` | Screenshot | `evidence/scr_25_admin_alpha_detail.png`| Admin drawer showing BMI 23.5, BP 120/80 |
| `LOG-04` | Terminal Log | `evidence/log_04_idempotency.txt` | HTTP 200 OK on duplicate sync retry |
| `LOG-07` | Server Log | `evidence/log_07_collector_expired.txt`| HTTP 401 `collector_session_expired` |
| `LOG-AUT-01` | Test Runner Log | `evidence/log_aut_01_flutter_test.txt` | Worktree test runner: 244 passed, 12 skipped |
| `LOG-CDX-01` | VPS Test Log | `evidence/log_cdx_01_test_restore.txt` | Codex VPS restore test: 35 assertions passed |
| `LOG-CDX-02` | VPS Test Log | `evidence/log_cdx_02_encrypted_roundtrip.txt` | Codex VPS Drive roundtrip: encrypted upload/restore |
| `CSV-01` | Export File | `evidence/exported_records.csv` | Full CSV export showing base & `ncd_*` headers |

---

## 4. Overall Release Gating Summary & Sign-Off

### Gate Evaluation
- **Worktree Automated Suite:** `[AUTOMATED PASS]` (244 regression, 64 store, 80 domain/sync, 24 web packaging, flutter analyze)
- **Ubuntu VPS Hardening & Backup Roundtrip:** `[CODEX REPORTED PASS]` (restore drill, encrypted Drive roundtrip, host firewall, systemd sandbox; timer disabled)
- **Manual Mobile & Admin Field Protocols:** `[NOT TESTED]` (Android checklist, two-phone handover, Option A admin UI testing awaiting manual execution)
- **Public VPS Admin Tunnel & Gate B Live Deployment:** `[BLOCKED]` (blocked pending domain, DNS, and TLS certificates)

*Note: Gate A as a whole is NOT 100% verified while manual browser/device checks remain unexecuted.*

### Pre-Deployment Gating Status
```text
[ ] APPROVED FOR LIVE FIELD DEPLOYMENT (Requires Gate A manual pass AND Gate B 100% pass)
[X] PRE-DEPLOYMENT GATING IN PROGRESS (Automated & VPS drills passed; awaiting manual field testing & Gate B domain)
[ ] REJECTED (Defects noted; requires remediation and re-testing)
```

| Name | Role | Date | Signature |
| :--- | :--- | :--- | :--- |
| | Android Test Lead | | |
| | Systems Architecture Lead | | |
| | Principal Investigator | | |
