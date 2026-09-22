import 'package:flutter_test/flutter_test.dart';
import 'package:project2/cloud/mappers/create_study_visit_payload_mapper.dart';
import 'package:project2/domain/measurement.dart';
import 'package:project2/domain/ncd_questionnaire.dart';
import 'package:project2/domain/participant_profile.dart';
import 'package:project2/domain/study_configuration.dart';
import 'package:project2/domain/visit_record.dart';

void main() {
  const mapper = CreateStudyVisitPayloadMapper();

  test(
    'maps a submitted P001 record to the new-participant callable contract',
    () {
      final record = _submittedRecord();

      final payload = mapper.map(
        record: record,
        studyId: 'pilot-2026',
        idempotencyKey: 'request_key_00001',
        participant: const NewCloudParticipant(),
      );

      expect(payload['studyId'], 'pilot-2026');
      expect(payload['idempotencyKey'], 'request_key_00001');
      expect(payload['participant'], {
        'mode': 'new',
        'profile': {'name': 'Test Participant', 'indianPhone': '+919000000001'},
        'metadata': {'schemaVersion': 1, 'sourceParticipantStudyId': 'P001'},
      });
      final visit = payload['visit']! as Map<String, Object?>;
      expect(visit['visitDate'], record.submittedAt);
      expect(visit['submittedAt'], record.submittedAt);
      expect(visit['status'], 'submitted');
      expect(visit['reviewState'], 'pending');
      expect(visit['questionnaire'], record.questionnaire!.toMap());
      expect(visit['stepTwoMeasurement'], {
        'value': 12.4,
        'unit': 'mg/dL',
        'recordedAt': DateTime.utc(2026, 9, 14, 8, 5),
        'note': 'Fasting sample',
      });
      expect(visit['confirmation'], {
        'name': 'Test Participant',
        'indianPhone': '+919000000001',
        'visitNumber': 1,
        'confirmedAt': DateTime.utc(2026, 9, 14, 8),
      });
      expect(visit['metadata'], {
        'schemaVersion': 1,
        'sourceRecordId': 'LOCAL-1',
        'sourceRevision': 2,
      });
      expect(_containsConsent(payload), isFalse);
    },
  );

  test('uses a Firestore participant document ID for repeat visits', () {
    final payload = mapper.map(
      record: _submittedRecord(),
      studyId: 'pilot-2026',
      idempotencyKey: 'request_key_00002',
      participant: ExistingCloudParticipant(participantId: 'dT3Fq1'),
    );

    expect(payload['participant'], {
      'mode': 'existing',
      'participantId': 'dT3Fq1',
    });
  });

  test('rejects incomplete records and invalid callable identifiers', () {
    final record = _submittedRecord();
    expect(
      () => mapper.map(
        record: record.copyWith(status: VisitStatus.draft),
        studyId: 'pilot-2026',
        idempotencyKey: 'request_key_00003',
        participant: const NewCloudParticipant(),
      ),
      throwsArgumentError,
    );
    expect(
      () => mapper.map(
        record: record,
        studyId: 'pilot/2026',
        idempotencyKey: 'short',
        participant: const NewCloudParticipant(),
      ),
      throwsArgumentError,
    );
    expect(
      () => ExistingCloudParticipant(participantId: 'participants/P001'),
      throwsArgumentError,
    );
  });
}

VisitRecord _submittedRecord() {
  const policy = ParticipantIdPolicy(
    prefix: 'P',
    firstNumber: 1,
    lastNumber: 200,
  );
  final participant = ParticipantProfile(
    studyId: 'P001',
    name: 'Test Participant',
    indianPhone: '+919000000001',
    idPolicy: policy,
  );
  final at = DateTime.utc(2026, 9, 14, 8);
  return VisitRecord(
    id: 'LOCAL-1',
    participant: participant,
    visitNumber: 1,
    collectorId: 'C001',
    createdAt: at,
    updatedAt: at,
    submittedAt: at,
    status: VisitStatus.submitted,
    syncState: SyncState.pending,
    reviewState: NeutralReviewState.pending,
    revision: 2,
    confirmation: VisitConfirmation(
      name: 'Test Participant',
      indianPhone: '+919000000001',
      visitNumber: 1,
      confirmedAt: at,
    ),
    stepTwoMeasurement: StepTwoMeasurement(
      value: 12.4,
      unit: 'mg/dL',
      recordedAt: DateTime.utc(2026, 9, 14, 8, 5),
      note: 'Fasting sample',
    ),
    questionnaire: const NcdQuestionnaire(
      studySite: 'community_clinic',
      age: 36,
      sex: 'female',
      education: 'higher',
      employment: 'employed',
      fruitFrequency: 'daily',
      vegetableFrequency: 'daily',
      sugaryDrinkFrequency: 'never',
      processedFoodFrequency: 'one_to_two_days',
      activeDaysPerWeek: 5,
      activeMinutesPerDay: 30,
      sleepHours: 7,
      heightCm: 160,
      weightKg: 62,
      waistCm: 78,
      bpOneSystolic: 120,
      bpOneDiastolic: 80,
      bpTwoSystolic: 118,
      bpTwoDiastolic: 78,
      tobaccoUse: 'never',
      alcoholPast30Days: 'no',
      hypertensionDiagnosis: 'no',
      diabetesDiagnosis: 'no',
      highCholesterolDiagnosis: 'dont_know',
      cardiovascularDiagnosis: 'no',
    ),
  );
}

bool _containsConsent(Object? value) {
  if (value is Map) {
    return value.keys.any(
          (key) => key.toString().toLowerCase().contains('consent'),
        ) ||
        value.values.any(_containsConsent);
  }
  if (value is Iterable) return value.any(_containsConsent);
  return false;
}
