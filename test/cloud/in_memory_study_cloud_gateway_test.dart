import 'package:flutter_test/flutter_test.dart';
import 'package:project2/cloud/in_memory_study_cloud_gateway.dart';
import 'package:project2/cloud/study_cloud_gateway.dart';
import 'package:project2/collector_auth/collector_access.dart';
import 'package:project2/domain/participant_profile.dart';
import 'package:project2/domain/study_configuration.dart';
import 'package:project2/domain/visit_record.dart';

void main() {
  const policy = ParticipantIdPolicy(
    prefix: 'P',
    firstNumber: 1,
    lastNumber: 99,
  );

  InMemoryStudyCloudGateway newGateway() {
    final gateway = InMemoryStudyCloudGateway(
      participantIdPolicy: policy,
      clock: () => DateTime.utc(2026, 9, 14),
    );
    gateway.registerCollector(code: CollectorCode('C001'), id: 'collector-1');
    gateway.registerCollector(code: CollectorCode('C002'), id: 'collector-2');
    return gateway;
  }

  test(
    'first device claims a collector code and a second phone is blocked',
    () async {
      final gateway = newGateway();
      final session = await gateway.claimFirstDevice(
        collectorCode: CollectorCode('C001'),
        installationId: 'phone-a',
      );
      expect(session.collectorId, 'collector-1');
      expect(
        () => gateway.claimFirstDevice(
          collectorCode: CollectorCode('C001'),
          installationId: 'phone-b',
        ),
        throwsA(
          isA<CollectorAccessException>().having(
            (error) => error.failure,
            'failure',
            CollectorAccessFailure.boundToAnotherDevice,
          ),
        ),
      );

      gateway.resetDeviceBinding(CollectorCode('C001'));
      final replacement = await gateway.claimFirstDevice(
        collectorCode: CollectorCode('C001'),
        installationId: 'phone-b',
      );
      expect(replacement.installationId, 'phone-b');
    },
  );

  test(
    'atomic allocation reuses request retries and assigns visits centrally',
    () async {
      final gateway = newGateway();
      final firstCollector = await gateway.claimFirstDevice(
        collectorCode: CollectorCode('C001'),
        installationId: 'phone-a',
      );
      final secondCollector = await gateway.claimFirstDevice(
        collectorCode: CollectorCode('C002'),
        installationId: 'phone-b',
      );
      final details = NewParticipantDetails(
        name: 'Mira Rao',
        indianPhone: '9000000001',
      );

      final first = await gateway.allocateVisit(
        session: firstCollector,
        participant: details,
        requestKey: 'allocation-a',
      );
      final retry = await gateway.allocateVisit(
        session: firstCollector,
        participant: details,
        requestKey: 'allocation-a',
      );
      final second = await gateway.allocateVisit(
        session: secondCollector,
        participant: details,
        requestKey: 'allocation-b',
      );

      expect(first.participant.studyId, 'P001');
      expect(retry.visitId, first.visitId);
      expect([first.visitNumber, second.visitNumber], [1, 2]);
      final lookup = await gateway.lookupParticipant(
        session: secondCollector,
        query: ParticipantLookupQuery.byIndianPhone('9000000001'),
      );
      expect(lookup?.nextVisitNumber, 3);
    },
  );

  test(
    'upload is idempotent and history is restricted to the collector',
    () async {
      final gateway = newGateway();
      final firstCollector = await gateway.claimFirstDevice(
        collectorCode: CollectorCode('C001'),
        installationId: 'phone-a',
      );
      final secondCollector = await gateway.claimFirstDevice(
        collectorCode: CollectorCode('C002'),
        installationId: 'phone-b',
      );
      final allocation = await gateway.allocateVisit(
        session: firstCollector,
        participant: NewParticipantDetails(
          name: 'Mira Rao',
          indianPhone: '9000000001',
        ),
        requestKey: 'allocation-a',
      );
      final record = _recordFrom(allocation, firstCollector.collectorId);

      final uploaded = await gateway.uploadVisit(
        session: firstCollector,
        record: record,
        idempotencyKey: 'upload-a',
      );
      final retry = await gateway.uploadVisit(
        session: firstCollector,
        record: record,
        idempotencyKey: 'upload-a',
      );

      expect(uploaded.created, isTrue);
      expect(uploaded.record.syncState, SyncState.synced);
      expect(retry.created, isFalse);
      expect(
        (await gateway.listCollectorHistory(session: firstCollector)).length,
        1,
      );
      expect(
        await gateway.listCollectorHistory(session: secondCollector),
        isEmpty,
      );
    },
  );

  test(
    'upload rejects records that were not allocated to the session',
    () async {
      final gateway = newGateway();
      final session = await gateway.claimFirstDevice(
        collectorCode: CollectorCode('C001'),
        installationId: 'phone-a',
      );
      final participant = ParticipantProfile(
        studyId: 'P001',
        name: 'Mira Rao',
        indianPhone: '9000000001',
        idPolicy: policy,
      );
      final unallocated = VisitRecord(
        id: 'made-up',
        participant: participant,
        visitNumber: 1,
        collectorId: session.collectorId,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        status: VisitStatus.draft,
        syncState: SyncState.pending,
        reviewState: NeutralReviewState.pending,
        revision: 1,
      );
      await expectLater(
        gateway.uploadVisit(
          session: session,
          record: unallocated,
          idempotencyKey: 'upload-made-up',
        ),
        throwsA(isA<CloudVisitConflictException>()),
      );
    },
  );
}

VisitRecord _recordFrom(VisitAllocation allocation, String collectorId) {
  final timestamp = DateTime.utc(2026, 9, 14);
  return VisitRecord(
    id: allocation.visitId,
    participant: allocation.participant,
    visitNumber: allocation.visitNumber,
    collectorId: collectorId,
    createdAt: timestamp,
    updatedAt: timestamp,
    status: VisitStatus.draft,
    syncState: SyncState.pending,
    reviewState: NeutralReviewState.pending,
    revision: 1,
  );
}
