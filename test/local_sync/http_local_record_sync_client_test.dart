import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:project2/local_sync/http_local_record_sync_client.dart';
import 'package:project2/local_sync/local_record_sync_gateway.dart';

void main() {
  test(
    'posts a VisitRecord-shaped payload to the configured LAN endpoint',
    () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url, Uri.parse('http://192.168.1.20:8787/records'));
          expect(request.headers['content-type'], 'application/json');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['id'], 'LOCAL-1');
          expect(body['syncState'], 'synced');
          expect(body['participant']['indianPhone'], '+919000000001');
          expect(body['confirmation']['visitNumber'], 1);
          return http.Response('{"id":"LOCAL-1"}', 201);
        }),
      );

      final result = await client.sendRecord(_record());

      expect(result, LocalRecordSyncResult.synced);
    },
  );

  test(
    'keeps records pending when no physical-LAN endpoint is configured',
    () async {
      var requested = false;
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: '',
        client: MockClient((_) async {
          requested = true;
          return http.Response('', 200);
        }),
      );

      final result = await client.sendRecord(_record());

      expect(result, LocalRecordSyncResult.pending);
      expect(requested, isFalse);
    },
  );
}

Map<String, Object?> _record() => {
  'id': 'LOCAL-1',
  'participant': {
    'studyId': 'P001',
    'name': 'Test Participant',
    'indianPhone': '+919000000001',
  },
  'visitNumber': 1,
  'collectorId': 'collector@demo.local',
  'createdAt': '2026-09-13T00:00:00.000Z',
  'updatedAt': '2026-09-13T00:00:00.000Z',
  'status': 'submitted',
  'syncState': 'synced',
  'reviewState': 'pending',
  'revision': 1,
  'confirmation': {
    'name': 'Test Participant',
    'indianPhone': '+919000000001',
    'visitNumber': 1,
    'confirmedAt': '2026-09-13T00:00:00.000Z',
  },
  'stepTwoMeasurement': null,
  'submittedAt': '2026-09-13T00:00:00.000Z',
};
