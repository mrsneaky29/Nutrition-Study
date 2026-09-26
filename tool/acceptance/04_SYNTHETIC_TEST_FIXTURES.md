# Synthetic Test Fixtures (Nutrition Study 1.0.0+5)

**Strict Confidentiality & Privacy Notice:**  
All data contained in this document is **100% synthetic and fictional**. It contains **NO real participant details, NO real Indian phone numbers, NO PII (Personally Identifiable Information), and NO production credentials**. These fixtures are designed solely for protocol verification, automated test suites, and acceptance testing.

---

## 1. Study Sizing & Architectural Invariants

### 1.1 Unlimited Participant Capacity Guarantee
> [!IMPORTANT]
> **Zero Artificial Participant Count Limit:**  
> The Nutrition Study system (client, API, and local storage) **NEVER imposes an artificial participant count limit**. Neither the Android SQLite schema, the local draft store, the HTTP client, nor the backend server places an upper bound on the number of participants or visits that can be collected. The system architecture supports open-ended participant enrollment across all phases.

### 1.2 Collector Number Scaling
As of release 1.0.0+5 (commit `faef803`), the legacy two-digit (99-collector) restriction has been completely eliminated. The system supports full collector numbering from `C01` (1) through `C100`, `C1000`, and above.

---

## 2. Synthetic Collector Credentials Template

Below are clean 32-character hexadecimal templates for configuring public-mode collector access on test servers and client devices:

```ini
# Environment Variable: LOCAL_SYNC_COLLECTOR_KEYS
# Format: collectorId:key (comma-separated, 3-digit zero-padded for collectors < 100)
C001:c0010101010101010101010101010101,C002:c0020202020202020202020202020202,C100:c1001001001001001001001001001001,C1000:c1000100010001000100010001000100

# Environment Variable: LOCAL_SYNC_ADMIN_KEY (minimum 32 hex characters)
LOCAL_SYNC_ADMIN_KEY=a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0
```

---

## 3. Synthetic Participant Fixtures

### Fixture 1: Participant Alpha (Complete Normal Measurements)

- **Purpose:** Baseline verification of valid full questionnaire, BMI formula, and Average BP calculation.
- **Participant Profile:**
  - **Full Name:** `Fictional Participant Alpha`
  - **Phone Number:** `+919876543210` (Fictional 10-digit)
  - **Age:** `30`
  - **Sex:** `female`
  - **Study Site:** `community_clinic`
  - **Education:** `higher`
  - **Employment:** `employed_salaried`
- **Habits & Lifestyle:**
  - **Tobacco Use:** `never`
  - **Alcohol Past 30 Days:** `no`
  - **Diet Frequency (past 7 days):**
    * Fruit: `three_to_four_days`
    * Vegetables: `daily`
    * Sugary Drinks: `never`
    * Processed Foods: `one_to_two_days`
  - **Physical Activity:** Active Days/Week = `5`, Active Mins/Day = `45` (Weekly Active = `225` mins)
  - **Sleep:** `7.5` hours/night
  - **Diagnoses:** Hypertension = `no`, Diabetes = `no`, High Cholesterol = `no`, Cardiovascular = `no`
- **Physical Measurements:**
  - **Height:** `170.0 cm` (Status: `recorded`, `heightMissingReason: null`)
  - **Weight:** `68.0 kg` (Status: `recorded`, `weightMissingReason: null`)
  - **Waist Circumference:** `80.0 cm` (Status: `recorded`, `waistMissingReason: null`)
  - **BP Reading 1:** Systolic `120 mmHg`, Diastolic `80 mmHg` (Status: `recorded`)
  - **BP Reading 2:** Systolic `120 mmHg`, Diastolic `80 mmHg` (Status: `recorded`)
- **Mathematical Expectation:**
  $$\text{BMI} = \frac{68.0}{(170.0 / 100)^2} = \frac{68.0}{2.89} \approx 23.5294... \xrightarrow{\text{rounded}} \mathbf{23.5}$$
  $$\text{Average Systolic} = \frac{120 + 120}{2} = \mathbf{120}, \quad \text{Average Diastolic} = \frac{80 + 80}{2} = \mathbf{80}$$
- **UI Ground Truth:**
  - App Review Screen: `BMI: 23.5` | `Average blood pressure: 120 / 80 mmHg`
  - App Receipt: `BMI: 23.5` | `Average blood pressure: 120 / 80 mmHg`
  - Admin Web Portal: `BMI: 23.5` | `Average BP: 120 / 80 mmHg`
  - CSV Export: `ncd_bmi: "23.529411764705884"` (raw), `ncd_height_cm: "170.0"`, `ncd_weight_kg: "68.0"`, `ncd_height_missing_reason: ""`

```json
{
  "id": "synthetic-uuid-alpha-0001",
  "participant": {
    "name": "Fictional Participant Alpha",
    "studyId": "C01-8192039482019482",
    "indianPhone": "+919876543210"
  },
  "visitNumber": 1,
  "collectorId": "C001",
  "status": "submitted",
  "syncState": "synced",
  "questionnaire": {
    "schemaVersion": 2,
    "studySite": "community_clinic",
    "age": 30,
    "sex": "female",
    "education": "higher",
    "employment": "employed_salaried",
    "fruitFrequency": "three_to_four_days",
    "vegetableFrequency": "daily",
    "sugaryDrinkFrequency": "never",
    "processedFoodFrequency": "one_to_two_days",
    "activeDaysPerWeek": 5,
    "activeMinutesPerDay": 45,
    "sleepHours": 7.5,
    "heightCm": 170.0,
    "weightKg": 68.0,
    "waistCm": 80.0,
    "bpOneSystolic": 120,
    "bpOneDiastolic": 80,
    "bpTwoSystolic": 120,
    "bpTwoDiastolic": 80,
    "heightMissingReason": null,
    "weightMissingReason": null,
    "waistMissingReason": null,
    "bpOneMissingReason": null,
    "bpTwoMissingReason": null
  }
}
```

---

### Fixture 2: Participant Beta (Missing Height - Reason: Declined)

- **Purpose:** Verification of explicit measurement refusal handling (`declined`), null BMI propagation, and UI string formatting.
- **Participant Profile:**
  - **Full Name:** `Fictional Participant Beta`
  - **Phone Number:** `+919876543211`
  - **Age:** `45`
  - **Sex:** `male`
  - **Study Site:** `community_outreach`
  - **Education:** `secondary`
  - **Employment:** `self_employed`
- **Physical Measurements:**
  - **Height:** `null` (Status: `declined`, `heightMissingReason: "declined"`)
  - **Weight:** `72.0 kg` (Status: `recorded`, `weightMissingReason: null`)
  - **Waist Circumference:** `88.0 cm` (Status: `recorded`, `waistMissingReason: null`)
  - **BP Reading 1:** Systolic `130 mmHg`, Diastolic `85 mmHg`
  - **BP Reading 2:** Systolic `126 mmHg`, Diastolic `83 mmHg`
- **Mathematical Expectation:**
  $$\text{Height is null} \implies \text{BMI is null}$$
  $$\text{Average Systolic} = \frac{130 + 126}{2} = \mathbf{128}, \quad \text{Average Diastolic} = \frac{85 + 83}{2} = \mathbf{84}$$
- **UI Ground Truth:**
  - App Review Screen: `Height: Declined` | `BMI: Not calculated` | `Average blood pressure: 128 / 84 mmHg`
  - App Receipt: `BMI: Not calculated` | `Average blood pressure: 128 / 84 mmHg`
  - Admin Web Portal: `BMI: Not recorded` | `Average BP: 128 / 84 mmHg`
  - CSV Export: `ncd_height_cm: ""`, `ncd_height_missing_reason: "declined"`, `ncd_bmi: ""`, `ncd_weight_kg: "72.0"`

```json
{
  "id": "synthetic-uuid-beta-0002",
  "participant": {
    "name": "Fictional Participant Beta",
    "studyId": "C01-9283019284710293",
    "indianPhone": "+919876543211"
  },
  "visitNumber": 1,
  "collectorId": "C001",
  "status": "submitted",
  "syncState": "synced",
  "questionnaire": {
    "schemaVersion": 2,
    "studySite": "community_outreach",
    "age": 45,
    "sex": "male",
    "education": "secondary",
    "employment": "self_employed",
    "fruitFrequency": "one_to_two_days",
    "vegetableFrequency": "three_to_four_days",
    "sugaryDrinkFrequency": "one_to_two_days",
    "processedFoodFrequency": "three_to_four_days",
    "activeDaysPerWeek": 3,
    "activeMinutesPerDay": 30,
    "sleepHours": 6.5,
    "heightCm": null,
    "weightKg": 72.0,
    "waistCm": 88.0,
    "bpOneSystolic": 130,
    "bpOneDiastolic": 85,
    "bpTwoSystolic": 126,
    "bpTwoDiastolic": 83,
    "heightMissingReason": "declined",
    "weightMissingReason": null,
    "waistMissingReason": null,
    "bpOneMissingReason": null,
    "bpTwoMissingReason": null
  }
}
```

---

### Fixture 3: Participant Gamma (Missing Weight - Reason: Unable)

- **Purpose:** Verification of physical inability to record measurement (`unable`), null BMI computation, and questionnaire integrity.
- **Participant Profile:**
  - **Full Name:** `Fictional Participant Gamma`
  - **Phone Number:** `+919876543212`
  - **Age:** `62`
  - **Sex:** `female`
  - **Study Site:** `community_clinic`
  - **Education:** `primary`
  - **Employment:** `retired`
- **Physical Measurements:**
  - **Height:** `165.0 cm` (Status: `recorded`, `heightMissingReason: null`)
  - **Weight:** `null` (Status: `unable`, `weightMissingReason: "unable"`, e.g. scale failure/wheelchair)
  - **Waist Circumference:** `null` (Status: `unable`, `waistMissingReason: "unable"`)
  - **BP Reading 1:** Systolic `140 mmHg`, Diastolic `90 mmHg`
  - **BP Reading 2:** Systolic `138 mmHg`, Diastolic `88 mmHg`
- **Mathematical Expectation:**
  $$\text{Weight is null} \implies \text{BMI is null}$$
  $$\text{Average Systolic} = \frac{140 + 138}{2} = \mathbf{139}, \quad \text{Average Diastolic} = \frac{90 + 88}{2} = \mathbf{89}$$
- **UI Ground Truth:**
  - App Review Screen: `Weight: Unable to measure` | `BMI: Not calculated` | `Average blood pressure: 139 / 89 mmHg`
  - App Receipt: `BMI: Not calculated` | `Average blood pressure: 139 / 89 mmHg`
  - Admin Web Portal: `BMI: Not recorded` | `Average BP: 139 / 89 mmHg`
  - CSV Export: `ncd_weight_kg: ""`, `ncd_weight_missing_reason: "unable"`, `ncd_waist_cm: ""`, `ncd_waist_missing_reason: "unable"`, `ncd_bmi: ""`

```json
{
  "id": "synthetic-uuid-gamma-0003",
  "participant": {
    "name": "Fictional Participant Gamma",
    "studyId": "C01-1029384756102938",
    "indianPhone": "+919876543212"
  },
  "visitNumber": 1,
  "collectorId": "C001",
  "status": "submitted",
  "syncState": "synced",
  "questionnaire": {
    "schemaVersion": 2,
    "studySite": "community_clinic",
    "age": 62,
    "sex": "female",
    "education": "primary",
    "employment": "retired",
    "fruitFrequency": "five_to_six_days",
    "vegetableFrequency": "daily",
    "sugaryDrinkFrequency": "never",
    "processedFoodFrequency": "never",
    "activeDaysPerWeek": 4,
    "activeMinutesPerDay": 20,
    "sleepHours": 8.0,
    "heightCm": 165.0,
    "weightKg": null,
    "waistCm": null,
    "bpOneSystolic": 140,
    "bpOneDiastolic": 90,
    "bpTwoSystolic": 138,
    "bpTwoDiastolic": 88,
    "heightMissingReason": null,
    "weightMissingReason": "unable",
    "waistMissingReason": "unable",
    "bpOneMissingReason": null,
    "bpTwoMissingReason": null
  }
}
```

---

### Fixture 4: Participant Delta (Missing Blood Pressure - Reason: Unable)

- **Purpose:** Verification of missing blood pressure readings, null average BP handling, and full independent BMI calculation.
- **Participant Profile:**
  - **Full Name:** `Fictional Participant Delta`
  - **Phone Number:** `+919876543213`
  - **Age:** `28`
  - **Sex:** `male`
  - **Study Site:** `other_site`
  - **Education:** `higher`
  - **Employment:** `employed_salaried`
- **Physical Measurements:**
  - **Height:** `175.0 cm` (Status: `recorded`, `heightMissingReason: null`)
  - **Weight:** `70.0 kg` (Status: `recorded`, `weightMissingReason: null`)
  - **Waist Circumference:** `82.0 cm` (Status: `recorded`, `waistMissingReason: null`)
  - **BP Reading 1:** `null` (Status: `unable`, `bpOneMissingReason: "unable"`, e.g. cuff unavailable)
  - **BP Reading 2:** `null` (Status: `unable`, `bpTwoMissingReason: "unable"`)
- **Mathematical Expectation:**
  $$\text{BMI} = \frac{70.0}{(175.0 / 100)^2} = \frac{70.0}{3.0625} \approx 22.857... \xrightarrow{\text{rounded}} \mathbf{22.9}$$
  $$\text{BP Readings are null} \implies \text{Average Blood Pressure is null}$$
- **UI Ground Truth:**
  - App Review Screen: `BMI: 22.9` | `Reading 1: Unable to measure` | `Reading 2: Unable to measure` | `Average blood pressure: Not calculated`
  - App Receipt: `BMI: 22.9` | `Average blood pressure: Not calculated`
  - Admin Web Portal: `BMI: 22.9` | `Average BP: Not recorded`
  - CSV Export: `ncd_bmi: "22.857142857142858"`, `ncd_bp_one_systolic: ""`, `ncd_bp_one_missing_reason: "unable"`, `ncd_average_systolic: ""`

```json
{
  "id": "synthetic-uuid-delta-0004",
  "participant": {
    "name": "Fictional Participant Delta",
    "studyId": "C01-4920194820194820",
    "indianPhone": "+919876543213"
  },
  "visitNumber": 1,
  "collectorId": "C001",
  "status": "submitted",
  "syncState": "synced",
  "questionnaire": {
    "schemaVersion": 2,
    "studySite": "other_site",
    "age": 28,
    "sex": "male",
    "education": "higher",
    "employment": "employed_salaried",
    "fruitFrequency": "daily",
    "vegetableFrequency": "daily",
    "sugaryDrinkFrequency": "never",
    "processedFoodFrequency": "never",
    "activeDaysPerWeek": 6,
    "activeMinutesPerDay": 60,
    "sleepHours": 7.0,
    "heightCm": 175.0,
    "weightKg": 70.0,
    "waistCm": 82.0,
    "bpOneSystolic": null,
    "bpOneDiastolic": null,
    "bpTwoSystolic": null,
    "bpTwoDiastolic": null,
    "heightMissingReason": null,
    "weightMissingReason": null,
    "waistMissingReason": null,
    "bpOneMissingReason": "unable",
    "bpTwoMissingReason": "unable"
  }
}
```
