import '../data/in_memory_visit_repository.dart';
import '../domain/participant_profile.dart';
import '../domain/study_configuration.dart';
import '../domain/visit_record.dart';

/// Synthetic, deterministic sample set used only by browser portal tests.
/// Production hosts should supply their own [InMemoryVisitRepository] or a
/// persistent [VisitRepository] implementation to [AdminPortalApp].
InMemoryVisitRepository createAdminDemoRepository() {
  const ids = ParticipantIdPolicy(prefix: 'P', firstNumber: 1, lastNumber: 200);
  final repository = InMemoryVisitRepository();
  final now = DateTime.utc(2026, 9, 12, 9);
  ParticipantProfile person(int number, String name, String phone) =>
      ParticipantProfile(
        studyId: ids.format(number),
        name: name,
        indianPhone: phone,
        idPolicy: ids,
      );
  VisitConfirmation confirmation(ParticipantProfile participant, int visit) =>
      VisitConfirmation(
        name: participant.name,
        indianPhone: participant.indianPhone,
        visitNumber: visit,
        confirmedAt: now,
      );

  final demoOne = person(12, 'Demo Participant 1', '+919000000001');
  final demoTwo = person(18, 'Demo Participant 2', '+919000000002');
  final demoThree = person(27, 'Demo Participant 3', '+919000000003');
  final demoFour = person(34, 'Demo Participant 4', '+919000000004');
  repository.seed([
    VisitRecord(
      id: 'visit-101',
      participant: demoOne,
      visitNumber: 2,
      collectorId: 'collector.sana',
      createdAt: now.subtract(const Duration(hours: 3)),
      updatedAt: now.subtract(const Duration(hours: 1)),
      submittedAt: now.subtract(const Duration(hours: 1)),
      status: VisitStatus.submitted,
      syncState: SyncState.synced,
      reviewState: NeutralReviewState.reviewed,
      confirmation: confirmation(demoOne, 2),
      revision: 3,
    ),
    VisitRecord(
      id: 'visit-102',
      participant: demoTwo,
      visitNumber: 1,
      collectorId: 'collector.sana',
      createdAt: now.subtract(const Duration(hours: 5)),
      updatedAt: now.subtract(const Duration(minutes: 45)),
      submittedAt: now.subtract(const Duration(minutes: 45)),
      status: VisitStatus.submitted,
      syncState: SyncState.pending,
      reviewState: NeutralReviewState.pending,
      confirmation: confirmation(demoTwo, 1),
      revision: 2,
    ),
    VisitRecord(
      id: 'visit-103',
      participant: demoThree,
      visitNumber: 3,
      collectorId: 'collector.rahul',
      createdAt: now.subtract(const Duration(days: 1)),
      updatedAt: now.subtract(const Duration(hours: 6)),
      submittedAt: now.subtract(const Duration(hours: 6)),
      status: VisitStatus.submitted,
      syncState: SyncState.failed,
      reviewState: NeutralReviewState.pending,
      confirmation: confirmation(demoThree, 3),
      revision: 4,
    ),
    VisitRecord(
      id: 'visit-104',
      participant: demoFour,
      visitNumber: 1,
      collectorId: 'collector.rahul',
      createdAt: now.subtract(const Duration(minutes: 18)),
      updatedAt: now.subtract(const Duration(minutes: 18)),
      status: VisitStatus.draft,
      syncState: SyncState.localOnly,
      reviewState: NeutralReviewState.pending,
      revision: 1,
    ),
  ]);
  return repository;
}
