import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:project2/local_demo_app.dart';
import 'package:project2/local_storage/local_record_store.dart';
import 'package:project2/presentation/sign_in_screen.dart';

void main() {
  testWidgets(
    'production volunteer sign-in asks nothing and survives logout and restart',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final installationKeys = <String>[];
      final client = MockClient((request) async {
        if (request.url.path == '/volunteer/session') {
          expect(request.headers.containsKey('x-local-sync-key'), false);
          final body = jsonDecode(request.body) as Map;
          expect(body.keys, ['installationKey']);
          final key = body['installationKey'] as String;
          expect(key, matches(RegExp(r'^[a-f0-9]{64}$')));
          installationKeys.add(key);
          return http.Response(
            jsonEncode({
              'collectorId': 'C002',
              'sessionToken': 'synthetic-volunteer-session-token-0123456',
              'displayName': 'Volunteer',
            }),
            200,
          );
        }
        if (request.url.path == '/collector/session') {
          expect(jsonDecode(request.body)['collectorId'], 'C002');
          expect(request.headers['x-local-sync-key'], installationKeys.last);
          return http.Response(
            jsonEncode({
              'collectorId': 'C002',
              'sessionToken': 'synthetic-restored-session-token-0123456',
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });
      final records = _Records();
      Widget app() => MaterialApp(
        home: LocalDemoApp(
          recordStore: records,
          localHttpClient: client,
          secureStorage: const FlutterSecureStorage(),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Scan sign-in QR'), findsOneWidget);
      final button = find.byKey(const Key('volunteer-sign-in'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Hello, Volunteer'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(installationKeys, hasLength(2));
      expect(installationKeys[0], installationKeys[1]);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Hello, Volunteer'), findsOneWidget);
      expect(find.byType(SignInScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
    skip:
        !const bool.fromEnvironment('LOCAL_GENERIC_RELEASE') ||
        !const bool.fromEnvironment('LOCAL_PUBLIC_RELEASE'),
  );
}

class _Records implements LocalRecordStore {
  @override
  Future<List<Map<String, Object?>>> readAll() async => [];
  @override
  Future<void> writeAll(List<Map<String, Object?>> records) async {}
}
