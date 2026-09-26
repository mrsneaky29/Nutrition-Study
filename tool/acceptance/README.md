# Nutrition Study 1.0.0+5 Acceptance Testing Kit

**Release Version:** `1.0.0+5`  
**Git Baseline Commit:** `8f170a74e8e08d11c819958b94f467f3448d56e8`  
**Branch:** `codex/plus5-acceptance-kit`  
**Primary APK Checksum (SHA256):** `1859d3afa4cef1da09987b443b9c107f20de7560cb0adc0ac05538c7f46c2982`  
**Author:** Acceptance Kit Author  

---

## 1. Executive Summary

This directory contains the complete, grounded, and standardized **Acceptance Test Kit** for the **Nutrition Study 1.0.0+5** release. The kit provides comprehensive, reproducible verification protocols for the mobile collector client, administrative portal, server-side data synchronization, multi-device collector handovers, and release gating criteria.

> [!CAUTION]
> **Strict Synthetic Data Policy:**  
> All fixtures, phone numbers, participant names, and credentials within this kit are **100% fictional and synthetic**. Real participant records, authentic PII, and production access keys must **never** be entered during acceptance verification or committed to source control.

---

## 2. Directory Navigation & Kit Structure

| Document | Primary Focus | Target Audience |
| :--- | :--- | :--- |
| **[01_ANDROID_ACCEPTANCE_CHECKLIST.md](01_ANDROID_ACCEPTANCE_CHECKLIST.md)** | Step-by-step checklist for the Android collector app. Covers HTTPS URL enforcement, offline drafting, physical measurements, BMI and average BP formulas, missing reasons, receipt verification, app restarts, reconnection sync, and idempotency. | Android QA Engineers, Field Coordinators |
| **[02_TWO_PHONE_COLLECTOR_HANDOVER_TEST.md](02_TWO_PHONE_COLLECTOR_HANDOVER_TEST.md)** | Protocol for two-phone collector handover. Validates single active session arbitration, HTTP 401 session expiration, zero offline data loss, session reclaim, sync of preserved records, and 16-digit CSPRNG Study ID collision safety. | Systems QA, Backend Engineers |
| **[03_ADMIN_ACCEPTANCE_CHECKLIST.md](03_ADMIN_ACCEPTANCE_CHECKLIST.md)** | Checklist for the Administrator Web Portal. Covers exact CORS origin enforcement, status filtering, record search, detailed inspection of calculated vs missing metrics, CSV export format, and questionnaire preservation during admin edits. | Data Managers, Compliance Officers |
| **[04_SYNTHETIC_TEST_FIXTURES.md](04_SYNTHETIC_TEST_FIXTURES.md)** | Fictional test profiles (Alpha, Beta, Gamma, Delta) and 32-character hexadecimal credential templates. Documents that there is **no application-imposed participant-count cap** (subject to host server hardware resources) and collector number scaling beyond 99. | Test Operators, Automation Engineers |
| **[05_RESULTS_TEMPLATE.md](05_RESULTS_TEMPLATE.md)** | Standardized results capture template using `[AUTOMATED PASS]`, `[CODEX REPORTED PASS]`, `[MANUAL PASS]`, `[NOT TESTED]`, and `[BLOCKED]` indicators. Includes environment capture tables, infrastructure matrix, evidence log, and sign-off blocks. | QA Leads, Acceptance Auditors |
| **[06_RELEASE_GATE_CHECKLIST.md](06_RELEASE_GATE_CHECKLIST.md)** | Release gating matrix dividing verification into Gate A (Local & Pre-Domain Verification) and Gate B (Public HTTPS & Live Domain Gates). | Release Managers, DevOps, PI |

---

## 3. Recommended Execution Workflow

To perform a complete acceptance audit of Nutrition Study 1.0.0+5, follow this sequential pathway:

```mermaid
graph TD
    A["Review Synthetic Test Fixtures<br>(04_SYNTHETIC_TEST_FIXTURES.md)"] --> B["Execute Gate A Verification<br>(06_RELEASE_GATE_CHECKLIST.md - Gate A)"]
    B --> C["Execute Android Client Checklist<br>(01_ANDROID_ACCEPTANCE_CHECKLIST.md)"]
    C --> D["Execute Two-Phone Handover Test<br>(02_TWO_PHONE_COLLECTOR_HANDOVER_TEST.md)"]
    D --> E["Execute Admin Portal Checklist<br>(03_ADMIN_ACCEPTANCE_CHECKLIST.md)"]
    E --> F["Record Findings & Evidence<br>(05_RESULTS_TEMPLATE.md)"]
    F --> G["Evaluate Release Gate B Prerequisites<br>(06_RELEASE_GATE_CHECKLIST.md - Gate B)"]
```

1. **Step 1: Setup & Grounding:** Read `04_SYNTHETIC_TEST_FIXTURES.md` to understand expected participant profiles and calculation formulas.
2. **Step 2: Gate A Automated & Infrastructure Verification:** Confirm all worktree automated tests pass (`[AUTOMATED PASS]`: 244 regression, 64 store, 80 domain/sync, 24 web packaging, `flutter analyze` clean). Note that Codex has verified host firewall, systemd sandbox, isolated restore (`tool/vps/test-restore.sh`), and private encrypted Google Drive backup roundtrip (`tool/vps/test-encrypted-roundtrip.sh`) on the Ubuntu VPS (`[CODEX REPORTED PASS]`). Automatic backup timers remain disabled pending USB key retention.
3. **Step 3: Android Verification:** Follow `01_ANDROID_ACCEPTANCE_CHECKLIST.md` on a physical Android device. Note that the existing signed shared +5 APK (`study-collector-1.0.0+5.apk`, SHA256: `1859d3afa4cef1da09987b443b9c107f20de7560cb0adc0ac05538c7f46c2982`) accepts its HTTPS server address dynamically at sign-in runtime and does not need to be rebuilt. Validate offline persistence, calculations, and receipt generation.
4. **Step 4: Multi-Device Verification:** Run `02_TWO_PHONE_COLLECTOR_HANDOVER_TEST.md` using two phones to verify session arbitration and collision avoidance.
5. **Step 5: Admin Web Verification:** Follow `03_ADMIN_ACCEPTANCE_CHECKLIST.md`. Functional UI testing is executed locally under Option A (Isolated Local Test Harness in private mode). Direct testing against the public VPS via raw HTTP SSH tunnel is `[BLOCKED]` because public mode enforces `X-Forwarded-Proto: https` and exact origin matching without weakening production security.
6. **Step 6: Document Audit Trail:** Fill out `05_RESULTS_TEMPLATE.md` with screenshot references, log hashes, and signatures.
7. **Step 7: Pre-Deployment Sign-Off:** Review `06_RELEASE_GATE_CHECKLIST.md`. Confirm that while automated tests and Codex VPS drills have passed, Gate A as a whole requires manual device/admin completion, and Gate B remains blocked until domain acquisition, DNS propagation, and live TLS certificates are provisioned.

---

## 4. Key Implementation Facts for Auditors

- **Calculated BMI Formula:**  
  $$\text{BMI} = \frac{\text{Weight (kg)}}{(\text{Height (cm)} / 100)^2}$$  
  Rounded to **1 decimal place** in the UI (e.g. $170\text{ cm}, 68\text{ kg} \implies 23.5$). If either height or weight is missing, BMI is `null` (`Not calculated` in client, `Not recorded` in admin).
- **Average Blood Pressure Formula:**  
  $$\text{Systolic}_{\text{avg}} = \frac{S_1 + S_2}{2}, \quad \text{Diastolic}_{\text{avg}} = \frac{D_1 + D_2}{2}$$  
  Formatted as `${S} / ${D}\text{ mmHg}`. If either reading is missing, Average BP is `null`.
- **Missing Measurement Statuses:**  
  Explicitly coded as `'unable'` or `'declined'`. In CSV exports, numeric columns are empty strings `""`, and reason columns (e.g. `ncd_height_missing_reason`) contain the reason text.
- **Study ID Structure:**  
  In generic release mode: `C<col>-<16 digits>`, generated via secure CSPRNG sequence (`upper * 100000000 + lower`). There are $9 \times 10^{15}$ possible suffixes per collector. IDs are collision-resistant, not guaranteed collision-free; the app checks local duplicates and the server checks records during sync.
- **Idempotency Guarantee:**  
  Upload retries for an existing record ID and matching `idempotencyKey` return HTTP `200 OK` with the existing record, without incrementing `revision` or creating duplicate rows.
- **CORS Enforcement & Public Mode:**  
  Public mode requires `LOCAL_SYNC_ALLOWED_ORIGINS` with exact HTTPS origins and `X-Forwarded-Proto: https`. Wildcard origins (`*`) and cleartext HTTP are strictly prohibited. A raw SSH tunnel (`ssh -L`) forwarding HTTP directly to loopback port 8787 fails public-mode security guards; NEVER weaken production security for testing. Use Option A (isolated local private test harness) for functional UI testing, or wait for Gate B (domain & TLS) for production VPS verification.
- **Participant Capacity:**  
  The system architecture enforces **no application-imposed participant-count cap** across client SQLite storage, draft files, and server JSON state; actual operational capacity is bounded solely by host server hardware resources (disk space, RAM, CPU throughput).
- **Safe Restore Testing Invariant:**  
  NEVER run restore tests against a live production service or live study state. Restore verification must run in isolated staging directories with isolated safety backups and mocked/test service identifiers (e.g. `tool/vps/test-restore.sh`).
- **Encrypted Offsite Backup Decoupled from Domain:**  
  Offsite backup to private Google Drive (`study-crypt:`) has been verified via synthetic roundtrip on the VPS by Codex (`[CODEX REPORTED PASS]`, `tool/vps/test-encrypted-roundtrip.sh`) and does NOT require a purchased domain. Automated systemd timers (`plus5-offsite-backup.timer`) remain disabled pending physical USB recovery key retention and final production sign-off.
- **Android APK Dynamic Server Address:**  
  The signed shared +5 APK (`study-collector-1.0.0+5.apk`, SHA256: `1859d3afa4cef1da09987b443b9c107f20de7560cb0adc0ac05538c7f46c2982`) dynamically accepts its HTTPS server address at runtime and does NOT need to be recompiled for final domain deployment. Only the admin web client needs to be compiled with the real API base URL.
