import '../domain/authenticated_user.dart';
import '../domain/participant_profile.dart';
import '../domain/visit_record.dart';
import 'visit_repository.dart';

/// Dependency-free repository for local development and unit tests.
class InMemoryVisitRepository implements VisitRepository {
  final Map<String, VisitRecord> _records = {};
  int _nextId = 1;

  /// Inserts existing local records for demos, migration exercises, or tests.
  ///
  /// This is intentionally explicit rather than a production persistence layer;
  /// callers supply fully validated domain records and duplicate IDs are refused.
  void seed(Iterable<VisitRecord> records) {
    for (final record in records) {
      if (_records.containsKey(record.id)) {
        throw ArgumentError.value(record.id, 'records', 'Duplicate visit ID.');
      }
      _records[record.id] = record;
    }
  }

  @override
  Future<VisitRecord> createDraft({
    required AuthenticatedUser actor,
    required ParticipantProfile participant,
    DateTime? now,
  }) async {
    _requireCollector(actor);
    final timestamp = now ?? DateTime.now().toUtc();
    final nextVisitNumber =
        _records.values
            .where(
              (record) => record.participant.studyId == participant.studyId,
            )
            .map((record) => record.visitNumber)
            .fold(0, (highest, value) => value > highest ? value : highest) +
        1;
    final record = VisitRecord(
      id: _newId(),
      participant: participant,
      visitNumber: nextVisitNumber,
      collectorId: actor.id,
      createdAt: timestamp,
      updatedAt: timestamp,
      status: VisitStatus.draft,
      syncState: SyncState.localOnly,
      reviewState: NeutralReviewState.pending,
      revision: 1,
    );
    _records[record.id] = record;
    return record;
  }

  @override
  Future<VisitRecord?> getById(String id, AuthenticatedUser actor) async {
    final record = _records[id];
    if (record == null || !_canRead(actor, record)) return null;
    return record;
  }

  @override
  Future<List<VisitRecord>> listVisibleTo(AuthenticatedUser actor) async {
    final result =
        _records.values.where((record) => _canRead(actor, record)).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(result);
  }

  @override
  Future<VisitRecord> saveOwnRecord({
    required AuthenticatedUser actor,
    required VisitRecord record,
  }) async {
    _requireCollector(actor);
    final existing = _requireOwned(record.id, actor);
    if (existing.isArchived) {
      throw StateError(
        'Archived visits can only be changed by an administrator.',
      );
    }
    if (record.collectorId != existing.collectorId ||
        !_sameParticipant(record.participant, existing.participant) ||
        record.visitNumber != existing.visitNumber ||
        record.status != existing.status ||
        record.submittedAt != existing.submittedAt ||
        !_sameArchive(record.archiveMetadata, existing.archiveMetadata)) {
      throw ArgumentError(
        'An edit cannot change ownership, participant, visit number, status, submission time, or archive state.',
      );
    }
    if (record.isSubmitted && !record.isConfirmed) {
      throw StateError('A submitted visit must keep a valid confirmation.');
    }
    final saved = record.copyWith(
      syncState: record.isSubmitted ? SyncState.pending : SyncState.localOnly,
      updatedAt: DateTime.now().toUtc(),
      revision: existing.revision + 1,
    );
    _records[saved.id] = saved;
    return saved;
  }

  @override
  Future<VisitRecord> saveAdminRecord({
    required AuthenticatedUser actor,
    required VisitRecord record,
    DateTime? now,
  }) async {
    if (!actor.isAdmin) {
      throw StateError('Only administrators can edit study records.');
    }
    final existing = _records[record.id];
    if (existing == null) throw StateError('Visit does not exist.');
    if (record.collectorId != existing.collectorId ||
        record.createdAt != existing.createdAt ||
        record.participant.studyId != existing.participant.studyId ||
        !_sameArchive(record.archiveMetadata, existing.archiveMetadata)) {
      throw ArgumentError(
        'An admin edit cannot change ownership, creation time, participant ID, or archive state.',
      );
    }
    if (record.status == VisitStatus.submitted &&
        (!record.isConfirmed || record.submittedAt == null)) {
      throw StateError(
        'A submitted visit must keep a confirmation and submission time.',
      );
    }
    if (record.status == VisitStatus.draft && record.submittedAt != null) {
      throw StateError('A draft visit cannot retain a submission time.');
    }
    final saved = record.copyWith(
      updatedAt: now ?? DateTime.now().toUtc(),
      revision: existing.revision + 1,
      archiveMetadata: existing.archiveMetadata,
    );
    _records[saved.id] = saved;
    return saved;
  }

  @override
  Future<VisitRecord> submit({
    required AuthenticatedUser actor,
    required String visitId,
    DateTime? now,
  }) async {
    _requireCollector(actor);
    final existing = _requireOwned(visitId, actor);
    if (existing.isArchived) {
      throw StateError('Archived visits cannot be submitted.');
    }
    final submitted = existing.submit(now ?? DateTime.now().toUtc());
    _records[visitId] = submitted;
    return submitted;
  }

  @override
  Future<VisitRecord> updateSyncState({
    required AuthenticatedUser actor,
    required String visitId,
    required SyncState syncState,
    DateTime? now,
  }) async {
    _requireCollector(actor);
    final existing = _records[visitId];
    if (existing == null) throw StateError('Visit does not exist.');
    if (existing.collectorId != actor.id) {
      throw StateError('Visit belongs to another collector.');
    }
    if (existing.isArchived) {
      throw StateError('Archived visits cannot be synchronized by collectors.');
    }
    final updated = existing.copyWith(
      syncState: syncState,
      updatedAt: now ?? DateTime.now().toUtc(),
      revision: existing.revision + 1,
    );
    _records[visitId] = updated;
    return updated;
  }

  @override
  Future<VisitRecord> setArchived({
    required AuthenticatedUser actor,
    required String visitId,
    required bool archived,
    DateTime? now,
  }) async {
    if (!actor.isAdmin) {
      throw StateError('Only administrators can archive or restore visits.');
    }
    final existing = _records[visitId];
    if (existing == null) throw StateError('Visit does not exist.');
    final timestamp = now ?? DateTime.now().toUtc();
    final updated = archived
        ? existing.archive(archivedBy: actor.id, at: timestamp)
        : existing.restore(timestamp);
    _records[visitId] = updated;
    return updated;
  }

  bool _canRead(AuthenticatedUser actor, VisitRecord record) =>
      actor.isAdmin || (!record.isArchived && record.collectorId == actor.id);

  void _requireCollector(AuthenticatedUser actor) {
    if (!actor.isCollector) {
      throw StateError('Only collectors can create or edit visit submissions.');
    }
  }

  VisitRecord _requireOwned(String id, AuthenticatedUser actor) {
    final record = _records[id];
    if (record == null) throw StateError('Visit does not exist.');
    if (record.collectorId != actor.id) {
      throw StateError('Visit belongs to another collector.');
    }
    return record;
  }

  String _newId() {
    while (_records.containsKey('visit-$_nextId')) {
      _nextId++;
    }
    return 'visit-${_nextId++}';
  }

  bool _sameParticipant(ParticipantProfile one, ParticipantProfile other) =>
      one.studyId == other.studyId &&
      one.name == other.name &&
      one.indianPhone == other.indianPhone;

  bool _sameArchive(ArchiveMetadata? one, ArchiveMetadata? other) =>
      one?.archivedBy == other?.archivedBy &&
      one?.archivedAt == other?.archivedAt;
}
