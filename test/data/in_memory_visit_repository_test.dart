import 'package:flutter_test/flutter_test.dart';
import 'package:project2/data/study_data.dart';
import 'package:project2/domain/study_models.dart';

void main() {
  const policy = ParticipantIdPolicy(
    prefix: 'P',
    firstNumber: 1,
    lastNumber: 200,
  );
  final participant = ParticipantProfile(
    studyId: 'P001',
    name: 'Mira Rao',
    indianPhone: '9000000001',
    idPolicy: policy,
  );
  const collectorA = AuthenticatedUser(
    id: 'collector-a',
    role: UserRole.collector,
  );
  const collectorB = AuthenticatedUser(
    id: 'collector-b',
    role: UserRole.collector,
  );
  const admin = AuthenticatedUser(id: 'admin', role: UserRole.admin);

  test(
    'repository assigns consecutive visits and scopes collector access',
    () async {
      final repository = InMemoryVisitRepository();
      final first = await repository.createDraft(
        actor: collectorA,
        participant: participant,
      );
      final second = await repository.createDraft(
        actor: collectorB,
        participant: participant,
      );
      expect([first.visitNumber, second.visitNumber], [1, 2]);
      expect(await repository.getById(second.id, collectorA), isNull);
      expect((await repository.listVisibleTo(collectorA)).single.id, first.id);
      expect((await repository.listVisibleTo(admin)).length, 2);
    },
  );

  test(
    'only the owner can edit records and submitted changes retain their status',
    () async {
      final repository = InMemoryVisitRepository();
      final draft = await repository.createDraft(
        actor: collectorA,
        participant: participant,
      );
      await expectLater(
        repository.saveOwnRecord(actor: collectorB, record: draft),
        throwsStateError,
      );
      final confirmed = draft.copyWith(
        confirmation: VisitConfirmation(
          name: participant.name,
          indianPhone: participant.indianPhone,
          visitNumber: draft.visitNumber,
          confirmedAt: DateTime.utc(2026),
        ),
      );
      await repository.saveOwnRecord(actor: collectorA, record: confirmed);
      final submitted = await repository.submit(
        actor: collectorA,
        visitId: draft.id,
      );
      expect(submitted.syncState, SyncState.pending);
      final amended = submitted.copyWith(
        stepTwoMeasurement: const StepTwoMeasurement(value: 10, unit: 'kg'),
      );
      final saved = await repository.saveOwnRecord(
        actor: collectorA,
        record: amended,
      );
      expect(saved.status, VisitStatus.submitted);
      expect(saved.revision, 4);
      expect(saved.syncState, SyncState.pending);
    },
  );

  test(
    'seed supports offline demos and next visit follows seeded history',
    () async {
      final repository = InMemoryVisitRepository();
      repository.seed([
        VisitRecord(
          id: 'imported-visit',
          participant: participant,
          visitNumber: 4,
          collectorId: collectorA.id,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          status: VisitStatus.submitted,
          syncState: SyncState.synced,
          reviewState: NeutralReviewState.pending,
          revision: 1,
          submittedAt: DateTime.utc(2026),
        ),
      ]);
      final newDraft = await repository.createDraft(
        actor: collectorB,
        participant: participant,
      );
      expect(newDraft.visitNumber, 5);
    },
  );

  test(
    'only admins can archive and archived visits leave collector queues',
    () async {
      final repository = InMemoryVisitRepository();
      final draft = await repository.createDraft(
        actor: collectorA,
        participant: participant,
      );
      await expectLater(
        repository.setArchived(
          actor: collectorA,
          visitId: draft.id,
          archived: true,
        ),
        throwsStateError,
      );
      final archived = await repository.setArchived(
        actor: admin,
        visitId: draft.id,
        archived: true,
        now: DateTime.utc(2026),
      );
      expect(archived.archiveMetadata?.archivedBy, admin.id);
      expect(await repository.getById(draft.id, collectorA), isNull);
      expect((await repository.listVisibleTo(admin)).single.isArchived, isTrue);
      final restored = await repository.setArchived(
        actor: admin,
        visitId: draft.id,
        archived: false,
        now: DateTime.utc(2026, 1, 2),
      );
      expect(restored.isArchived, isFalse);
    },
  );

  test(
    'admins can amend study data but cannot change identity or ownership',
    () async {
      final repository = InMemoryVisitRepository();
      final draft = await repository.createDraft(
        actor: collectorA,
        participant: participant,
      );
      final amended = draft.copyWith(
        participant: ParticipantProfile(
          studyId: participant.studyId,
          name: 'Mira S. Rao',
          indianPhone: participant.indianPhone,
          idPolicy: policy,
        ),
        visitNumber: 7,
        reviewState: NeutralReviewState.reviewed,
        stepTwoMeasurement: const StepTwoMeasurement(value: 12, unit: 'kg'),
      );
      final saved = await repository.saveAdminRecord(
        actor: admin,
        record: amended,
        now: DateTime.utc(2026),
      );
      expect(saved.participant.name, 'Mira S. Rao');
      expect(saved.visitNumber, 7);
      expect(saved.reviewState, NeutralReviewState.reviewed);
      expect(saved.revision, 2);
      await expectLater(
        repository.saveAdminRecord(
          actor: admin,
          record: amended.copyWith(
            participant: ParticipantProfile(
              studyId: 'P002',
              name: amended.participant.name,
              indianPhone: amended.participant.indianPhone,
              idPolicy: policy,
            ),
          ),
        ),
        throwsArgumentError,
      );
    },
  );
}
