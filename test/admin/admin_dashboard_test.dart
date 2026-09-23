import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project2/admin/admin_dashboard.dart';
import 'package:project2/admin/admin_demo_data.dart';
import 'package:project2/admin/local_api_visit_repository.dart';
import 'package:project2/data/in_memory_visit_repository.dart';
import 'package:project2/domain/authenticated_user.dart';
import 'package:project2/domain/ncd_questionnaire.dart';
import 'package:project2/domain/participant_id.dart';
import 'package:project2/domain/visit_record.dart';

void main() {
  const admin = AuthenticatedUser(id: 'admin.test', role: UserRole.admin);

  testWidgets('admin dashboard searches records and opens its guarded editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = createAdminDemoRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboard(repository: repository, admin: admin),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Study operations'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'not-a-record');
    await tester.pump();

    expect(find.text('No matching records'), findsOneWidget);
    expect(find.text('Questionnaire'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Demo Participant');
    await tester.pump();
    await tester.tap(find.text('Demo Participant 1').first);
    await tester.pumpAndSettle();

    expect(find.text('Edit record'), findsOneWidget);
    expect(find.text('Archive visit'), findsOneWidget);

    await tester.tap(find.text('Edit record'));
    await tester.pumpAndSettle();

    expect(find.text('Edit P012'), findsOneWidget);
    expect(find.text('Participant details'), findsOneWidget);
    expect(find.text('Optional Step 2 measurement'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).first,
      'Demo Participant 1 Revised',
    );
    final confirmationCheckbox = find.descendant(
      of: find.widgetWithText(
        CheckboxListTile,
        'I have confirmed the participant details and visit number.',
      ),
      matching: find.byType(Checkbox),
    );
    tester.widget<Checkbox>(confirmationCheckbox).onChanged!(true);
    await tester.pump();
    expect(tester.widget<Checkbox>(confirmationCheckbox).value, isTrue);
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(
      (await repository.getById('visit-101', admin))!.participant.name,
      'Demo Participant 1 Revised',
    );
  });

  testWidgets(
    'admin edit does NOT erase questionnaire responses (regression test)',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = createAdminDemoRepository();
      final original = (await repository.getById('visit-101', admin))!;
      const questionnaire = NcdQuestionnaire(
        studySite: 'Site B',
        age: 52,
        sex: 'male',
        education: 'Tertiary',
        employment: 'Retired',
        fruitFrequency: 'Daily',
        vegetableFrequency: 'Daily',
        sugaryDrinkFrequency: 'Never',
        processedFoodFrequency: 'Never',
        activeDaysPerWeek: 4,
        activeMinutesPerDay: 45,
        sleepHours: 8.0,
        heightCm: 175.0,
        weightKg: 78.0,
        waistCm: 88.0,
        bpOneSystolic: 125,
        bpOneDiastolic: 82,
        bpTwoSystolic: 122,
        bpTwoDiastolic: 80,
      );
      await repository.saveAdminRecord(
        actor: admin,
        record: original.copyWith(questionnaire: questionnaire),
      );

      await tester.pumpWidget(
        MaterialApp(home: AdminDashboard(repository: repository, admin: admin)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Demo Participant 1').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit record'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        'Demo Participant 1 Modified',
      );
      final confirmationCheckbox = find.descendant(
        of: find.widgetWithText(
          CheckboxListTile,
          'I have confirmed the participant details and visit number.',
        ),
        matching: find.byType(Checkbox),
      );
      tester.widget<Checkbox>(confirmationCheckbox).onChanged!(true);
      await tester.pump();

      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      final saved = await repository.getById('visit-101', admin);
      expect(saved, isNotNull);
      expect(saved!.participant.name, 'Demo Participant 1 Modified');
      expect(saved.questionnaire, isNotNull);
      expect(saved.questionnaire!.age, 52);
      expect(saved.questionnaire!.studySite, 'Site B');
    },
  );

  testWidgets('admin can archive a record without deleting it', (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = createAdminDemoRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboard(repository: repository, admin: admin),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Demo Participant 1').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive visit'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Archive visit').last);
    await tester.pumpAndSettle();

    final retained = await repository.getById('visit-101', admin);
    expect(retained, isNotNull);
    expect(retained!.isArchived, isTrue);
  });

  testWidgets('admin shows a collector Step 2 placeholder note', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = createAdminDemoRepository();
    final original = (await repository.getById('visit-101', admin))!;
    await repository.saveAdminRecord(
      actor: admin,
      record: original.copyWith(
        stepTwoPlaceholderNote: 'Participant requested a follow-up call.',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboard(repository: repository, admin: admin),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Demo Participant 1').first);
    await tester.pumpAndSettle();

    expect(find.text('Optional Step 2 note'), findsOneWidget);
    expect(
      find.text('Participant requested a follow-up call.'),
      findsOneWidget,
    );
  });

  testWidgets('background polling keeps the loaded dashboard visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final seedRepository = createAdminDemoRepository();
    final repository = _SlowSecondLoadRepository()
      ..seed(await seedRepository.listVisibleTo(admin));

    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboard(repository: repository, admin: admin),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Demo Participant 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();

    expect(repository.loadCount, 2);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Study operations'), findsOneWidget);
    expect(find.text('Demo Participant 1'), findsOneWidget);
  });

  testWidgets(
    'server outage marks cached records read-only until retry succeeds',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final seedRepository = createAdminDemoRepository();
      final repository = _IntermittentRepository()
        ..seed(await seedRepository.listVisibleTo(admin));

      await tester.pumpWidget(
        MaterialApp(home: AdminDashboard(repository: repository, admin: admin)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Demo Participant 1'), findsOneWidget);

      repository.available = false;
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not refresh — showing last loaded records'),
        findsOneWidget,
      );
      expect(find.text('Demo Participant 1'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Copy CSV'))
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('Demo Participant 1').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Edit record'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();

      repository.available = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not refresh — showing last loaded records'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'admin dashboard displays participant phone, collector ID, and study ID in table',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = createAdminDemoRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboard(repository: repository, admin: admin),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Participant'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Visit'), findsOneWidget);
      expect(find.text('Collector'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);

      expect(find.text('P012'), findsOneWidget);
      expect(find.text('+919000000001'), findsOneWidget);
      expect(find.text('collector.sana'), findsWidgets);
      expect(find.text('Visit 2'), findsWidgets);
    },
  );

  testWidgets(
    'admin dashboard displays sync conflict indicator and review state pill',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = createAdminDemoRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboard(repository: repository, admin: admin),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 sync conflict detected'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DataTable),
          matching: find.text('Sync conflict'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(DataTable),
          matching: find.text('Reviewed'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(DataTable),
          matching: find.text('Pending review'),
        ),
        findsWidgets,
      );

      await tester.tap(find.text('View conflicts'));
      await tester.pumpAndSettle();

      expect(find.text('Demo Participant 3'), findsOneWidget);
      expect(find.text('Demo Participant 1'), findsNothing);
    },
  );

  testWidgets(
    'admin dashboard searches records by phone number',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = createAdminDemoRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboard(repository: repository, admin: admin),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '+919000000003');
      await tester.pump();

      expect(find.text('Demo Participant 3'), findsOneWidget);
      expect(find.text('Demo Participant 1'), findsNothing);
      expect(find.text('Demo Participant 2'), findsNothing);
      expect(find.text('Demo Participant 4'), findsNothing);
    },
  );

  testWidgets(
    'admin dashboard strictly never contains a delete action or delete button',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = createAdminDemoRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboard(repository: repository, admin: admin),
        ),
      );
      await tester.pumpAndSettle();

      void assertNoDeleteElements() {
        expect(find.text('Delete'), findsNothing);
        expect(find.text('Delete record'), findsNothing);
        expect(find.text('Delete visit'), findsNothing);
        expect(find.byIcon(Icons.delete), findsNothing);
        expect(find.byIcon(Icons.delete_outline), findsNothing);
        expect(find.byIcon(Icons.delete_forever), findsNothing);
      }

      assertNoDeleteElements();

      // Open details modal
      await tester.tap(find.text('Demo Participant 1').first);
      await tester.pumpAndSettle();
      assertNoDeleteElements();
      expect(find.text('Archive visit'), findsOneWidget);
      expect(
        find.text(
          'Archiving is reversible. This portal never provides a permanent delete action.',
        ),
        findsOneWidget,
      );

      // Open edit modal
      await tester.tap(find.text('Edit record'));
      await tester.pumpAndSettle();
      assertNoDeleteElements();
    },
  );

  testWidgets(
    'admin dashboard displays server conflict inbox with side-by-side comparison',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _ConflictMockRepository();
      repository.seed(await createAdminDemoRepository().listVisibleTo(admin));
      repository.conflicts = [
        {
          'id': 'conflict-99',
          'status': 'pending',
          'reason': 'phone_mismatch',
          'rejectedRecord': {
            'participant': {
              'studyId': 'C01-000001',
              'name': 'Incoming Reject',
              'indianPhone': '+919876543210',
            },
            'visitNumber': 1,
            'collectorId': 'collector.alpha',
          },
          'conflictingRecord': {
            'participant': {
              'studyId': 'C01-000001',
              'name': 'Existing Conflicting',
              'indianPhone': '+919123456780',
            },
            'visitNumber': 1,
            'collectorId': 'collector.beta',
          },
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboard(repository: repository, admin: admin),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Server Conflict Inbox'), findsOneWidget);
      expect(find.text('Conflict #conflict-99'), findsOneWidget);

      expect(find.text('Rejected Record (Incoming)'), findsOneWidget);
      expect(find.text('Incoming Reject'), findsOneWidget);
      expect(find.text('+919876543210'), findsOneWidget);
      expect(find.text('collector.alpha'), findsOneWidget);

      expect(find.text('Conflicting Record (Server)'), findsOneWidget);
      expect(find.text('Existing Conflicting'), findsOneWidget);
      expect(find.text('+919123456780'), findsOneWidget);
      expect(find.text('collector.beta'), findsOneWidget);

      expect(find.text('Mark as Reviewed'), findsOneWidget);
      expect(find.text('Resolve Conflict'), findsOneWidget);
    },
  );

  testWidgets('admin marks conflict as reviewed', (tester) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _ConflictMockRepository();
    repository.seed(await createAdminDemoRepository().listVisibleTo(admin));
    repository.conflicts = [
      {
        'id': 'conflict-99',
        'status': 'pending',
        'rejectedRecord': {
          'participant': {
            'studyId': 'C01-000001',
            'name': 'Incoming Reject',
            'indianPhone': '+919876543210',
          },
          'visitNumber': 1,
          'collectorId': 'collector.alpha',
        },
        'conflictingRecord': {
          'participant': {
            'studyId': 'C01-000001',
            'name': 'Existing Conflicting',
            'indianPhone': '+919123456780',
          },
          'visitNumber': 1,
          'collectorId': 'collector.beta',
        },
      },
    ];

    await tester.pumpWidget(
      MaterialApp(home: AdminDashboard(repository: repository, admin: admin)),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Mark as Reviewed'));
    await tester.tap(find.text('Mark as Reviewed'));
    await tester.pumpAndSettle();

    expect(repository.lastReviewedId, 'conflict-99');
    expect(find.text('Conflict marked as reviewed.'), findsOneWidget);
  });

  testWidgets(
    'admin resolves conflict with corrected Study ID and visit number',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _ConflictMockRepository();
      repository.seed(await createAdminDemoRepository().listVisibleTo(admin));
      repository.conflicts = [
        {
          'id': 'conflict-99',
          'status': 'pending',
          'rejectedRecord': {
            'participant': {
              'studyId': 'C01-000001',
              'name': 'Incoming Reject',
              'indianPhone': '+919876543210',
            },
            'visitNumber': 1,
            'collectorId': 'collector.alpha',
          },
          'conflictingRecord': {
            'participant': {
              'studyId': 'C01-000001',
              'name': 'Existing Conflicting',
              'indianPhone': '+919123456780',
            },
            'visitNumber': 1,
            'collectorId': 'collector.beta',
          },
        },
      ];

      await tester.pumpWidget(
        MaterialApp(home: AdminDashboard(repository: repository, admin: admin)),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Resolve Conflict'));
      await tester.tap(find.text('Resolve Conflict'));
      await tester.pumpAndSettle();

      expect(find.text('Resolve Conflict #conflict-99'), findsOneWidget);

      // The dialog has Study ID pre-filled with C01-000001
      final studyIdField = find.widgetWithText(TextFormField, 'C01-000001');
      await tester.enterText(studyIdField, 'C01-000042');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Resolve Conflict').last);
      await tester.pumpAndSettle();

      expect(repository.lastResolvedId, 'conflict-99');
      expect(repository.lastResolution, isNotNull);
      expect(repository.lastResolution!['studyId'], 'C01-000042');
      expect(repository.lastResolution!['visitNumber'], 1);
      expect(find.text('Conflict resolved successfully.'), findsOneWidget);
    },
  );

  test('Participant ID validation contract supports C01-000001 and legacy P001', () {
    expect(isValidParticipantStudyId('C01-000001'), isTrue);
    expect(isValidParticipantStudyId('P001'), isTrue);
    expect(isValidParticipantStudyId('P012'), isTrue);
    expect(isValidParticipantStudyId('invalid-id'), isFalse);
  });
}

class _IntermittentRepository extends InMemoryVisitRepository {
  bool available = true;

  @override
  Future<List<VisitRecord>> listVisibleTo(AuthenticatedUser actor) {
    if (!available) return Future.error(StateError('server unavailable'));
    return super.listVisibleTo(actor);
  }
}

class _SlowSecondLoadRepository extends InMemoryVisitRepository {
  int loadCount = 0;
  final stalledLoad = Completer<List<VisitRecord>>();

  @override
  Future<List<VisitRecord>> listVisibleTo(AuthenticatedUser actor) {
    loadCount++;
    if (loadCount == 2) return stalledLoad.future;
    return super.listVisibleTo(actor);
  }
}

class _ConflictMockRepository extends InMemoryVisitRepository
    implements ServerConflictRepository {
  List<Map<String, dynamic>> conflicts = [];
  String? lastReviewedId;
  String? lastResolvedId;
  Map<String, dynamic>? lastResolution;

  @override
  Future<List<Map<String, dynamic>>> listConflicts({String? status}) async =>
      conflicts;

  @override
  Future<Map<String, dynamic>?> getConflict(String id) async {
    for (final c in conflicts) {
      if (c['id'] == id) return c;
    }
    return null;
  }

  @override
  Future<void> reviewConflict(String id, {String? notes}) async {
    lastReviewedId = id;
    for (final c in conflicts) {
      if (c['id'] == id) c['status'] = 'reviewed';
    }
  }

  @override
  Future<void> resolveConflict(
    String id,
    Map<String, dynamic> resolution,
  ) async {
    lastResolvedId = id;
    lastResolution = resolution;
    conflicts.removeWhere((c) => c['id'] == id);
  }
}
