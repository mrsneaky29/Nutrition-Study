import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:project2/local_demo_app.dart';
import 'package:project2/local_storage/local_record_store.dart';
import 'package:project2/local_sync/http_local_record_sync_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'public release restores saved HTTPS session without compiled server URL',
    (tester) async {
      expect(HttpLocalRecordSyncClient.configuredApiBaseUrl, isEmpty);

      const savedUrl = 'https://saved.example.test';
      const savedKey = 'synthetic-public-release-key';
      const savedToken = 'synthetic-restored-session';
      FlutterSecureStorage.setMockInitialValues({
        'local_server_url': savedUrl,
        'local_collector_key': savedKey,
        'local_session_token': savedToken,
        'local_collector_code': 'C007',
      });

      http.Request? observedRequest;
      final client = MockClient((request) async {
        observedRequest = request;
        return http.Response('{"stored":true}', 201);
      });
      final storage = const FlutterSecureStorage();
      final recordStore = _MemoryRecordStore([_pendingVisit()]);

      await tester.pumpWidget(
        MaterialApp(
          home: LocalDemoApp(
            recordStore: recordStore,
            secureStorage: storage,
            localHttpClient: client,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hello, Collector 7'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(observedRequest, isNotNull);
      expect(observedRequest!.url, Uri.parse('$savedUrl/records'));
      expect(observedRequest!.url.scheme, 'https');
      expect(observedRequest!.headers['x-local-sync-key'], savedKey);
      expect(observedRequest!.headers['x-local-session'], savedToken);
      expect(recordStore.records.single['syncState'], 'synced');
      expect(await storage.read(key: 'local_server_url'), savedUrl);
      expect(await storage.read(key: 'local_session_token'), savedToken);
    },
    skip: !const bool.fromEnvironment('LOCAL_GENERIC_RELEASE') ||
        !const bool.fromEnvironment('LOCAL_PUBLIC_RELEASE'),
  );
}

Map<String, Object?> _pendingVisit() => {
  'id': 'LOCAL-PENDING-PUBLIC-1',
  'participant': {
    'studyId': 'C07-1234567890123456',
    'name': 'Synthetic Participant',
    'indianPhone': '+919000000001',
  },
  'visitNumber': 1,
  'collectorId': 'C007',
  'submittedAt': '2026-09-13T00:00:00.000Z',
  'syncState': 'pending',
  'idempotencyKey': 'upload_LOCAL-PENDING-PUBLIC-1',
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
