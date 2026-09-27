import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project2/admin/admin_dashboard.dart';
import 'package:project2/admin/admin_demo_data.dart';
import 'package:project2/admin/local_api_visit_repository.dart';
import 'package:project2/domain/authenticated_user.dart';
import 'package:project2/domain/visit_record.dart';

class _MalformedRepository extends LocalApiVisitRepository {
  _MalformedRepository(this.records) : super(apiKey: 'synthetic-only');
  final List<VisitRecord> records;
  var malformed = true;
  @override
  Future<List<VisitRecord>> listVisibleTo(AuthenticatedUser actor) async {
    malformedRecordCount = malformed ? 1 : 0;
    return records;
  }

  @override
  Future<List<Map<String, dynamic>>> listConflicts({String? status}) async =>
      [];
}

void main() {
  testWidgets(
    'malformed warning blocks partial export and clears after repair',
    (tester) async {
      const admin = AuthenticatedUser(id: 'admin.test', role: UserRole.admin);
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final records = await createAdminDemoRepository().listVisibleTo(admin);
      final repo = _MalformedRepository(records);
      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboard(repository: repo, admin: admin),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1 malformed server records'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Copy CSV'),
            )
            .onPressed,
        isNull,
      );
      repo.malformed = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.textContaining('malformed server records'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Copy CSV'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      repo.close();
    },
  );
}
