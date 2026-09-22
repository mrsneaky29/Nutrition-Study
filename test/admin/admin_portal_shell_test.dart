import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project2/admin/access/admin_session_gateway.dart';
import 'package:project2/admin/admin_app.dart';
import 'package:project2/admin/admin_demo_data.dart';
import 'package:project2/admin/collectors/in_memory_collector_account_gateway.dart';
import 'package:project2/domain/authenticated_user.dart';

void main() {
  const admin = AuthenticatedUser(id: 'admin.test', role: UserRole.admin);

  testWidgets('wide admin portal opens collector access from the top bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AdminPortalShell(
          repository: createAdminDemoRepository(),
          admin: admin,
          sessionGateway: const InMemoryAdminSessionGateway(admin),
          collectorGateway: InMemoryCollectorAccountGateway(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Study operations'), findsOneWidget);
    await tester.tap(find.text('Collector access').first);
    await tester.pumpAndSettle();

    expect(find.text('Collector numbers'), findsOneWidget);
    expect(find.text('Create next collector number'), findsOneWidget);
  });

  testWidgets('compact admin portal uses bottom navigation', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AdminPortalShell(
          repository: createAdminDemoRepository(),
          admin: admin,
          sessionGateway: const InMemoryAdminSessionGateway(admin),
          collectorGateway: InMemoryCollectorAccountGateway(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('Collector access').last);
    await tester.pumpAndSettle();

    expect(find.text('Collector numbers'), findsOneWidget);
  });
}
