import '../domain/visit_record.dart' show SyncState;

export '../domain/visit_record.dart' show SyncState;

/// Lightweight view data owned by presentation until domain models are wired in.
class ParticipantDraft {
  const ParticipantDraft({
    required this.studyId,
    required this.name,
    required this.phone,
  });

  final String studyId;
  final String name;
  final String phone;
}

class SubmissionSummary {
  const SubmissionSummary({
    required this.id,
    required this.participantName,
    required this.studyId,
    required this.visitNumber,
    required this.submittedAt,
    required this.syncState,
  });

  final String id;
  final String participantName;
  final String studyId;
  final int visitNumber;
  final DateTime submittedAt;
  final SyncState syncState;
}

extension SyncStateLabel on SyncState {
  String get label => switch (this) {
    SyncState.localOnly => 'Saved on this device',
    SyncState.synced => 'Synced',
    SyncState.pending => 'Pending sync',
    SyncState.failed => 'Sync needs attention',
  };
}

class AdminRecord {
  const AdminRecord({
    required this.recordId,
    required this.studyId,
    required this.participantName,
    required this.collector,
    required this.visitNumber,
    required this.status,
  });

  final String recordId;
  final String studyId;
  final String participantName;
  final String collector;
  final int visitNumber;
  final SyncState status;
}
