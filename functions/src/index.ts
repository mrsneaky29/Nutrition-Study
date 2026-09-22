import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { createHash } from "node:crypto";

admin.initializeApp();
const db = admin.firestore();
const REGION = "asia-south1";
const CODE_PATTERN = /^C[0-9]{3,}$/;
const IDEMPOTENCY_PATTERN = /^[A-Za-z0-9_-]{16,128}$/;

type AuthCaller = { uid: string; token: { role?: unknown; collectorCode?: unknown; firebase?: { sign_in_provider?: unknown } } };
type CollectionName = "participants" | "visits";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function exact(value: unknown, required: readonly string[], optional: readonly string[] = []): Record<string, unknown> {
  if (!isRecord(value)) throw new HttpsError("invalid-argument", "Request data must be an object.");
  const allowed = new Set([...required, ...optional]);
  if (Object.keys(value).some((key) => !allowed.has(key)) || required.some((key) => !(key in value))) {
    throw new HttpsError("invalid-argument", "Request contains unsupported or missing fields.");
  }
  return value;
}

function text(value: unknown, field: string, max = 128): string {
  if (typeof value !== "string") throw new HttpsError("invalid-argument", `${field} must be text.`);
  const result = value.trim();
  if (!result || result.length > max) throw new HttpsError("invalid-argument", `${field} must be 1-${max} characters.`);
  return result;
}

function docId(value: unknown, field: string): string {
  const result = text(value, field);
  if (result.includes("/")) throw new HttpsError("invalid-argument", `${field} must be a document ID.`);
  return result;
}

function collectorCode(value: unknown): string {
  const result = text(value, "collectorCode", 16).toUpperCase();
  if (!CODE_PATTERN.test(result)) throw new HttpsError("invalid-argument", "collectorCode must use the C001 format.");
  return result;
}

function positiveInteger(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 1) {
    throw new HttpsError("invalid-argument", `${field} must be a positive integer.`);
  }
  return value;
}

function requireAdmin(auth: AuthCaller | undefined): string {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in is required.");
  if (auth.token.role !== "admin") throw new HttpsError("permission-denied", "An admin role is required.");
  return auth.uid;
}

function requireAnonymous(auth: AuthCaller | undefined): string {
  if (!auth) throw new HttpsError("unauthenticated", "Anonymous sign-in is required before claiming a code.");
  if (auth.token.firebase?.sign_in_provider !== "anonymous") {
    throw new HttpsError("permission-denied", "Only an anonymous app installation can claim a collector code.");
  }
  return auth.uid;
}

async function requireCollector(auth: AuthCaller | undefined): Promise<{ uid: string; code: string }> {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in is required.");
  const code = typeof auth.token.collectorCode === "string" ? auth.token.collectorCode : "";
  if (auth.token.role !== "collector" || !CODE_PATTERN.test(code)) {
    throw new HttpsError("permission-denied", "This device is not bound to an active collector code.");
  }
  const snapshot = await db.collection("collectorCodes").doc(code).get();
  if (!snapshot.exists || snapshot.data()?.state !== "active" || snapshot.data()?.boundUid !== auth.uid) {
    throw new HttpsError("permission-denied", "This collector-code binding is inactive or belongs to another phone.");
  }
  return { uid: auth.uid, code };
}

function timestamp(value: unknown, field: string): admin.firestore.Timestamp {
  if (value === undefined) return admin.firestore.Timestamp.now();
  if (value instanceof admin.firestore.Timestamp) return value;
  if (value instanceof Date && !Number.isNaN(value.getTime())) return admin.firestore.Timestamp.fromDate(value);
  throw new HttpsError("invalid-argument", `${field} must be a Firebase timestamp.`);
}

function nextRevision(data: admin.firestore.DocumentData | undefined): number {
  return typeof data?.revision === "number" && Number.isSafeInteger(data.revision) && data.revision >= 1 ? data.revision + 1 : 1;
}

function recordCollection(value: unknown): CollectionName {
  if (value !== "participants" && value !== "visits") {
    throw new HttpsError("invalid-argument", "collection must be participants or visits.");
  }
  return value;
}

function editableChanges(collection: CollectionName, value: unknown): Record<string, unknown> {
  if (!isRecord(value) || Object.keys(value).length === 0) {
    throw new HttpsError("invalid-argument", "changes must be a non-empty object.");
  }
  const allowed = collection === "participants"
    ? new Set(["profile", "metadata"])
    : new Set(["visitDate", "status", "reviewState", "questionnaire", "stepTwoMeasurement", "confirmation", "submittedAt", "syncState", "metadata"]);
  if (Object.keys(value).some((key) => !allowed.has(key))) {
    throw new HttpsError("invalid-argument", "changes contains protected or unsupported fields.");
  }
  for (const key of ["profile", "metadata", "questionnaire", "stepTwoMeasurement", "confirmation"]) {
    if (key in value && !isRecord(value[key])) throw new HttpsError("invalid-argument", `${key} must be an object.`);
  }
  for (const key of ["status", "reviewState", "syncState"]) if (key in value) text(value[key], key, 64);
  for (const key of ["visitDate", "submittedAt"]) if (key in value) timestamp(value[key], key);
  return value;
}

/** Administrator-only creation of the next unused code (C001, C002, ...). */
export const createCollectorCode = onCall({ region: REGION }, async (request) => {
  const createdBy = requireAdmin(request.auth);
  const raw = exact(request.data, [], ["displayName"]);
  const displayName = typeof raw.displayName === "string" && raw.displayName.trim()
    ? text(raw.displayName, "displayName", 120)
    : null;
  const sequence = db.collection("system").doc("collectorCodeSequence");
  let code = "";
  await db.runTransaction(async (tx) => {
    const current = await tx.get(sequence);
    const last = typeof current.data()?.lastNumber === "number" ? current.data()!.lastNumber as number : 0;
    const number = last + 1;
    code = `C${String(number).padStart(3, "0")}`;
    tx.set(sequence, { lastNumber: number, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    tx.create(db.collection("collectorCodes").doc(code), {
      collectorCode: code, ...(displayName ? { displayName } : {}), state: "active", createdBy,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.create(db.collection("auditEvents").doc(), {
      eventType: "collectorCode.created", actorUid: createdBy, actorRole: "admin", collectorCode: code,
      displayName, occurredAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return { collectorCode: code, displayName, state: "active" };
});

/** First anonymous app installation to claim a code becomes its bound phone. */
export const claimCollectorCode = onCall({ region: REGION }, async (request) => {
  const uid = requireAnonymous(request.auth);
  const raw = exact(request.data, ["collectorCode"]);
  const code = collectorCode(raw.collectorCode);
  const ref = db.collection("collectorCodes").doc(code);
  try {
    await db.runTransaction(async (tx) => {
      const current = await tx.get(ref);
      const data = current.data();
      if (!current.exists || data?.state !== "active") throw new HttpsError("not-found", "Collector code is unavailable.");
      if (data.boundUid && data.boundUid !== uid) {
        throw new HttpsError("already-exists", "This collector code is already bound to another phone.");
      }
      if (!data.boundUid) {
        tx.update(ref, { boundUid: uid, boundAt: admin.firestore.FieldValue.serverTimestamp(), updatedAt: admin.firestore.FieldValue.serverTimestamp() });
        tx.create(db.collection("auditEvents").doc(), {
          eventType: "collectorCode.claimed", actorUid: uid, actorRole: "collector", collectorCode: code,
          occurredAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    });
    await admin.auth().setCustomUserClaims(uid, { role: "collector", collectorCode: code });
    return { collectorCode: code, tokenRefreshRequired: true };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error("Collector code claim failed", error);
    throw new HttpsError("internal", "Collector code could not be claimed.");
  }
});

/** Unbinds a lost/replaced phone. The old Firebase installation is disabled. */
export const resetCollectorCodeBinding = onCall({ region: REGION }, async (request) => {
  const resetBy = requireAdmin(request.auth);
  const code = collectorCode(exact(request.data, ["collectorCode"]).collectorCode);
  const ref = db.collection("collectorCodes").doc(code);
  let oldUid: string | undefined;
  await db.runTransaction(async (tx) => {
    const current = await tx.get(ref);
    if (!current.exists) throw new HttpsError("not-found", "Collector code was not found.");
    oldUid = typeof current.data()?.boundUid === "string" ? current.data()!.boundUid as string : undefined;
    tx.update(ref, {
      state: "active", boundUid: admin.firestore.FieldValue.delete(), boundAt: admin.firestore.FieldValue.delete(),
      resetAt: admin.firestore.FieldValue.serverTimestamp(), resetBy, updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.create(db.collection("auditEvents").doc(), {
      eventType: "collectorCode.bindingReset", actorUid: resetBy, actorRole: "admin", collectorCode: code,
      previousUid: oldUid ?? null, occurredAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  if (oldUid) {
    await Promise.all([
      admin.auth().revokeRefreshTokens(oldUid).catch(() => undefined),
      admin.auth().updateUser(oldUid, { disabled: true }).catch(() => undefined),
    ]);
  }
  return { collectorCode: code, state: "active", bindingReset: true };
});

/** Revocation disables the bound phone; reactivation does not restore old access. */
export const setCollectorCodeState = onCall({ region: REGION }, async (request) => {
  const changedBy = requireAdmin(request.auth);
  const raw = exact(request.data, ["collectorCode", "state"]);
  const code = collectorCode(raw.collectorCode);
  if (raw.state !== "active" && raw.state !== "revoked") throw new HttpsError("invalid-argument", "state must be active or revoked.");
  const state = raw.state;
  const ref = db.collection("collectorCodes").doc(code);
  let boundUid: string | undefined;
  await db.runTransaction(async (tx) => {
    const current = await tx.get(ref);
    if (!current.exists) throw new HttpsError("not-found", "Collector code was not found.");
    boundUid = typeof current.data()?.boundUid === "string" ? current.data()!.boundUid as string : undefined;
    tx.update(ref, {
      state, updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(state === "revoked" ? { revokedAt: admin.firestore.FieldValue.serverTimestamp(), revokedBy: changedBy } : { revokedAt: admin.firestore.FieldValue.delete(), revokedBy: admin.firestore.FieldValue.delete() }),
    });
    tx.create(db.collection("auditEvents").doc(), {
      eventType: `collectorCode.${state}`, actorUid: changedBy, actorRole: "admin", collectorCode: code,
      occurredAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  if (state === "revoked" && boundUid) {
    await Promise.all([
      admin.auth().revokeRefreshTokens(boundUid).catch(() => undefined),
      admin.auth().updateUser(boundUid, { disabled: true }).catch(() => undefined),
    ]);
  }
  return { collectorCode: code, state };
});

function visitPayload(value: unknown): Record<string, unknown> {
  const raw = exact(value, ["questionnaire", "confirmation"], ["visitDate", "status", "reviewState", "stepTwoMeasurement", "submittedAt", "syncState", "metadata"]);
  if (!isRecord(raw.questionnaire)) throw new HttpsError("invalid-argument", "questionnaire must be an object.");
  if (!isRecord(raw.confirmation)) throw new HttpsError("invalid-argument", "confirmation must be an object.");
  return editableChanges("visits", raw);
}

function participantProfile(value: unknown): Record<string, unknown> {
  const profile = exact(value, ["name", "indianPhone"]);
  return {
    name: text(profile.name, "participant.profile.name", 160),
    indianPhone: text(profile.indianPhone, "participant.profile.indianPhone", 16),
  };
}

function participantRefForPhone(
  study: admin.firestore.DocumentReference,
  collector: string,
  indianPhone: string,
): admin.firestore.DocumentReference {
  const digest = createHash("sha256").update(indianPhone).digest("hex").slice(0, 40);
  return study.collection("participants").doc(`${collector.toLowerCase()}_${digest}`);
}

function validateConfirmation(
  value: unknown,
  profile: Record<string, unknown>,
  visitNumber: number,
): Record<string, unknown> {
  const confirmation = exact(value, ["name", "indianPhone", "visitNumber", "confirmedAt"]);
  const name = text(confirmation.name, "visit.confirmation.name", 160);
  const indianPhone = text(confirmation.indianPhone, "visit.confirmation.indianPhone", 16);
  const confirmedVisitNumber = positiveInteger(confirmation.visitNumber, "visit.confirmation.visitNumber");
  if (name !== profile.name || indianPhone !== profile.indianPhone || confirmedVisitNumber !== visitNumber) {
    throw new HttpsError("failed-precondition", "Confirmation does not match the server-assigned participant and visit.");
  }
  return {
    name,
    indianPhone,
    visitNumber: confirmedVisitNumber,
    confirmedAt: timestamp(confirmation.confirmedAt, "visit.confirmation.confirmedAt"),
  };
}

/** Resolves a participant owned by the signed-in collector. */
export const lookupStudyParticipant = onCall({ region: REGION }, async (request) => {
  const caller = await requireCollector(request.auth);
  const raw = exact(request.data, ["studyId", "query"]);
  const studyId = docId(raw.studyId, "studyId");
  const query = exact(raw.query, [], ["participantCode", "indianPhone"]);
  const hasCode = "participantCode" in query;
  const hasPhone = "indianPhone" in query;
  if (hasCode === hasPhone) throw new HttpsError("invalid-argument", "Supply exactly one participant lookup value.");
  const study = db.collection("studies").doc(studyId);
  let snapshot: admin.firestore.DocumentSnapshot;
  if (hasPhone) {
    const phone = text(query.indianPhone, "query.indianPhone", 16);
    snapshot = await participantRefForPhone(study, caller.code, phone).get();
  } else {
    const code = text(query.participantCode, "query.participantCode", 32).toUpperCase();
    const matches = await study.collection("participants")
      .where("collectorId", "==", caller.code)
      .where("participantCode", "==", code)
      .limit(1)
      .get();
    if (matches.empty) return { participant: null };
    snapshot = matches.docs[0];
  }
  const data = snapshot.data();
  if (!snapshot.exists || data?.collectorId !== caller.code || data.archivedAt || !isRecord(data.profile)) {
    return { participant: null };
  }
  return {
    participant: {
      participantId: snapshot.id,
      participantCode: data.participantCode,
      profile: participantProfile(data.profile),
      nextVisitNumber: positiveInteger(data.nextVisitNumber, "participant.nextVisitNumber"),
    },
  };
});

/**
 * Allocates the server participant and visit numbers before data entry. The
 * durable request key makes retries return the same reservation.
 */
export const allocateStudyVisit = onCall({ region: REGION }, async (request) => {
  const caller = await requireCollector(request.auth);
  const raw = exact(request.data, ["studyId", "requestKey", "participant"]);
  const studyId = docId(raw.studyId, "studyId");
  const requestKey = text(raw.requestKey, "requestKey", 128);
  if (!IDEMPOTENCY_PATTERN.test(requestKey)) throw new HttpsError("invalid-argument", "requestKey must be 16-128 URL-safe characters.");
  const suppliedProfile = participantProfile(raw.participant);
  const phone = suppliedProfile.indianPhone as string;
  const study = db.collection("studies").doc(studyId);
  const reservation = study.collection("allocations").doc(`${caller.uid}_${requestKey}`);
  const participant = participantRefForPhone(study, caller.code, phone);
  const participantSequence = study.collection("system").doc("participantSequence");
  const visit = study.collection("visits").doc();
  let result: Record<string, unknown> | undefined;
  await db.runTransaction(async (tx) => {
    const saved = await tx.get(reservation);
    if (saved.exists) {
      const data = saved.data();
      if (data?.collectorId !== caller.code || typeof data.participantId !== "string" || typeof data.participantCode !== "string" || typeof data.visitId !== "string" || typeof data.visitNumber !== "number" || !isRecord(data.profile)) {
        throw new HttpsError("failed-precondition", "Previous visit allocation cannot be replayed safely.");
      }
      result = { participantId: data.participantId, participantCode: data.participantCode, visitId: data.visitId, visitNumber: data.visitNumber, profile: data.profile, replayed: true };
      return;
    }
    const existing = await tx.get(participant);
    let participantCode: string;
    let profile: Record<string, unknown>;
    let visitNumber: number;
    if (existing.exists) {
      const data = existing.data();
      if (data?.collectorId !== caller.code || data.archivedAt || typeof data.participantCode !== "string" || !isRecord(data.profile)) {
        throw new HttpsError("failed-precondition", "The phone number is linked to an unavailable participant.");
      }
      participantCode = data.participantCode;
      profile = participantProfile(data.profile);
      visitNumber = positiveInteger(data.nextVisitNumber, "participant.nextVisitNumber");
      tx.update(participant, { nextVisitNumber: visitNumber + 1, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    } else {
      const counter = await tx.get(participantSequence);
      const next = (typeof counter.data()?.lastNumber === "number" ? counter.data()!.lastNumber as number : 0) + 1;
      participantCode = `P${String(next).padStart(3, "0")}`;
      profile = suppliedProfile;
      visitNumber = 1;
      tx.set(participantSequence, { lastNumber: next, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
      tx.create(participant, {
        studyId, collectorId: caller.code, createdBy: caller.uid, participantCode, profile,
        nextVisitNumber: 2, createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(), revision: 1,
      });
    }
    tx.create(visit, {
      studyId, participantId: participant.id, participantCode, visitNumber,
      collectorId: caller.code, createdBy: caller.uid, status: "reserved",
      syncState: "pending", reviewState: "pending", revision: 1,
      createdAt: admin.firestore.FieldValue.serverTimestamp(), updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.create(reservation, {
      collectorId: caller.code, participantId: participant.id, participantCode,
      visitId: visit.id, visitNumber, profile, createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.create(db.collection("auditEvents").doc(), {
      eventType: "visit.allocated", actorUid: caller.uid, actorRole: "collector", collectorCode: caller.code,
      studyId, participantId: participant.id, participantCode, visitId: visit.id, visitNumber,
      occurredAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    result = { participantId: participant.id, participantCode, visitId: visit.id, visitNumber, profile, replayed: false };
  });
  if (!result) throw new HttpsError("internal", "Visit allocation produced no result.");
  return result;
});

/** Completes one server allocation; repeated upload keys are idempotent. */
export const submitAllocatedStudyVisit = onCall({ region: REGION }, async (request) => {
  const caller = await requireCollector(request.auth);
  const raw = exact(request.data, ["studyId", "visitId", "idempotencyKey", "visit"]);
  const studyId = docId(raw.studyId, "studyId");
  const visitId = docId(raw.visitId, "visitId");
  const idempotencyKey = text(raw.idempotencyKey, "idempotencyKey", 128);
  if (!IDEMPOTENCY_PATTERN.test(idempotencyKey)) throw new HttpsError("invalid-argument", "idempotencyKey must be 16-128 URL-safe characters.");
  const payload = visitPayload(raw.visit);
  const study = db.collection("studies").doc(studyId);
  const visit = study.collection("visits").doc(visitId);
  const replay = study.collection("ingestion").doc(`${caller.uid}_${idempotencyKey}`);
  let replayed = false;
  await db.runTransaction(async (tx) => {
    const saved = await tx.get(replay);
    if (saved.exists) {
      if (saved.data()?.visitId !== visitId || saved.data()?.collectorId !== caller.code) {
        throw new HttpsError("already-exists", "This upload key belongs to another visit.");
      }
      replayed = true;
      return;
    }
    const current = await tx.get(visit);
    const data = current.data();
    if (!current.exists || data?.collectorId !== caller.code || typeof data.participantId !== "string" || typeof data.visitNumber !== "number") {
      throw new HttpsError("not-found", "The allocated visit was not found.");
    }
    if (data.status === "submitted") throw new HttpsError("already-exists", "This visit was already submitted with another upload key.");
    const participant = await tx.get(study.collection("participants").doc(data.participantId));
    const participantData = participant.data();
    if (!participant.exists || !isRecord(participantData?.profile)) throw new HttpsError("failed-precondition", "Participant profile is unavailable.");
    const confirmation = validateConfirmation(payload.confirmation, participantProfile(participantData.profile), data.visitNumber);
    tx.update(visit, {
      visitDate: timestamp(payload.visitDate, "visitDate"), submittedAt: timestamp(payload.submittedAt, "submittedAt"),
      status: "submitted", reviewState: payload.reviewState ?? "pending", syncState: "synced",
      questionnaire: payload.questionnaire, confirmation,
      ...(payload.stepTwoMeasurement ? { stepTwoMeasurement: payload.stepTwoMeasurement } : {}),
      ...(payload.metadata ? { metadata: payload.metadata } : {}),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(), revision: nextRevision(data),
    });
    tx.create(replay, { collectorId: caller.code, visitId, createdAt: admin.firestore.FieldValue.serverTimestamp() });
    tx.create(db.collection("auditEvents").doc(), {
      eventType: "visit.submitted", actorUid: caller.uid, actorRole: "collector", collectorCode: caller.code,
      studyId, participantId: data.participantId, participantCode: data.participantCode, visitId, visitNumber: data.visitNumber,
      occurredAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return { visitId, replayed };
});

/**
 * Transactional insert for new/repeat visits. An idempotency key is stored with
 * the result so network retries return the original IDs instead of duplicating.
 */
export const createStudyVisit = onCall({ region: REGION }, async (request) => {
  const caller = await requireCollector(request.auth);
  const raw = exact(request.data, ["studyId", "idempotencyKey", "participant", "visit"]);
  const studyId = docId(raw.studyId, "studyId");
  const idempotencyKey = text(raw.idempotencyKey, "idempotencyKey", 128);
  if (!IDEMPOTENCY_PATTERN.test(idempotencyKey)) throw new HttpsError("invalid-argument", "idempotencyKey must be 16-128 URL-safe characters.");
  const participantRaw = exact(raw.participant, ["mode"], ["profile", "metadata", "participantId"]);
  const isNew = participantRaw.mode === "new";
  const isExisting = participantRaw.mode === "existing";
  if (!isNew && !isExisting) throw new HttpsError("invalid-argument", "participant.mode must be new or existing.");
  if (isNew && (!isRecord(participantRaw.profile) || ("metadata" in participantRaw && !isRecord(participantRaw.metadata)) || "participantId" in participantRaw)) {
    throw new HttpsError("invalid-argument", "A new participant requires profile and optional metadata only.");
  }
  if (isExisting && (!("participantId" in participantRaw) || "profile" in participantRaw || "metadata" in participantRaw)) {
    throw new HttpsError("invalid-argument", "An existing participant requires participantId only.");
  }
  const visit = visitPayload(raw.visit);
  const study = db.collection("studies").doc(studyId);
  const replay = study.collection("ingestion").doc(`${caller.uid}_${idempotencyKey}`);
  const sequence = study.collection("system").doc("participantSequence");
  let response: { participantId: string; participantCode: string; visitId: string; visitNumber: number; replayed: boolean } | undefined;
  try {
    await db.runTransaction(async (tx) => {
      const saved = await tx.get(replay);
      if (saved.exists) {
        const data = saved.data();
        if (data?.collectorId !== caller.code || typeof data?.participantId !== "string" || typeof data.participantCode !== "string" || typeof data.visitId !== "string" || typeof data.visitNumber !== "number") {
          throw new HttpsError("failed-precondition", "Previous submission cannot be safely replayed.");
        }
        response = { participantId: data.participantId, participantCode: data.participantCode, visitId: data.visitId, visitNumber: data.visitNumber, replayed: true };
        return;
      }
      let participantRef: admin.firestore.DocumentReference;
      let participantCode: string;
      let visitNumber: number;
      let profile: Record<string, unknown>;
      if (isExisting) {
        participantRef = study.collection("participants").doc(docId(participantRaw.participantId, "participantId"));
        const existing = await tx.get(participantRef);
        const data = existing.data();
        if (!existing.exists || data?.collectorId !== caller.code || data.archivedAt || typeof data.participantCode !== "string") {
          throw new HttpsError("not-found", "Participant was not found for this collector.");
        }
        participantCode = data.participantCode;
        if (!isRecord(data.profile)) throw new HttpsError("failed-precondition", "Participant profile is unavailable.");
        profile = participantProfile(data.profile);
        visitNumber = typeof data.nextVisitNumber === "number" && Number.isSafeInteger(data.nextVisitNumber) && data.nextVisitNumber >= 1
          ? data.nextVisitNumber
          : 1;
        tx.update(participantRef, { nextVisitNumber: visitNumber + 1, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
      } else {
        profile = participantProfile(participantRaw.profile);
        const counter = await tx.get(sequence);
        const next = (typeof counter.data()?.lastNumber === "number" ? counter.data()!.lastNumber as number : 0) + 1;
        participantCode = `P${String(next).padStart(3, "0")}`;
        participantRef = study.collection("participants").doc();
        tx.set(sequence, { lastNumber: next, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
        tx.create(participantRef, {
          studyId, collectorId: caller.code, createdBy: caller.uid, participantCode,
          profile, ...(isRecord(participantRaw.metadata) ? { metadata: participantRaw.metadata } : {}),
          nextVisitNumber: 2, createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(), revision: 1,
        });
        visitNumber = 1;
      }
      const confirmation = validateConfirmation(visit.confirmation, profile, visitNumber);
      const visitRef = study.collection("visits").doc();
      tx.create(visitRef, {
        studyId, participantId: participantRef.id, participantCode, visitNumber,
        collectorId: caller.code, createdBy: caller.uid,
        visitDate: timestamp(visit.visitDate, "visitDate"), submittedAt: timestamp(visit.submittedAt, "submittedAt"),
        status: visit.status ?? "submitted", reviewState: visit.reviewState ?? "unreviewed", syncState: "synced",
        ...(visit.questionnaire ? { questionnaire: visit.questionnaire } : {}),
        ...(visit.stepTwoMeasurement ? { stepTwoMeasurement: visit.stepTwoMeasurement } : {}),
        confirmation, ...(visit.metadata ? { metadata: visit.metadata } : {}),
        createdAt: admin.firestore.FieldValue.serverTimestamp(), updatedAt: admin.firestore.FieldValue.serverTimestamp(), revision: 1,
      });
      tx.create(replay, {
        collectorId: caller.code, createdBy: caller.uid, participantId: participantRef.id, participantCode,
        visitId: visitRef.id, visitNumber, createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.create(db.collection("auditEvents").doc(), {
        eventType: "visit.created", actorUid: caller.uid, actorRole: "collector", collectorCode: caller.code,
        studyId, participantId: participantRef.id, participantCode, visitId: visitRef.id, visitNumber,
        occurredAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      response = { participantId: participantRef.id, participantCode, visitId: visitRef.id, visitNumber, replayed: false };
    });
    if (!response) throw new HttpsError("internal", "Visit submission produced no result.");
    return response;
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error("Study visit creation failed", error);
    throw new HttpsError("internal", "Visit could not be saved.");
  }
});

/** Archive/restore only: there is deliberately no delete callable. */
export const setStudyRecordArchived = onCall({ region: REGION }, async (request) => {
  const actor = requireAdmin(request.auth);
  const raw = exact(request.data, ["studyId", "collection", "recordId", "archived"]);
  if (typeof raw.archived !== "boolean") throw new HttpsError("invalid-argument", "archived must be true or false.");
  const studyId = docId(raw.studyId, "studyId");
  const collection = recordCollection(raw.collection);
  const recordId = docId(raw.recordId, "recordId");
  const record = db.collection("studies").doc(studyId).collection(collection).doc(recordId);
  try {
    await db.runTransaction(async (tx) => {
      const old = await tx.get(record);
      if (!old.exists) throw new HttpsError("not-found", "Study record was not found.");
      tx.update(record, raw.archived ? {
        archivedAt: admin.firestore.FieldValue.serverTimestamp(), archivedBy: actor,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(), revision: nextRevision(old.data()),
      } : {
        archivedAt: admin.firestore.FieldValue.delete(), archivedBy: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(), revision: nextRevision(old.data()),
      });
      tx.create(db.collection("auditEvents").doc(), {
        eventType: raw.archived ? "studyRecord.archived" : "studyRecord.restored", actorUid: actor, actorRole: "admin",
        studyId, collection, recordId, previousRevision: old.data()?.revision ?? null,
        occurredAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
    return { studyId, collection, recordId, archived: raw.archived };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error("Archive operation failed", error);
    throw new HttpsError("internal", "Study record could not be archived or restored.");
  }
});

/** Full content edit for administrators with optimistic revision checking and audit history. */
export const updateStudyRecord = onCall({ region: REGION }, async (request) => {
  const actor = requireAdmin(request.auth);
  const raw = exact(request.data, ["studyId", "collection", "recordId", "expectedRevision", "changes"]);
  const studyId = docId(raw.studyId, "studyId");
  const collection = recordCollection(raw.collection);
  const recordId = docId(raw.recordId, "recordId");
  const expectedRevision = positiveInteger(raw.expectedRevision, "expectedRevision");
  const changes = editableChanges(collection, raw.changes);
  const record = db.collection("studies").doc(studyId).collection(collection).doc(recordId);
  try {
    await db.runTransaction(async (tx) => {
      const old = await tx.get(record);
      const data = old.data();
      if (!old.exists || data?.studyId !== studyId) throw new HttpsError("not-found", "Study record was not found.");
      const currentRevision = typeof data.revision === "number" ? data.revision : 1;
      if (currentRevision !== expectedRevision) throw new HttpsError("aborted", "Record changed elsewhere. Refresh it before saving.");
      tx.update(record, { ...changes, updatedAt: admin.firestore.FieldValue.serverTimestamp(), revision: currentRevision + 1 });
      tx.create(db.collection("auditEvents").doc(), {
        eventType: "studyRecord.updated", actorUid: actor, actorRole: "admin", studyId, collection, recordId,
        previousRevision: currentRevision, newRevision: currentRevision + 1, changedFields: Object.keys(changes),
        before: Object.fromEntries(Object.keys(changes).map((key) => [key, data[key] ?? null])), after: changes,
        occurredAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
    return { studyId, collection, recordId, updated: Object.keys(changes) };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error("Study record update failed", error);
    throw new HttpsError("internal", "Study record could not be updated.");
  }
});
