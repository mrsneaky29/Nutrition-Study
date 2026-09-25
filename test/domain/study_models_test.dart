import 'package:flutter_test/flutter_test.dart';
import 'package:project2/domain/study_models.dart';

void main() {
  const policy = ParticipantIdPolicy(
    prefix: 'NUT',
    firstNumber: 12,
    lastNumber: 14,
  );

  test(
    'participant IDs are configured and phone numbers are canonicalized',
    () {
      expect(policy.normalize(' nut012 '), 'NUT012');
      expect(policy.normalize('NUT011'), isNull);
      final participant = ParticipantProfile(
        studyId: 'nut012',
        name: '  Test   Participant ',
        indianPhone: '09000 000001',
        idPolicy: policy,
      );
      expect(participant.studyId, 'NUT012');
      expect(participant.name, 'Test Participant');
      expect(participant.indianPhone, '+919000000001');
      expect(participant.toCsvRow(), {'participant_study_id': 'NUT012'});
    },
  );

  test('a visit cannot submit until staff repeats every identity detail', () {
    final participant = ParticipantProfile(
      studyId: 'NUT012',
      name: 'Test Participant',
      indianPhone: '+919000000001',
      idPolicy: policy,
    );
    final draft = VisitRecord(
      id: 'v1',
      participant: participant,
      visitNumber: 1,
      collectorId: 'collector-a',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      status: VisitStatus.draft,
      syncState: SyncState.localOnly,
      reviewState: NeutralReviewState.pending,
      revision: 1,
    );
    expect(() => draft.submit(DateTime.utc(2026, 1, 2)), throwsStateError);
    final confirmed = draft.copyWith(
      confirmation: VisitConfirmation(
        name: 'Test Participant',
        indianPhone: '9000000001',
        visitNumber: 1,
        confirmedAt: DateTime.utc(2026, 1, 2),
      ),
    );
    expect(
      confirmed.submit(DateTime.utc(2026, 1, 2)).status,
      VisitStatus.submitted,
    );
  });

  test('exports contain flat CSV data and Firestore-safe primitive maps', () {
    final participant = ParticipantProfile(
      studyId: 'NUT012',
      name: 'Test Participant',
      indianPhone: '9000000001',
      idPolicy: policy,
    );
    final record = VisitRecord(
      id: 'v1',
      participant: participant,
      visitNumber: 1,
      collectorId: 'collector-a',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      status: VisitStatus.draft,
      syncState: SyncState.localOnly,
      reviewState: NeutralReviewState.pending,
      revision: 1,
      stepTwoMeasurement: const StepTwoMeasurement(value: 11.2, unit: 'kg'),
      stepTwoPlaceholderNote: 'Participant asked for a follow-up reminder.',
      confirmation: VisitConfirmation(
        name: 'Test Participant',
        indianPhone: '9000000001',
        visitNumber: 1,
        confirmedAt: DateTime.utc(2026),
      ),
      archiveMetadata: ArchiveMetadata(
        archivedBy: 'admin-a',
        archivedAt: DateTime.utc(2026),
      ),
    );
    expect(record.toCsvRow()['step_2_unit'], 'kg');
    expect(record.toFirestoreMap()['archivedAt'], DateTime.utc(2026));
    expect(record.toCsvRow()['archived_by'], 'admin-a');
    expect(
      record.toFirestoreMap()['stepTwoPlaceholderNote'],
      'Participant asked for a follow-up reminder.',
    );
    expect(record.toCsvRow().containsKey('step_2_placeholder_note'), isFalse);
    expect(record.toCsvRow()['confirmed_visit_number'], '1');
    expect(record.toCsvRow().containsKey('confirmed_name'), isFalse);
    expect(record.toCsvRow().containsKey('confirmed_indian_phone'), isFalse);
    expect(record.toCsvRow().containsKey('participant_name'), isFalse);
    expect(record.toCsvRow().containsKey('participant_indian_phone'), isFalse);
  });

  test('archiving is auditable and reversible without deleting the visit', () {
    final participant = ParticipantProfile(
      studyId: 'NUT012',
      name: 'Test Participant',
      indianPhone: '9000000001',
      idPolicy: policy,
    );
    final record = VisitRecord(
      id: 'v1',
      participant: participant,
      visitNumber: 1,
      collectorId: 'collector-a',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      status: VisitStatus.draft,
      syncState: SyncState.localOnly,
      reviewState: NeutralReviewState.pending,
      revision: 1,
    );
    final archived = record.archive(
      archivedBy: 'admin-a',
      at: DateTime.utc(2026, 1, 2),
    );
    expect(archived.isArchived, isTrue);
    expect(archived.revision, 2);
    final restored = archived.restore(DateTime.utc(2026, 1, 3));
    expect(restored.isArchived, isFalse);
    expect(restored.revision, 3);
  });
}
