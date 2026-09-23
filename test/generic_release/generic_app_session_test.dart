import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:project2/local_demo_app.dart';
import 'package:project2/local_storage/local_record_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('generic app sessions', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    testWidgets('sign out clears credentials and restart stays signed out', (
      tester,
    ) async {
      final server = _TestCollectorServer();
      final storage = const FlutterSecureStorage();
      final recordStore = _MemoryRecordStore([]);

      await _mountApp(tester, storage, recordStore, server);
      await _signIn(tester, server.baseUrl);
      expect(find.text('Hello, Collector 7'), findsOneWidget);
      expect(await storage.read(key: 'local_session_token'), 'session-1');
      expect(await storage.read(key: 'local_collector_key'), _accessKey);

      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(await storage.read(key: 'local_session_token'), isNull);
      expect(await storage.read(key: 'local_collector_key'), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _mountApp(tester, storage, recordStore, server);
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(find.text('Hello, Collector 7'), findsNothing);
      expect(server.sessionStarts, 1);
    });

    testWidgets(
      'restart retries pending local record and 401 signs out safely',
      (tester) async {
        final server = _TestCollectorServer();
        final storage = const FlutterSecureStorage();
        final recordStore = _MemoryRecordStore([_pendingVisit()]);

        await _mountApp(tester, storage, recordStore, server);
        await _signIn(tester, server.baseUrl);
        expect(server.recordSessionTokens, ['session-1']);
        expect(recordStore.records.single['syncState'], 'synced');

        recordStore.records = [_pendingVisit()];
        await recordStore.writeAll(recordStore.records);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        server.activeSession = 'session-from-another-phone';
        await _mountApp(tester, storage, recordStore, server);
        await tester.pumpAndSettle();

        expect(server.sessionStarts, 1);
        expect(server.recordSessionTokens, ['session-1', 'session-1']);
        expect(find.byType(TextFormField), findsNWidgets(3));
        expect(find.text('Hello, Collector 7'), findsNothing);
        expect(recordStore.records.single['id'], 'LOCAL-PENDING-1');
        expect(recordStore.records.single['syncState'], 'failed');
        expect(await storage.read(key: 'local_session_token'), isNull);
        expect(await storage.read(key: 'local_collector_key'), isNull);
      },
    );
  }, skip: !const bool.fromEnvironment('LOCAL_GENERIC_RELEASE'));
}

const _accessKey = 'synthetic-collector-access-key';

Future<void> _mountApp(
  WidgetTester tester,
  FlutterSecureStorage storage,
  LocalRecordStore recordStore,
  _TestCollectorServer server,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LocalDemoApp(
        recordStore: recordStore,
        secureStorage: storage,
        localHttpClient: server.client,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _signIn(WidgetTester tester, String serverUrl) async {
  await tester.enterText(find.byType(TextFormField).at(0), '7');
  await tester.enterText(find.byType(TextFormField).at(1), serverUrl);
  await tester.enterText(find.byType(TextFormField).at(2), _accessKey);
  await tester.ensureVisible(find.widgetWithText(FilledButton, 'Continue'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
  await tester.pumpAndSettle();
}

Map<String, Object?> _pendingVisit() => {
  'id': 'LOCAL-PENDING-1',
  'participant': {
    'studyId': 'C07-1234567890123456',
    'name': 'Synthetic Participant',
    'indianPhone': '+919000000001',
  },
  'visitNumber': 1,
  'collectorId': 'C007',
  'submittedAt': '2026-09-13T00:00:00.000Z',
  'syncState': 'pending',
  'idempotencyKey': 'upload_LOCAL-PENDING-1',
};

class _MemoryRecordStore implements LocalRecordStore {
  _MemoryRecordStore(this.records);

  List<Map<String, Object?>> records;

  @override
  Future<List<Map<String, Object?>>> readAll() async => records
      .map(
        (record) => (jsonDecode(jsonEncode(record)) as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      )
      .toList();

  @override
  Future<void> writeAll(List<Map<String, Object?>> newRecords) async {
    records = newRecords
        .map(
          (record) => (jsonDecode(jsonEncode(record)) as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList();
  }
}

class _TestCollectorServer {
  _TestCollectorServer() {
    client = MockClient(_handleRequest);
  }

  late final MockClient client;
  String? activeSession;
  int sessionStarts = 0;
  final List<String?> recordSessionTokens = [];

  String get baseUrl => 'http://study.test:8787';

  Future<http.Response> _handleRequest(http.Request request) async {
    if (request.method == 'POST' && request.url.path == '/collector/session') {
      final payload = jsonDecode(request.body) as Map;
      sessionStarts++;
      activeSession = 'session-$sessionStarts';
      return http.Response(
        jsonEncode({
          'collectorId': payload['collectorId'],
          'sessionToken': activeSession,
        }),
        200,
      );
    }
    if (request.method == 'POST' && request.url.path == '/records') {
      recordSessionTokens.add(request.headers['x-local-session']);
      if (request.headers['x-local-session'] != activeSession) {
        return http.Response('{"error":"collector_session_expired"}', 401);
      }
      return http.Response('{"stored":true}', 201);
    }
    return http.Response('{"error":"not_found"}', 404);
  }
}
