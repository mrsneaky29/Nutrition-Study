# Android Client Acceptance Checklist (Nutrition Study 1.0.0+5)

**Target Artifact:** `study-collector-1.0.0+5.apk`  
**Build Configuration:** `--dart-define=LOCAL_GENERIC_RELEASE=true --dart-define=LOCAL_PUBLIC_RELEASE=true`  
**Expected SHA256 Checksum:** `1859d3afa4cef1da09987b443b9c107f20de7560cb0adc0ac05538c7f46c2982`  
**Execution Type:** Manual Field Simulation & Protocol Verification  
**Primary Auditor:** Field Acceptance Testing Lead  

---

## 1. Scope & Objective

This checklist provides a rigid, end-to-end procedural manual to verify the Android Study Collector client (version 1.0.0+5) under realistic field conditions. It exercises security constraints, offline persistence, data integrity validation, calculated metric formulas, and server-side synchronization idempotency.

---

## 2. Pre-Test Environmental Setup

1. **Hardware & OS Requirements:**
   - Physical Android device running Android 8.0 (API level 26) through Android 14 (API level 34).
   - Minimum 2 GB free internal storage.
   - Functional Wi-Fi and Mobile Data (Cellular) interfaces.
2. **Server Availability:**
   - Public HTTPS Backend active at `https://<domain>` (Gate B) **OR** local tunnel endpoint over HTTPS (`https://10.0.2.2:8787` / reverse proxy) (Gate A).
   - Valid Collector Access Key provisioned on the server for Collector ID `C001` (Collector 1).
3. **App Installation:**
   - Install `study-collector-1.0.0+5.apk` via ADB:
     ```powershell
     adb install -r build/app/outputs/flutter-apk/app-release.apk
     ```
   - Confirm app package name is `org.nutritionstudy.project2` and launches to the Sign-In screen.
   - *Dynamic Endpoint Configuration:* The signed shared +5 APK dynamically accepts any valid HTTPS server address at runtime in the Sign-In screen. It does **not** need to be recompiled for final domain deployment.

---

## 3. Step-by-Step Acceptance Checklist

### Phase 1: App Launch & Public HTTPS Enforcement

| Step # | Test Action | Expected Result | Pass/Fail Criteria |
| :--- | :--- | :--- | :--- |
| **1.1** | Launch the application from cold start. | Welcome / Sign-In screen displays with title **Study Collector**. Input fields shown: **Collector number**, **Server address**, and **Collector access key**. | Cold start displays clean UI without crashes. |
| **1.2** | Verify **Server address** field label and placeholder hint. | The field is explicitly labeled **Server address** (not "Home server address"). The hint text displays `https://server.example.com` (not `http://192.168.1.5:8787`). | Label matches `Server address`; hint specifies `https://`. |
| **1.3** | Enter an insecure HTTP address: `http://api.nutritionstudy.org` and tap **Continue**. | Validation blocks progression. Inline error displays: `Enter the server address provided by the administrator.` | Insecure cleartext HTTP scheme is strictly rejected. |
| **1.4** | Enter a malformed URL with path or query: `https://api.nutritionstudy.org/sync?v=1` and tap **Continue**. | Validation blocks progression. Form displays: `Enter the server address provided by the administrator.` | Base URL validator rejects query strings, paths, and fragments. |
| **1.5** | Enter a valid HTTPS server URL: `https://api.nutritionstudy.org` (or valid test HTTPS endpoint). | Input is accepted with no validation error. | HTTPS endpoint accepted. |

---

### Phase 2: Collector Authentication & Session Establishment

| Step # | Test Action | Expected Result | Pass/Fail Criteria |
| :--- | :--- | :--- | :--- |
| **2.1** | Test Collector Number formatting: Enter `1` in Collector Number. | The app normalizes positive integers. Input `1` maps internally to `C001` upon submission. | Accepts integer values `1` through `1000+`. |
| **2.2** | Enter an invalid collector number: `0` or `-5` or `abc`. | Form validation displays: `Enter a number such as 1.` | Non-positive and non-numeric entries rejected. |
| **2.3** | Test short Access Key: Enter fewer than 16 characters in Access Key. | Validation displays: `Enter your collector access key.` | Key length < 16 characters blocked. |
| **2.4** | Enter the full 32-character hexadecimal Access Key provisioned for Collector `C001` (Collector 1) and tap **Continue**. | Client sends `POST /collector/session` with header `x-local-sync-key: <key>` and body `{"collectorId": "C001"}`. Server returns `200 OK` with `sessionToken`. | App navigates to Collector Home Screen: "Hello, C001". |
| **2.5** | Inspect Home Screen initial state. | Displays metric cards: **Awaiting sync: 0**, **Recent submissions: 0**. Floating Action Button labeled **New participant**. | Header shows assigned Collector ID; counts initialize to zero. |

---

### Phase 3: Offline Data Collection Simulation (Airplane Mode)

| Step # | Test Action | Expected Result | Pass/Fail Criteria |
| :--- | :--- | :--- | :--- |
| **3.1** | **Enable Airplane Mode** on the device. Confirm Wi-Fi, Cellular Data, and Bluetooth are all disabled. | Device is fully offline. App remains fully operational. | No crash, no blocking network modals. |
| **3.2** | Tap **New participant** (+ Floating Action Button). | Navigates to **Participant Identification** step. Study ID is automatically generated with collector prefix: `C01-<16 digits>` (e.g. `C01-8392019482019384`). | Study ID is 16-digit CSPRNG sequence prefixed with `C01-`. |
| **3.3** | Enter Demographic Data (Synthetic Participant Alpha):<br>- **Participant Name:** `Fictional Participant Alpha`<br>- **Phone Number:** `9876543210` (India 10-digit format)<br>- Tap **Save and continue**. | Navigates to Step 1: **NCD Risk Questionnaire**. Participant summary displays at top: `Fictional Participant Alpha · C01-...`. | Form saves to local draft store. Draft recovery is active. |
| **3.4** | Complete Step 1: Questionnaire (Demographics & Habits):<br>- **Study site:** Community clinic<br>- **Age:** `30`<br>- **Sex:** Female<br>- **Education:** Higher education<br>- **Employment:** Employed / salaried<br>- **Tobacco use:** Never<br>- **Alcohol in past 30 days:** No<br>- **Dietary frequency (past 7 days):**<br>  * Fruit: 3–4 days<br>  * Vegetables: Every day<br>  * Sugary drinks: Never<br>  * Processed food: 1–2 days<br>- **Physical activity:**<br>  * Active days per week: `5`<br>  * Active minutes per day: `45`<br>- **Sleep:** `7.5` hours/night<br>- **Known diagnoses:** All "No" (Hypertension: No, Diabetes: No, Cholesterol: No, Cardiovascular: No). | All form inputs accept values. Weekly active minutes calculated as `5 * 45 = 225 minutes`. Tap **Continue to measurements**. | Form transitions cleanly to Step 2: Physical measurements without network calls. |

---

### Phase 4: Step 2 Physical Measurements & Missing Value Handlers

| Step # | Test Action | Expected Result | Pass/Fail Criteria |
| :--- | :--- | :--- | :--- |
| **4.1** | **Normal Measurements (Participant Alpha):**<br>- **Height status:** Measured<br>- **Height (cm):** `170.0`<br>- **Weight status:** Measured<br>- **Weight (kg):** `68.0`<br>- **Waist circumference status:** Measured<br>- **Waist circumference (cm):** `80.0`<br>- **Reading 1 status:** Measured -> Systolic: `120`, Diastolic: `80`<br>- **Reading 2 status:** Measured -> Systolic: `120`, Diastolic: `80` | All decimal and integer inputs accepted. Validates systolic > diastolic. Tap **Review questionnaire**. | Transitions to **Review and submit** screen. |
| **4.2** | Verify **Calculated BMI** on Review Screen:<br>Formula: $\text{BMI} = \frac{\text{weight}}{(\text{height}/100)^2} = \frac{68.0}{1.7^2} = \frac{68.0}{2.89} \approx 23.529...$ | Review screen explicitly displays **BMI: 23.5** (rounded to 1 decimal place). | BMI equals exactly `23.5`. |
| **4.3** | Verify **Average Blood Pressure** on Review Screen:<br>Systolic: $(120 + 120)/2 = 120$<br>Diastolic: $(80 + 80)/2 = 80$ | Review screen explicitly displays **Average blood pressure: 120 / 80 mmHg**. | Avg BP formatted as `120 / 80 mmHg`. |
| **4.4** | **Missing Measurement Reasons Test (Synthetic Participant Beta):**<br>Create new draft for Participant Beta.<br>In Step 2 Physical Measurements:<br>- Set **Height status** dropdown to `Declined`.<br>- Note that Height numeric text field disappears.<br>- Enter **Weight (kg):** `72.0` (status: Measured). | When status is `Declined`, input field is hidden and `heightMissingReason` is stored as `'declined'`. Tap **Review questionnaire**. | Review screen shows **Height: Declined** and **BMI: Not calculated**. |
| **4.5** | **Missing Measurement Reasons Test (Synthetic Participant Gamma):**<br>Create new draft for Participant Gamma.<br>- Enter **Height (cm):** `165.0`.<br>- Set **Weight status** dropdown to `Unable to measure`.<br>- Note that Weight numeric input field disappears. | Input field hidden; `weightMissingReason` stored as `'unable'`. Tap **Review questionnaire**. | Review screen shows **Weight: Unable to measure** and **BMI: Not calculated**. |
| **4.6** | **Missing Blood Pressure Test (Synthetic Participant Delta):**<br>Create draft for Participant Delta.<br>- Set **Reading 1 status** to `Unable to measure`.<br>- Set **Reading 2 status** to `Unable to measure`. | Both BP input fields hidden; `bpOneMissingReason` and `bpTwoMissingReason` stored as `'unable'`. Tap **Review questionnaire**. | Review screen displays **Reading 1: Unable to measure**, **Reading 2: Unable to measure**, and **Average blood pressure: Not calculated**. |

---

### Phase 5: Submission Receipt & Offline Queue Verification

| Step # | Test Action | Expected Result | Pass/Fail Criteria |
| :--- | :--- | :--- | :--- |
| **5.1** | On Review screen for Participant Alpha, tap **Review and submit**. | Submission completes locally. Navigates to **Submission receipt** screen. | Receipt displays checkmark icon and confirmation message. |
| **5.2** | Inspect **Submission receipt** fields: | Verifies:<br>1. **Submission ID:** Valid UUIDv4 format.<br>2. **Study ID:** Matches generated `C01-<16 digits>`.<br>3. **BMI:** `23.5`<br>4. **Average blood pressure:** `120 / 80 mmHg`<br>5. **Sync status:** `Pending` chip (yellow/neutral accent).<br>6. Offline notice: *"This entry remains safely stored on this device and will sync when available."* | All receipt elements match expected values and offline status is `Pending`. |
| **5.3** | Tap **Return home**. Inspect Collector Home Screen. | **Awaiting sync** metric increments to `1` (or total pending). **Recent activity** displays Participant Alpha card with `Pending` status chip. | Home screen reflects pending submission count. |
| **5.4** | Tap **View all** to navigate to **My submissions**. | Screen displays list with search bar. Participant Alpha is visible showing name, `C01-...`, `Visit 1`, and `Pending` chip. | Submission is queryable in local submission repository. |

---

### Phase 6: App Kill, RAM Eviction & Persistence Verification

| Step # | Test Action | Expected Result | Pass/Fail Criteria |
| :--- | :--- | :--- | :--- |
| **6.1** | Maintain **Airplane Mode** (offline). Open Android App Switcher / Recent Apps and swipe away **Study Collector** to force kill. | Process is terminated. RAM is freed. | App process killed. |
| **6.2** | Optional OS check via ADB: | Confirm PID is destroyed:<br>`adb shell pidof org.nutritionstudy.project2` returns empty. | Process completely dead. |
| **6.3** | Reopen **Study Collector** from application launcher while still offline. | App opens directly to Collector Home Screen without re-prompting for credentials. Stored session token and collector identity persist in encrypted SQLite / Secure Storage. | Auto-login succeeds offline from secure local credentials. |
| **6.4** | Check **Awaiting sync** card and **Recent activity**. | Awaiting sync count is still `1` (or pending total). Participant Alpha is present with `Pending` status chip intact. | Pending records survive complete process termination and reboot. |

---

### Phase 7: Network Reconnection & Cloud Synchronization

| Step # | Test Action | Expected Result | Pass/Fail Criteria |
| :--- | :--- | :--- | :--- |
| **7.1** | **Disable Airplane Mode**. Connect device to cellular data or verified test Wi-Fi network with access to the HTTPS server. | Network connectivity restored. Server endpoint is reachable via HTTPS. | Device internet connection confirmed active. |
| **7.2** | On Collector Home Screen, observe the sync action button in top AppBar. Tap the **Sync (Retry pending sync)** icon. | Sync indicator displays circular progress animation (`isRetrying = true`). Client dispatches `POST /records` with JSON payload and header `x-local-session: <sessionToken>`. | Server processes payload and returns `200 OK`. |
| **7.3** | Inspect Home Screen after sync completion. | **Awaiting sync** metric drops to `0`. Participant Alpha's status chip transitions from `Pending` (yellow) to **Synced** (green). | Visual state transitions immediately to Synced. |
| **7.4** | Open **My submissions** and tap on Participant Alpha's card. | Detail view shows **Sync status: Synced**. Submission ID, Study ID, and visit details are identical to offline entry. | Record confirmed synchronized in local database. |

---

### Phase 8: Duplicate Prevention & Server Idempotency

| Step # | Test Action | Expected Result | Pass/Fail Criteria |
| :--- | :--- | :--- | :--- |
| **8.1** | While online and fully synced, trigger the sync cycle again (or use ADB / debug runner to re-send the exact same record payload with identical `id` and `idempotencyKey`). | Client sends duplicate request to `POST /records`. | Server inspects `idempotencyKey` against existing record ID. |
| **8.2** | Verify Server HTTP Response Code and Body. | Server returns **`200 OK`** (idempotent clone of existing record). It does **NOT** increment `revision`, does **NOT** duplicate rows in database, and does **NOT** return a 409 Conflict. | Idempotency verified: 200 OK without duplicate record creation. |
| **8.3** | Verify Admin Portal / Server Record Count. | The total stored record count on the backend remains unchanged. Only one visit record exists for that `visit_id`. | Zero duplicate entries created on server. |

---

## 4. Sign-Off Execution Block

| Auditor Name | Role / Title | Date & Time | Overall Verdict |
| :--- | :--- | :--- | :--- |
| | Android Acceptance QA Lead | | `[ ] PASS` `[ ] FAIL` |
| | Study Principal Investigator | | `[ ] PASS` `[ ] FAIL` |

*Notes / Deviations:*
