import 'package:flutter_test/flutter_test.dart';
import 'package:project2/cloud/in_memory_study_cloud_gateway.dart';
import 'package:project2/cloud/study_cloud_gateway.dart';
import 'package:project2/collector/collector_cloud_controller.dart';
import 'package:project2/collector_auth/collector_access.dart';
import 'package:project2/domain/ncd_questionnaire.dart';
import 'package:project2/domain/study_configuration.dart';
import 'package:project2/domain/visit_record.dart';

void main() {
  const policy = ParticipantIdPolicy(
    prefix: 'P',
    firstNumber: 1,
    lastNumber: 99,
  );

  ({
    InMemoryStudyCloudGateway gateway,
    InMemoryInstallationSessionStore store,
    CollectorCloudController controller,
  })
  setUpController({
    String installationId = 'install-a',
    String requestId = 'generated-key',
  }) {
    final gateway = InMemoryStudyCloudGateway(
      participantIdPolicy: policy,
      clock: () => DateTime.utc(2026, 9, 14),
    );
    gateway.registerCollector(code: CollectorCode('C001'), id: 'collector-1');
    final store = InMemoryInstallationSessionStore();
    return (
      gateway: gateway,
      store: store,
      controller: CollectorCloudController(
        gateway: gateway,
        sessionStore: store,
        installationIdGenerator: () => installationId,
        requestIdGenerator: () => requestId,
      ),
    );
  }

  test(
    'claims with injected installation ID then restores validated session',
    () async {
      final setup = setUpController();

      final claimed = await setup.controller.restoreOrClaim(
        collectorCode: CollectorCode('C001'),
      );
      final restored = await setup.controller.restoreOrClaim();

      expect(claimed.claimed, isTrue);
      expect(claimed.session.installationId, 'install-a');
      expect(restored.restored, isTrue);
      expect(restored.session.accessToken, claimed.session.accessToken);
    },
  );

  test('clears malformed or invalid persisted sessions', () async {
    final setup = setUpController();
    await setup.store.write(
      CollectorInstallationSession(
        collectorId: 'not-registered',
        collectorCode: CollectorCode('C001'),
        installationId: 'old-phone',
        accessToken: 'expired',
        issuedAt: DateTime.utc(2026),
      ),
    );

    expect(await setup.controller.validatePersistedSession(), isNull);
    expect(await setup.store.read(), isNull);
    await expectLater(
      setup.controller.lookupParticipant(
        ParticipantLookupQuery.byStudyId('P001'),
      ),
      throwsA(isA<CollectorSessionRequiredException>()),
    );
  });

  test(
    'allocates a new then repeat visit using a retry-safe request key',
    () async {
      final setup = setUpController(requestId: 'allocation-key');
      await setup.controller.restoreOrClaim(
        collectorCode: CollectorCode('C001'),
      );
      final details = NewParticipantDetails(
        name: 'Mira Rao',
        indianPhone: '9000000001',
      );

      final first = await setup.controller.allocateNewOrRepeatVisit(
        participant: details,
      );
      final retry = await setup.controller.allocateNewOrRepeatVisit(
        participant: details,
        requestKey: first.requestKey,
      );
      final repeat = await setup.controller.allocateNewOrRepeatVisit(
        participant: details,
        requestKey: 'second-allocation-key',
      );

      expect(first.allocation.participant.studyId, 'P001');
      expect(retry.allocation.visitId, first.allocation.visitId);
      expect(repeat.allocation.visitNumber, 2);
    },
  );

  test(
    'looks up, uploads idempotently, and refreshes collector history',
    () async {
      final setup = setUpController(requestId: 'upload-key');
      final session = (await setup.controller.restoreOrClaim(
        collectorCode: CollectorCode('C001'),
      )).session;
      final allocated = await setup.controller.allocateNewOrRepeatVisit(
        participant: NewParticipantDetails(
          name: 'Mira Rao',
          indianPhone: '9000000001',
        ),
        requestKey: 'allocation-key',
      );
      final lookup = await setup.controller.lookupParticipant(
        ParticipantLookupQuery.byIndianPhone('9000000001'),
      );
      final record = _recordFrom(allocated.allocation, session.collectorId);

      final uploaded = await setup.controller.uploadIdempotently(
        record: record,
      );
      final retry = await setup.controller.uploadIdempotently(
        record: record,
        idempotencyKey: uploaded.idempotencyKey,
      );

      expect(lookup?.participant.studyId, 'P001');
      expect(uploaded.upload.created, isTrue);
      expect(retry.upload.created, isFalse);
      expect(
        (await setup.controller.refreshCollectorHistory()).single.id,
        allocated.allocation.visitId,
      );
    },
  );

  test('rejects uploading a record for a different collector', () async {
    final setup = setUpController();
    await setup.controller.restoreOrClaim(collectorCode: CollectorCode('C001'));
    final allocation = await setup.controller.allocateNewOrRepeatVisit(
      participant: NewParticipantDetails(
        name: 'Mira Rao',
        indianPhone: '9000000001',
      ),
    );

    await expectLater(
      setup.controller.uploadIdempotently(
        record: _recordFrom(allocation.allocation, 'another-collector'),
      ),
      throwsArgumentError,
    );
  });

  test('rejects an unsubmitted record before it reaches the gateway', () async {
    final setup = setUpController();
    final session = (await setup.controller.restoreOrClaim(
      collectorCode: CollectorCode('C001'),
    )).session;
    final allocation = await setup.controller.allocateNewOrRepeatVisit(
      participant: NewParticipantDetails(
        name: 'Mira Rao',
        indianPhone: '9000000001',
      ),
    );

    await expectLater(
      setup.controller.uploadIdempotently(
        record: _recordFrom(
          allocation.allocation,
          session.collectorId,
          submitted: false,
        ),
      ),
      throwsArgumentError,
    );
  });
}

VisitRecord _recordFrom(
  VisitAllocation allocation,
  String collectorId, {
  bool submitted = true,
}) {
  final timestamp = DateTime.utc(2026, 9, 14);
  return VisitRecord(
    id: allocation.visitId,
    participant: allocation.participant,
    visitNumber: allocation.visitNumber,
    collectorId: collectorId,
    createdAt: timestamp,
    updatedAt: timestamp,
    status: submitted ? VisitStatus.submitted : VisitStatus.draft,
    syncState: SyncState.pending,
    reviewState: NeutralReviewState.pending,
    revision: 1,
    confirmation: VisitConfirmation(
      name: allocation.participant.name,
      indianPhone: allocation.participant.indianPhone,
      visitNumber: allocation.visitNumber,
      confirmedAt: timestamp,
    ),
    questionnaire: questionnaire,
    submittedAt: submitted ? timestamp : null,
  );
}

const questionnaire = NcdQuestionnaire(
  studySite: 'community_clinic',
  age: 34,
  sex: 'female',
  education: 'secondary',
  employment: 'employed',
  fruitFrequency: 'daily',
  vegetableFrequency: 'daily',
  sugaryDrinkFrequency: 'one_to_two_days',
  processedFoodFrequency: 'never',
  activeDaysPerWeek: 5,
  activeMinutesPerDay: 30,
  sleepHours: 7.5,
  heightCm: 160,
  weightKg: 64,
  waistCm: 82,
  bpOneSystolic: 120,
  bpOneDiastolic: 80,
  bpTwoSystolic: 124,
  bpTwoDiastolic: 78,
);
