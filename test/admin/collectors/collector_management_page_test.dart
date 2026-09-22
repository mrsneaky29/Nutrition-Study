import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project2/admin/access/admin_session_gateway.dart';
import 'package:project2/admin/collectors/collector_account.dart';
import 'package:project2/admin/collectors/collector_management_page.dart';
import 'package:project2/admin/collectors/in_memory_collector_account_gateway.dart';
import 'package:project2/domain/authenticated_user.dart';

void main() {
  const admin = AuthenticatedUser(id: 'admin.pilot', role: UserRole.admin);

  Widget page(InMemoryCollectorAccountGateway gateway) => MaterialApp(
    home: CollectorManagementPage(
      sessionGateway: const InMemoryAdminSessionGateway(admin),
      collectorGateway: gateway,
    ),
  );

  testWidgets('requires an authenticated administrator session', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CollectorManagementPage(
          sessionGateway: const InMemoryAdminSessionGateway(null),
          collectorGateway: InMemoryCollectorAccountGateway(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Administrator sign-in required'), findsOneWidget);
    expect(find.text('Create next collector number'), findsNothing);
  });

  testWidgets('creates the next sequential collector number', (tester) async {
    final gateway = InMemoryCollectorAccountGateway(
      seed: [
        CollectorAccount(
          code: 'C001',
          status: CollectorAccountStatus.active,
          createdAt: DateTime.utc(2026),
        ),
      ],
    );
    await tester.pumpWidget(page(gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create next collector number'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Riya');
    await tester.tap(find.text('Create number'));
    await tester.pumpAndSettle();

    expect(find.text('Collector 2'), findsOneWidget);
    expect(find.text('Riya'), findsOneWidget);
    expect(find.text('Collector created.'), findsOneWidget);
  });

  testWidgets('resets a bound device and retains the collector account', (
    tester,
  ) async {
    final gateway = InMemoryCollectorAccountGateway(
      seed: [
        CollectorAccount(
          code: 'C007',
          status: CollectorAccountStatus.active,
          createdAt: DateTime.utc(2026),
          deviceBinding: CollectorDeviceBinding(
            label: 'Galaxy M14',
            boundAt: DateTime.utc(2026, 9, 14),
          ),
        ),
      ],
    );
    await tester.pumpWidget(page(gateway));
    await tester.pumpAndSettle();

    expect(find.textContaining('Bound to Galaxy M14'), findsOneWidget);
    await tester.tap(find.text('Reset device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset device access'));
    await tester.pumpAndSettle();

    expect(find.text('Collector 7'), findsOneWidget);
    expect(find.text('No phone currently bound'), findsOneWidget);
    expect(find.text('Collector 7 device access reset.'), findsOneWidget);
  });

  testWidgets(
    'disabling keeps the collector account visible and has no delete action',
    (tester) async {
      final gateway = InMemoryCollectorAccountGateway(
        seed: [
          CollectorAccount(
            code: 'C003',
            status: CollectorAccountStatus.active,
            createdAt: DateTime.utc(2026),
          ),
        ],
      );
      await tester.pumpWidget(page(gateway));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Disable collector'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disable collector').last);
      await tester.pumpAndSettle();

      expect(find.text('Collector 3'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
      expect(find.text('Disable collector'), findsNothing);
      expect(find.textContaining('Delete'), findsNothing);
    },
  );
}
