import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project2/admin/admin_dashboard.dart';
import 'package:project2/admin/admin_demo_data.dart';
import 'package:project2/data/in_memory_visit_repository.dart';
import 'package:project2/domain/authenticated_user.dart';
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
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(repository.loadCount, 2);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Study operations'), findsOneWidget);
    expect(find.text('Demo Participant 1'), findsOneWidget);
  });
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
