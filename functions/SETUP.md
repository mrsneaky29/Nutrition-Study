# Firebase pilot backend

This is the deployable cloud replacement for the temporary LAN/JSON service.
It is designed for the one-week real-data pilot: collectors use administrator-
created codes (not email/password accounts), while administrators retain their
Firebase Authentication accounts and `role: 'admin'` custom claim.

## One-time deployment setup

1. Create the Firestore database in **asia-south1 (Mumbai)**. This location is
   permanent once selected.
2. Enable **Anonymous** sign-in in Firebase Authentication for collector phone
   installations. Enable an administrator sign-in provider separately (Email/
   Password is adequate for the pilot, with administrator accounts provisioned
   out of band).
3. Bootstrap the first administrator only from a trusted machine or CI job:
   set its Auth custom claim to `{ role: 'admin' }`. Do not put a service-account
   key in this repository or in the mobile app.
4. Install dependencies in this directory and deploy from the repository root:

   ```powershell
   npm --prefix functions install
   firebase deploy --only functions,firestore
   ```

5. Confirm the deployed callables are in `asia-south1` and test one code claim
   with a test device before entering real records.

## Callable contracts

All functions are callable HTTPS Functions in `asia-south1`.

| Callable | Caller | Request | Result |
| --- | --- | --- | --- |
| `createCollectorCode` | Admin | `{ displayName? }` | next sequential `{ collectorCode: "C001", displayName, state: "active" }` |
| `claimCollectorCode` | Anonymous phone | `{ collectorCode }` | binds first phone; then force-refresh the Auth token |
| `resetCollectorCodeBinding` | Admin | `{ collectorCode }` | disables old phone and makes the code claimable again |
| `setCollectorCodeState` | Admin | `{ collectorCode, state: "active" \| "revoked" }` | changes code status; revocation disables its current phone |
| `lookupStudyParticipant` | Bound collector | `{ studyId, query: { participantCode } }` or `{ studyId, query: { indianPhone } }` | owned participant or `null` |
| `allocateStudyVisit` | Bound collector | `{ studyId, requestKey, participant: { name, indianPhone } }` | server participant/visit allocation; retry-safe |
| `submitAllocatedStudyVisit` | Bound collector | `{ studyId, visitId, idempotencyKey, visit }` | completes a reserved visit; retry-safe |
| `createStudyVisit` | Bound collector | contract below | allocated IDs/numbers; replayed retries return the same result |
| `updateStudyRecord` | Admin | `{ studyId, collection, recordId, expectedRevision, changes }` | saves allowed edits or returns `aborted` for a stale revision |
| `setStudyRecordArchived` | Admin | `{ studyId, collection, recordId, archived }` | reversibly archives/restores a record |

`claimCollectorCode` must be called after `signInAnonymously()`. On a successful
claim the app must call `getIdToken(true)` before reading or submitting data.
The first active phone wins. A replacement phone requires an administrator
`resetCollectorCodeBinding` first.

### `createStudyVisit` request

```json
{
  "studyId": "pilot-2026",
  "idempotencyKey": "a-new-random-uuid-or-other-16-character-key",
  "participant": {
    "mode": "new",
    "profile": { "...": "participant fields" },
    "metadata": { "schemaVersion": 1 }
  },
  "visit": {
    "visitDate": "Firebase Timestamp",
    "submittedAt": "Firebase Timestamp",
    "questionnaire": { "...": "custom NCD questionnaire payload" },
    "stepTwoMeasurement": { "...": "questionnaire payload" },
    "confirmation": { "...": "submission metadata" },
    "metadata": { "schemaVersion": 1 }
  }
}
```

For a repeat visit, replace `participant` with:

```json
{ "mode": "existing", "participantId": "the-existing-Firestore-document-id" }
```

The response is always:

```json
{
  "participantId": "...",
  "participantCode": "P001",
  "visitId": "...",
  "visitNumber": 1,
  "replayed": false
}
```

The backend creates participant codes as `P001…` and allocates a visit number
from the participant's internal `nextVisitNumber` counter inside the same
Firestore transaction. Reuse the **same** idempotency key until a definitive
response is received; this prevents duplicate visits after a timeout or offline
retry.

## Data and retention behavior

- `collectorCodes/{code}` holds display name, state, and one bound anonymous
  Auth UID. It is readable only by administrators.
- Study records live at `/studies/{studyId}/participants/{participantId}` and
  `/studies/{studyId}/visits/{visitId}`. Bound collectors can read only records
  tagged with their own code; administrators can read all records.
- `/studies/{studyId}/ingestion/*` and counter documents are internal state and
  are not client-readable.
- Every collector-code action, record creation, admin edit, archive, and restore
  appends `/auditEvents/{eventId}`. These are admin-readable and client-immutable.
- There is no delete callable and Firestore Rules grant no delete permission.
- Physical consent remains outside the app and is not represented in the cloud
  data model.

## Current integration boundary

The collector production runtime now initializes Firebase Auth, Functions, and
Firestore from validated `--dart-define` values. It claims collector numbers,
allocates participant/visit numbers before data entry, stores submissions on the
phone, and retries uploads idempotently. Local demo mode remains a separate
build-time option. The admin Firebase account and visit repositories still need
to replace the local adapters before the hosted admin portal is production-ready.
