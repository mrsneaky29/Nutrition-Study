import 'measurement.dart';
import 'ncd_questionnaire.dart';
import 'participant_profile.dart';

enum VisitStatus { draft, submitted }

enum SyncState { localOnly, pending, synced, failed }

/// A non-judgmental administrative review marker. It carries no rating.
enum NeutralReviewState { pending, reviewed }

/// A staff member must repeat these details before a visit can be submitted.
class VisitConfirmation {
  VisitConfirmation({
    required String name,
    required String indianPhone,
    required this.visitNumber,
    required this.confirmedAt,
  }) : name = ParticipantProfile.normalizeName(name),
       indianPhone = ParticipantProfile.requireIndianPhone(indianPhone),
       assert(visitNumber > 0);

  final String name;
  final String indianPhone;
  final int visitNumber;
  final DateTime confirmedAt;

  bool matches(ParticipantProfile participant, int expectedVisitNumber) =>
      name == participant.name &&
      indianPhone == participant.indianPhone &&
      visitNumber == expectedVisitNumber;

  Map<String, Object> toFirestoreMap() => {
    'name': name,
    'indianPhone': indianPhone,
    'visitNumber': visitNumber,
    'confirmedAt': confirmedAt.toUtc().toIso8601String(),
  };

  Map<String, String> toCsvRow() => {
    'confirmed_name': name,
    'confirmed_indian_phone': indianPhone,
    'confirmed_visit_number': visitNumber.toString(),
    'confirmed_at': confirmedAt.toUtc().toIso8601String(),
  };
}

/// Audit information recorded when an administrator removes a visit from the
/// active operational queue. The record remains available to administrators
/// and can be restored; it is never silently deleted.
class ArchiveMetadata {
  ArchiveMetadata({required this.archivedBy, required this.archivedAt})
    : assert(archivedBy != '');

  final String archivedBy;
  final DateTime archivedAt;

  Map<String, Object> toFirestoreMap() => {
    'archivedBy': archivedBy,
    'archivedAt': archivedAt.toUtc().toIso8601String(),
  };

  Map<String, String> toCsvRow() => {
    'archived_by': archivedBy,
    'archived_at': archivedAt.toUtc().toIso8601String(),
  };
}

class VisitRecord {
  const VisitRecord({
    required this.id,
    required this.participant,
    required this.visitNumber,
    required this.collectorId,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.syncState,
    required this.reviewState,
    required this.revision,
    this.confirmation,
    this.stepTwoMeasurement,
    this.stepTwoPlaceholderNote,
    this.questionnaire,
    this.archiveMetadata,
    this.submittedAt,
  }) : assert(id != ''),
       assert(collectorId != ''),
       assert(visitNumber > 0),
       assert(revision > 0);

  final String id;
  final ParticipantProfile participant;
  final int visitNumber;
  final String collectorId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final VisitStatus status;
  final SyncState syncState;
  final NeutralReviewState reviewState;

  /// Increments whenever the owner changes the record, including after submit.
  final int revision;
  final VisitConfirmation? confirmation;
  final StepTwoMeasurement? stepTwoMeasurement;

  /// Unstructured, optional information collected by the replaceable Step 2
  /// placeholder. This deliberately has no questionnaire interpretation.
  final String? stepTwoPlaceholderNote;
  final NcdQuestionnaire? questionnaire;
  final ArchiveMetadata? archiveMetadata;
  final DateTime? submittedAt;

  bool get isDraft => status == VisitStatus.draft;
  bool get isSubmitted => status == VisitStatus.submitted;
  bool get isConfirmed =>
      confirmation?.matches(participant, visitNumber) ?? false;
  bool get isArchived => archiveMetadata != null;

  VisitRecord copyWith({
    ParticipantProfile? participant,
    int? visitNumber,
    DateTime? updatedAt,
    VisitStatus? status,
    SyncState? syncState,
    NeutralReviewState? reviewState,
    int? revision,
    VisitConfirmation? confirmation,
    bool clearConfirmation = false,
    StepTwoMeasurement? stepTwoMeasurement,
    bool clearStepTwoMeasurement = false,
    String? stepTwoPlaceholderNote,
    bool clearStepTwoPlaceholderNote = false,
    NcdQuestionnaire? questionnaire,
    bool clearQuestionnaire = false,
    ArchiveMetadata? archiveMetadata,
    bool clearArchiveMetadata = false,
    DateTime? submittedAt,
    bool clearSubmittedAt = false,
  }) {
    return VisitRecord(
      id: id,
      participant: participant ?? this.participant,
      visitNumber: visitNumber ?? this.visitNumber,
      collectorId: collectorId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      syncState: syncState ?? this.syncState,
      reviewState: reviewState ?? this.reviewState,
      revision: revision ?? this.revision,
      confirmation: clearConfirmation
          ? null
          : confirmation ?? this.confirmation,
      stepTwoMeasurement: clearStepTwoMeasurement
          ? null
          : stepTwoMeasurement ?? this.stepTwoMeasurement,
      stepTwoPlaceholderNote: clearStepTwoPlaceholderNote
          ? null
          : stepTwoPlaceholderNote ?? this.stepTwoPlaceholderNote,
      questionnaire: clearQuestionnaire ? null : questionnaire ?? this.questionnaire,
      archiveMetadata: clearArchiveMetadata
          ? null
          : archiveMetadata ?? this.archiveMetadata,
      submittedAt: clearSubmittedAt ? null : submittedAt ?? this.submittedAt,
    );
  }

  VisitRecord archive({required String archivedBy, required DateTime at}) {
    if (isArchived) throw StateError('This visit is already archived.');
    return copyWith(
      archiveMetadata: ArchiveMetadata(archivedBy: archivedBy, archivedAt: at),
      updatedAt: at,
      revision: revision + 1,
    );
  }

  VisitRecord restore(DateTime at) {
    if (!isArchived) throw StateError('This visit is not archived.');
    return copyWith(
      clearArchiveMetadata: true,
      updatedAt: at,
      revision: revision + 1,
    );
  }

  VisitRecord submit(DateTime at) {
    if (!isDraft) throw StateError('Only a draft visit can be submitted.');
    if (!isConfirmed) {
      throw StateError('Name, phone, and visit number must be confirmed.');
    }
    return copyWith(
      status: VisitStatus.submitted,
      syncState: SyncState.pending,
      submittedAt: at,
      updatedAt: at,
      revision: revision + 1,
    );
  }

  Map<String, Object?> toFirestoreMap() => {
    'id': id,
    'participant': participant.toFirestoreMap(),
    'visitNumber': visitNumber,
    'collectorId': collectorId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'status': status.name,
    'syncState': syncState.name,
    'reviewState': reviewState.name,
    'revision': revision,
    'confirmation': confirmation?.toFirestoreMap(),
    'stepTwoMeasurement': stepTwoMeasurement?.toFirestoreMap(),
    'stepTwoPlaceholderNote': stepTwoPlaceholderNote,
    'questionnaire': questionnaire?.toMap(),
    ...?(archiveMetadata == null
        ? null
        : {
            'archivedAt': archiveMetadata!.archivedAt.toUtc(),
            'archivedBy': archiveMetadata!.archivedBy,
          }),
    'submittedAt': submittedAt?.toUtc().toIso8601String(),
  };

  Map<String, String> toCsvRow() => {
    // Direct identifiers remain in the operational participant record, never
    // in an analysis/export row.
    'participant_study_id': participant.studyId,
    'visit_id': id,
    'visit_number': visitNumber.toString(),
    'collector_id': collectorId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'visit_status': status.name,
    'sync_state': syncState.name,
    'review_state': reviewState.name,
    'revision': revision.toString(),
    'submitted_at': submittedAt?.toUtc().toIso8601String() ?? '',
    ...?archiveMetadata?.toCsvRow(),
    ...?confirmation?.toCsvRow(),
    ...?stepTwoMeasurement?.toCsvRow(),
    'step_2_placeholder_note': stepTwoPlaceholderNote ?? '',
    ...?questionnaire?.toCsvRow(),
  };
}
