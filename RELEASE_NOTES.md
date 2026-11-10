# Vivayu 1.0.4+12

## Volunteer access and public Android download

- Added **Continue as volunteer** beside QR sign-in, without asking for any
  sign-in details. First use needs internet; each installation retains its own
  securely generated credential and can resume after logout or restart.
- Volunteer submissions are labeled **Volunteer** in the app and admin console,
  including search and archive/restore. Raw IDs remain available for audit/export.
- Volunteers are restricted to their own participant lookup and submissions;
  admin endpoints and other collectors' records stay protected. Anonymous
  registration/upload limits and persistent disable support are included.
- English and Telugu copy added. Existing QR sign-in, questionnaire schema 4,
  calculations, research estimates and admin measurement corrections remain.
- The homepage Vivayu card links to a direct signed APK download on the existing
  DigitalOcean host. No Play Store or Google Drive login is needed.

## Retained from 1.0.3+11

## Admin measurement corrections

The admin visit editor can correct body measurements, both blood-pressure
readings, activity and sleep values, and the optional Step 2 measurement. BMI,
waist-to-hip ratio, average blood pressure, and weekly activity recalculate on
save. Admin edits detect when another change has already updated the visit.

## Backend scoring update

Admin record listings now include research estimates for existing and newly
submitted visits. The backend uses the original four-input model when the
expanded model's answers are incomplete. The result names the selected model.
Required unknown answers and previous diagnoses produce a status for the
affected outcome. Scoring runs entirely on the server.
The admin console shows these estimates and the model used beside each visit.
The existing Android build supports this backend update.

The collector questionnaire adds four optional items in English and Telugu.

- Difficulty walking one kilometre
- Alcohol use, including occasional use
- Farm, business, wage or salaried work during the past year
- A previous diagnosis of heart disease

The VPS backend accepts questionnaire versions 1–4. Administrators can request
an on-demand research estimate with `GET /records/<record-id>/research-risk`.
The scorer runs in Dart using fixed coefficients from three logistic regression
models trained on the IHDS 2004–05 and 2011–12 panel. It estimates newly reported
hypertension, diabetes and heart disease. For each outcome it returns an
estimate, a prior-diagnosis status, or an insufficient-information status.

The expanded model's AUC on held-out IHDS households was 0.755 for hypertension,
0.791 for diabetes and 0.724 for heart disease. This is internal validation in
the historical cohort. The API is for research and requires administrator access.
The release includes the training code and aggregate results.

The local regression suite passed 308 tests, with 14 configuration-dependent
skips. The test suite covers legacy questionnaires, access control and agreement
with Python on a synthetic profile.

Activate the backend before distributing the collector APK. Install the APK over
the previous official Vivayu build to preserve the phone's saved records and
settings. The package remains `org.nutritionstudy.project2`.
