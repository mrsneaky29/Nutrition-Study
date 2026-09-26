# Admin Web Portal Acceptance Checklist (Nutrition Study 1.0.0+5)

**Target Artifact:** Separate Admin Web Application (`build/admin_web/` / `nutrition-study-admin-web-*.zip`)
**Backend Service:** `tool/local_sync_server.dart` (Public Mode / HTTPS Reverse Proxy)  
**Execution Environment:** Chromium / Firefox Browser on Secure Administrator Workstation  
**Auditor:** Data Management Lead / Compliance Officer  

---

## 1. Overview & System Expectations

The Administrator Web Portal provides centralized oversight for data collection, monitoring, conflict resolution, correction of administrative metadata, and research data export. The portal is decoupled from the Android collector app and operates with strict access controls:

1. **Security Isolation:** The admin bundle does **not** embed administrator credentials or collector keys.
2. **Exact Origin CORS & HTTPS Enforcement:** In public mode (`LOCAL_SYNC_PUBLIC_MODE=true`), the backend strictly enforces `LOCAL_SYNC_ALLOWED_ORIGINS` and requires `X-Forwarded-Proto: https`. Plain HTTP requests are rejected with `HTTP 403 Forbidden`. Wildcards (`*`) and cleartext HTTP origins are rejected at startup. The admin web client compiled in public mode strictly expects HTTPS.
3. **Data Immutability & Audit Trails:** Administrative updates never destroy original raw questionnaire observations or participant answers.

> [!WARNING]
> **Production Security Invariant:**  
> **NEVER weaken production security for testing!** Do NOT add plain HTTP origins to `LOCAL_SYNC_ALLOWED_ORIGINS` on the production server, and NEVER disable `LOCAL_SYNC_PUBLIC_MODE` on the production VPS. A raw HTTP port-forwarding tunnel (`ssh -L 8787:127.0.0.1:8787`) alone **CANNOT** satisfy public-mode backend guards:
> - Public mode requires `X-Forwarded-Proto: https` (plain HTTP requests directly into port 8787 receive `403 Forbidden`).
> - Public mode requires browser `Origin` to exactly match `LOCAL_SYNC_ALLOWED_ORIGINS` (a browser opening `http://127.0.0.1:8086` sends an HTTP origin that fails exact HTTPS origin matching).
> - The admin web client compiled in public mode strictly expects HTTPS.

---

## 2. Pre-Test Environmental Requirements & Valid Test Arrangements

Acceptance testing of the Admin Web Portal MUST follow one of two valid test arrangements:

### Option A: Isolated Local Test Harness (Recommended for Functional UI Testing)
Used for functional acceptance testing of dashboard filtering, metrics calculation, and CSV export without requiring a live domain:
- **Backend API Server:** Open a dedicated PowerShell window at the repository root (the directory containing `tool/` and `pubspec.yaml`). Run an isolated local instance in non-public/private mode where cleartext HTTP and CORS `*` are permitted:
  ```powershell
  $acceptanceProject = (Get-Location).Path
  $acceptanceState = Join-Path $env:TEMP ("nutrition-admin-test-" + [guid]::NewGuid())
  New-Item -ItemType Directory -Path $acceptanceState | Out-Null
  $env:LOCAL_SYNC_PUBLIC_MODE = "false"
  $env:LOCAL_SYNC_ALLOWED_ORIGINS = "*"
  $env:LOCAL_SYNC_ADMIN_KEY = "synthetic-admin-key-for-local-tests-only"
  $env:LOCAL_SYNC_COLLECTOR_KEYS = "C001:synthetic-collector-key-for-local-tests-only"
  Push-Location $acceptanceState
  try { dart "$acceptanceProject/tool/local_sync_server.dart" --host=127.0.0.1 --port=8787 }
  finally { Pop-Location }
  ```
- The backend stores `.local_data` under its working directory; the fresh temporary directory isolates these synthetic records. Run this in a dedicated PowerShell window, not a production server shell. Close the window afterward to discard its test-only environment variables.
- **Admin Web Server:** In a second PowerShell window at the project root, build a separate private-mode admin bundle (do not use the public-release bundle), then serve it:
  ```powershell
  ./tool/build_web_clients.ps1 -AdminOnly -AdminApiBaseUrl http://127.0.0.1:8787 -NoPub
  node tool/static_site_server.js --port=8086 --root=build/admin_web --host=127.0.0.1
  ```
- **Browser Access:** Navigate to `http://127.0.0.1:8086`. Functional UI tests (Sections 2–5) can proceed locally in this isolated sandbox.

### Option B: VPS Public Environment (Awaits Gate B Domain, DNS & TLS)
Against the production VPS:
- The VPS backend runs with `LOCAL_SYNC_PUBLIC_MODE=true` and `LOCAL_SYNC_ALLOWED_ORIGINS=https://admin.YOUR-DOMAIN`.
- Port 8787 is strictly internal (loopback only) and Caddy is stopped pending domain acquisition.
- Because a raw HTTP SSH tunnel cannot satisfy `X-Forwarded-Proto: https` or exact HTTPS origin matching without compromising production settings, direct admin portal testing through an SSH tunnel against the public VPS environment is marked **`[BLOCKED]`** until Gate B (domain, DNS, and TLS certificates) is deployed.

### Test Dataset
At least four synthetic records loaded on the server (see `04_SYNTHETIC_TEST_FIXTURES.md`):
- `Fictional Participant Alpha` (Complete measurements: BMI 23.5, Avg BP 120/80)
- `Fictional Participant Beta` (Height missing: reason `declined`)
- `Fictional Participant Gamma` (Weight missing: reason `unable`)
- `Fictional Participant Delta` (BP missing: readings 1 & 2 `unable`)

---

## 3. Step-by-Step Acceptance Checklist

### Section 1: Authorized Access & Exact CORS Enforcement

*(Note: Sections 2–5 can be validated functionally under Option A. CORS origin enforcement steps 1.4–1.5 validate public-mode origin guards.)*

| Step # | Test Action | Expected Result | Pass/Fail Criteria |
| :--- | :--- | :--- | :--- |
| **1.1** | Navigate to the Admin Web Portal in a browser. | Admin sign-in screen loads, prompting for **Administrator access key**. | Clean login form displayed without error. |
| **1.2** | Enter an invalid or short access key (`wrongkey123`) and submit. | Client sends request to backend; server returns **`HTTP 401 Unauthorized`** with body `{"error": "Invalid local access key."}` (or **`HTTP 403 Forbidden`** with `{"error": "Administrator access required."}` if a collector key is supplied). UI displays error alert. | Inauthentic key rejected. |
| **1.3** | Enter the provisioned 32-character hexadecimal **Administrator access key** and submit. | Server validates key against `LOCAL_SYNC_ADMIN_KEY` and returns `200 OK` for initial record query. Dashboard loads. | Administrator authenticated; dashboard view rendered. |
| **1.4** | **CORS Origin Validation (Unauthorized Origin):**<br>Using `curl` or browser developer console from an unlisted origin (e.g. `Origin: https://evil.attacker.com`):<br>`curl -H "Origin: https://evil.attacker.com" -H "X-Local-Sync-Key: <admin-key>" https://<api-domain>/records` | Server response does **NOT** include `Access-Control-Allow-Origin: https://evil.attacker.com`. Browser blocks cross-origin reading. | Unauthorized origin denied by CORS. |
| **1.5** | **CORS Origin Validation (Authorized Origin):**<br>From the configured admin origin:<br>`curl -i -H "Origin: https://admin.nutritionstudy.org" -H "X-Local-Sync-Key: <admin-key>" https://<api-domain>/records` | Server response includes exact headers:<br>`Access-Control-Allow-Origin: https://admin.nutritionstudy.org`<br>`Vary: Origin` | Authorized origin header returned cleanly. |

---

### Section 2: Record Listing, Filtering & Full-Text Search

| Step # | Test Action | Expected Result | Pass/Fail Criteria |
| :--- | :--- | :--- | :--- |
| **2.1** | Verify initial dashboard table loading. | Data table renders displaying columns: **Participant** (shows name & Study ID), **Phone**, **Visit**, **Collector**, **Status**, **Review**, **Last updated**. Summary shows: `4 of 4 records shown` (or total count). | All preloaded records visible in active view. |
| **2.2** | Test Status Filter dropdown:<br>- Select **Submitted**<br>- Select **Needs sync** / **Sync conflicts** / **Pending review**<br>- Select **Archived**<br>- Select **All records** | Data table filters dynamically in memory without re-fetching:<br>- *Submitted:* Shows only records with status `submitted`.<br>- *Needs sync / Sync conflicts / Pending review:* Shows un-synced or conflicted uploads.<br>- *Archived:* Shows archived visits.<br>- *All records:* Shows complete operational queue. | Filtering functions correctly across all status states. |
| **2.3** | Test Search by **Participant Name**: Type `Alpha` in search box. | Data table filters instantly to display only `Fictional Participant Alpha`. Counter displays `1 of 4 records shown`. | Search filters by participant name substring. |
| **2.4** | Test Search by **Study ID**: Clear and type the 16-digit Study ID for Participant Beta (e.g. `C01-`). | Data table displays matching participant record. | Search filters accurately by Study ID. |
| **2.5** | Test Search by **Collector ID**: Type `C01` (or `C001`). | All records collected by Collector `C01` are displayed. | Search filters by collector code. |

---

### Section 3: Detailed Record Inspection & Measurement Verification

| Step # | Test Action | Expected Result | Pass/Fail Criteria |
| :--- | :--- | :--- | :--- |
| **3.1** | Click on the row for **Fictional Participant Alpha** to open the Record Details drawer. | Bottom sheet / drawer slides in with title **Record summary**. Displays participant profile metadata, study ID, collector ID, visit number, and record UUID. | Record summary drawer opens cleanly. |
| **3.2** | Inspect **Participant Alpha** calculated fields in Drawer: | Verifies:<br>1. **Study site:** Community clinic<br>2. **Age / sex:** `30 · female`<br>3. **BMI:** Displays **`23.5`** (calculated from 170.0cm, 68.0kg)<br>4. **Average BP:** Displays **`120 / 80 mmHg`**<br>5. **Activity:** `225 min/week`<br>6. **Sleep:** `7.5 hours/night` | Calculated values match mathematical ground truth. |
| **3.3** | Open Record Details drawer for **Fictional Participant Beta** (Height missing: `declined`). | Verifies:<br>1. **BMI:** Explicitly displays **`Not recorded`** (since height is null).<br>2. **Average BP:** Displays `120 / 80 mmHg` (since both BP readings exist). | Missing height causes BMI to display `Not recorded`. |
| **3.4** | Open Record Details drawer for **Fictional Participant Gamma** (Weight missing: `unable`). | Verifies:<br>1. **BMI:** Explicitly displays **`Not recorded`** (since weight is null). | Missing weight causes BMI to display `Not recorded`. |
| **3.5** | Open Record Details drawer for **Fictional Participant Delta** (BP readings 1 & 2: `unable`). | Verifies:<br>1. **BMI:** Calculated correctly if height/weight present.<br>2. **Average BP:** Explicitly displays **`Not recorded`** (since both BP readings are null). | Missing BP readings cause Average BP to display `Not recorded`. |

---

### Section 4: CSV Export & Header Integrity

| Step # | Test Action | Expected Result | Pass/Fail Criteria |
| :--- | :--- | :--- | :--- |
| **4.1** | On the dashboard header, click **Copy CSV** button. | Browser copies full CSV text to clipboard. A SnackBar notification appears: `Copied 4 matching records as CSV.` | CSV string copied to system clipboard. |
| **4.2** | Paste the clipboard contents into a text editor (e.g. Notepad, VS Code) or spreadsheet tool. | Text contains comma-separated values with double-quote escaping for text entries. | Valid CSV formatting with consistent line endings. |
| **4.3** | **Verify Base Headers:** Check the first 7 columns of Row 1. | Exactly matches:<br>`visit_id,study_id,collector_id,visit_number,visit_status,sync_state,updated_at` | Base header columns match specification exactly. |
| **4.4** | **Verify Questionnaire Headers:** Check subsequent columns. | Contains all questionnaire keys prefixed with `ncd_`, sorted in alphabetical order:<br>`ncd_active_days_per_week,ncd_active_minutes_per_day,ncd_age,ncd_alcohol_frequency,ncd_alcohol_past30_days,ncd_average_diastolic,ncd_average_systolic,ncd_bmi,ncd_bp_one_diastolic,ncd_bp_one_missing_reason,ncd_bp_one_systolic,ncd_bp_two_diastolic,ncd_bp_two_missing_reason,ncd_bp_two_systolic,ncd_cardiovascular_diagnosis,ncd_diabetes_diagnosis,ncd_education,ncd_employment,ncd_fruit_frequency,ncd_height_cm,ncd_height_missing_reason,ncd_high_cholesterol_diagnosis,ncd_hypertension_diagnosis,ncd_processed_food_frequency,ncd_schema_version,ncd_sex,ncd_sleep_hours,ncd_study_site,ncd_sugary_drink_frequency,ncd_tobacco_frequency,ncd_tobacco_type,ncd_tobacco_use,ncd_vegetable_frequency,ncd_waist_cm,ncd_waist_missing_reason,ncd_weekly_active_minutes,ncd_weight_kg,ncd_weight_missing_reason` | All 38 `ncd_*` columns present and sorted (total 45 columns including the 7 base headers). |
| **4.5** | **Verify Missing Values in Data Rows:**<br>- Inspect row for **Participant Beta**:<br>  * `ncd_height_cm`: `""` (empty string)<br>  * `ncd_height_missing_reason`: `"declined"`<br>  * `ncd_bmi`: `""` (empty string)<br>- Inspect row for **Participant Gamma**:<br>  * `ncd_weight_kg`: `""`<br>  * `ncd_weight_missing_reason`: `"unable"`<br>  * `ncd_bmi`: `""`<br>- Inspect row for **Participant Delta**:<br>  * `ncd_bp_one_systolic`: `""`<br>  * `ncd_bp_one_missing_reason`: `"unable"`<br>  * `ncd_average_systolic`: `""`<br>  * `ncd_average_diastolic`: `""` | Missing measurements output clean empty quotes `""` for numeric fields while preserving reason codes in the corresponding `_missing_reason` column. | Numeric fields empty; reason strings populated. |

---

### Section 5: Administrative Correction & Questionnaire Preservation

| Step # | Test Action | Expected Result | Pass/Fail Criteria |
| :--- | :--- | :--- | :--- |
| **5.1** | In the Record Details drawer for **Participant Alpha**, click **Edit record**. | Opens `_RecordEditSheet` allowing edits to: Participant Name, Phone, Visit Number, Status, Review State, and Step 2 Note. | Edit modal opens with pre-populated values. |
| **5.2** | Enable the **Include Step 2 measurement** toggle. Enter:<br>- **Measurement value:** `14.2`<br>- **Measurement unit:** `mmol/L`<br>- **Measurement note:** `Verified by Dr. Sharma during clinic audit.` | Input fields accept values and pass local form validation. | Form inputs validated. |
| **5.3** | Check confirmation box: *"I have confirmed the participant details and visit number."* Tap **Save changes**. | Client dispatches `PUT /records/<visit_id>` with updated fields. Backend processes `store.replaceAdmin()`, incrementing `revision` by 1. Drawer shows SnackBar: `Visit C01-... updated.` | Save succeeds; revision increments. |
| **5.4** | **Preservation Verification:** Refresh the browser completely (Ctrl+F5) to clear client state and reload records directly from server storage. | Dashboard reloads. Open **Participant Alpha** details drawer. | Server data re-fetched. |
| **5.5** | Verify that the edited note is displayed **AND** all original NCD questionnaire responses are 100% intact: | Verifies:<br>1. **Optional Step 2 note:** `Verified by Dr. Sharma during clinic audit.`<br>2. **BMI:** Still `23.5`<br>3. **Average BP:** Still `120 / 80 mmHg`<br>4. All demographics, diet, tobacco, alcohol, and physical activity values remain exactly identical to initial submission. | Questionnaire data was preserved intact through administrative edit. |
| **5.6** | Test **Archive Visit**:<br>- In details drawer, tap **Archive visit**.<br>- Confirm confirmation dialog. | Server sets `isArchived = true`. Record disappears from active view and appears under `Archived` filter. Raw data is preserved; nothing is deleted. | Archive toggles without permanent data destruction. |

---

## 4. Acceptance Sign-Off

| Reviewer Name | Role | Timestamp | Signature / Verdict |
| :--- | :--- | :--- | :--- |
| | Head of Data Management | | `[ ] APPROVED` `[ ] REJECTED` |
| | Quality Assurance Engineer | | `[ ] APPROVED` `[ ] REJECTED` |
