import '../../domain/visit_record.dart';

/// Selects how the Functions `createStudyVisit` callable should resolve the
/// participant for a canonical local [VisitRecord].
///
/// A participant code such as `P001` is not a Firestore document ID. For an
/// existing cloud participant, pass the document ID returned by the callable.
sealed class CloudParticipantTarget {
  const CloudParticipantTarget();
}

/// Lets the callable allocate the next participant code transactionally.
class NewCloudParticipant extends CloudParticipantTarget {
  const NewCloudParticipant();
}

/// Reuses a participant document that was returned by an earlier callable.
class ExistingCloudParticipant extends CloudParticipantTarget {
  ExistingCloudParticipant({required String participantId})
    : participantId = _documentId(participantId, 'participantId');

  final String participantId;
}

/// Produces the JSON-compatible request object accepted by `createStudyVisit`.
///
/// This mapper deliberately has no Firebase dependency: the Firebase adapter
/// may convert the returned UTC [DateTime] values to its timestamp type at the
/// network boundary. It sends no consent fields; physical consent remains
/// outside this data contract.
class CreateStudyVisitPayloadMapper {
  const CreateStudyVisitPayloadMapper();

  Map<String, Object?> map({
    required VisitRecord record,
    required String studyId,
    required String idempotencyKey,
    required CloudParticipantTarget participant,
  }) {
    final normalizedStudyId = _documentId(studyId, 'studyId');
    final normalizedKey = idempotencyKey.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(normalizedKey)) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'Use 16–128 URL-safe characters.',
      );
    }
    if (!record.isSubmitted || record.submittedAt == null) {
      throw ArgumentError('Only submitted records can be uploaded.');
    }
    if (record.isArchived) {
      throw ArgumentError('Archived records cannot be uploaded.');
    }
    if (!record.isConfirmed) {
      throw ArgumentError('The record confirmation does not match the visit.');
    }
    final questionnaire = record.questionnaire;
    if (questionnaire == null) {
      throw ArgumentError('A custom NCD questionnaire is required.');
    }

    return {
      'studyId': normalizedStudyId,
      'idempotencyKey': normalizedKey,
      'participant': switch (participant) {
        NewCloudParticipant() => {
          'mode': 'new',
          // The callable, rather than a phone, allocates participantCode P001…
          'profile': {
            'name': record.participant.name,
            'indianPhone': record.participant.indianPhone,
          },
          'metadata': {
            'schemaVersion': 1,
            // Retain the local P001-style value only as migration provenance;
            // it is never submitted as the cloud participant document ID.
            'sourceParticipantStudyId': record.participant.studyId,
          },
        },
        ExistingCloudParticipant(:final participantId) => {
          'mode': 'existing',
          'participantId': participantId,
        },
      },
      'visit': {
        'visitDate': record.submittedAt!.toUtc(),
        'submittedAt': record.submittedAt!.toUtc(),
        'status': record.status.name,
        'reviewState': record.reviewState.name,
        'questionnaire': questionnaire.toMap(),
        if (record.stepTwoMeasurement case final measurement?)
          'stepTwoMeasurement': {
            'value': measurement.value,
            'unit': measurement.unit,
            if (measurement.recordedAt case final recordedAt?)
              'recordedAt': recordedAt.toUtc(),
            'note': ?measurement.note,
          },
        'confirmation': {
          'name': record.confirmation!.name,
          'indianPhone': record.confirmation!.indianPhone,
          'visitNumber': record.confirmation!.visitNumber,
          'confirmedAt': record.confirmation!.confirmedAt.toUtc(),
        },
        'metadata': {
          'schemaVersion': 1,
          'sourceRecordId': record.id,
          'sourceRevision': record.revision,
        },
      },
    };
  }
}

String _documentId(String value, String field) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.contains('/')) {
    throw ArgumentError.value(value, field, '$field must be a document ID.');
  }
  return normalized;
}
