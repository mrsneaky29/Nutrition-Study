/// Boundary for optionally mirroring locally collected records to a LAN service.
///
/// The collector UI depends on this interface rather than HTTP so the local
/// service can be removed or replaced without changing the collection flow.
abstract interface class LocalRecordSyncGateway {
  Future<LocalRecordSyncResult> sendRecord(Map<String, Object?> record);
  Future<ParticipantLookupResult> lookupParticipant(String phone);
}

/// A distinct Study ID returned for a phone that may be shared by a household.
class ParticipantLookupCandidate {
  const ParticipantLookupCandidate({
    required this.studyId,
    required this.name,
    required this.nextVisitNumber,
  });

  final String studyId;
  final String name;
  final int nextVisitNumber;
}

/// Result of an online participant lookup.
class ParticipantLookupResult {
  const ParticipantLookupResult({
    required this.found,
    this.studyId,
    this.name,
    this.nextVisitNumber,
    this.isOffline = false,
    this.isAmbiguous = false,
    this.candidates = const [],
  });

  const ParticipantLookupResult.found({
    this.studyId,
    this.name,
    this.nextVisitNumber,
  })  : found = true,
        isOffline = false,
        isAmbiguous = false,
        candidates = const [];

  const ParticipantLookupResult.ambiguous(this.candidates)
      : found = true,
        studyId = null,
        name = null,
        nextVisitNumber = null,
        isOffline = false,
        isAmbiguous = true;

  const ParticipantLookupResult.notFound()
      : found = false,
        studyId = null,
        name = null,
        nextVisitNumber = null,
        isOffline = false,
        isAmbiguous = false,
        candidates = const [];

  const ParticipantLookupResult.offline()
      : found = false,
        studyId = null,
        name = null,
        nextVisitNumber = null,
        isOffline = true,
        isAmbiguous = false,
        candidates = const [];

  final bool found;
  final String? studyId;
  final String? name;
  final int? nextVisitNumber;
  final bool isOffline;
  final bool isAmbiguous;
  final List<ParticipantLookupCandidate> candidates;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParticipantLookupResult &&
          runtimeType == other.runtimeType &&
          found == other.found &&
          studyId == other.studyId &&
          name == other.name &&
          nextVisitNumber == other.nextVisitNumber &&
          isOffline == other.isOffline &&
          isAmbiguous == other.isAmbiguous &&
          _sameCandidates(candidates, other.candidates);

  @override
  int get hashCode =>
      Object.hash(found, studyId, name, nextVisitNumber, isOffline,
          isAmbiguous, Object.hashAll(candidates.map((candidate) =>
              Object.hash(candidate.studyId, candidate.name,
                  candidate.nextVisitNumber))));

  static bool _sameCandidates(List<ParticipantLookupCandidate> a,
      List<ParticipantLookupCandidate> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].studyId != b[i].studyId || a[i].name != b[i].name ||
          a[i].nextVisitNumber != b[i].nextVisitNumber) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() =>
      'ParticipantLookupResult(found: $found, studyId: $studyId, name: $name, nextVisitNumber: $nextVisitNumber, isOffline: $isOffline, isAmbiguous: $isAmbiguous)';
}

/// Status outcomes of a local record synchronization attempt.
enum LocalRecordSyncResult {
  synced,
  pending,
  failed,
  conflict;

  bool get isSynced => this == LocalRecordSyncResult.synced;
  bool get isPending => this == LocalRecordSyncResult.pending;
  bool get isFailed => this == LocalRecordSyncResult.failed;
  bool get isConflict => this == LocalRecordSyncResult.conflict;

  /// Convenience helper to create a [SyncResponse] representing this result.
  SyncResponse toResponse({
    String? message,
    String? conflictType,
    String? conflictId,
    int? statusCode,
    Map<String, Object?>? body,
    String? rawBody,
  }) {
    return SyncResponse(
      result: this,
      message: message,
      conflictType: conflictType,
      conflictId: conflictId,
      statusCode: statusCode,
      body: body,
      rawBody: rawBody,
    );
  }
}

/// Detailed response object for local record synchronization attempts.
///
/// Preserves conflict details (such as [message] and [conflictType]),
/// HTTP [statusCode], decoded [body], and [rawBody] while remaining
/// fully backwards-compatible with [LocalRecordSyncResult].
class SyncResponse {
  const SyncResponse({
    required this.result,
    this.message,
    this.conflictType,
    this.conflictId,
    this.statusCode,
    this.body,
    this.rawBody,
  });

  const SyncResponse.synced({
    this.message,
    this.statusCode = 200,
    this.body,
    this.rawBody,
  }) : result = LocalRecordSyncResult.synced,
       conflictType = null,
       conflictId = null;

  const SyncResponse.pending({
    this.message,
    this.statusCode,
    this.body,
    this.rawBody,
  }) : result = LocalRecordSyncResult.pending,
       conflictType = null,
       conflictId = null;

  const SyncResponse.failed({
    this.message,
    this.statusCode,
    this.body,
    this.rawBody,
  }) : result = LocalRecordSyncResult.failed,
       conflictType = null,
       conflictId = null;

  const SyncResponse.conflict({
    this.message,
    this.conflictType,
    this.conflictId,
    this.statusCode = 409,
    this.body,
    this.rawBody,
  }) : result = LocalRecordSyncResult.conflict;

  final LocalRecordSyncResult result;
  final String? message;
  final String? conflictType;
  final String? conflictId;
  final int? statusCode;
  final Map<String, Object?>? body;
  final String? rawBody;

  bool get isSynced => result == LocalRecordSyncResult.synced;
  bool get isPending => result == LocalRecordSyncResult.pending;
  bool get isFailed => result == LocalRecordSyncResult.failed;
  bool get isConflict => result == LocalRecordSyncResult.conflict;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncResponse &&
          runtimeType == other.runtimeType &&
          result == other.result &&
          message == other.message &&
          conflictType == other.conflictType &&
          conflictId == other.conflictId &&
          statusCode == other.statusCode &&
          rawBody == other.rawBody;

  @override
  int get hashCode =>
      Object.hash(result, message, conflictType, conflictId, statusCode, rawBody);

  @override
  String toString() =>
      'SyncResponse(result: $result, statusCode: $statusCode, message: $message, conflictType: $conflictType, conflictId: $conflictId)';
}

/// Backwards-compatible alias for [SyncResponse].
typedef LocalRecordSyncResponse = SyncResponse;
