import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../tool/local_sync_server.dart';

Map<String, dynamic> _makeRecord({
  required String id,
  required String studyId,
  required String name,
  required String phone,
  required int visitNumber,
  required String collectorId,
  required String idempotencyKey,
}) => {
  'id': id,
  'idempotencyKey': idempotencyKey,
  'participant': {
    'studyId': studyId,
    'name': name,
    'indianPhone': phone,
  },
  'visitNumber': visitNumber,
  'collectorId': collectorId,
  'createdAt': '2026-09-23T06:00:00.000Z',
  'updatedAt': '2026-09-23T06:00:00.000Z',
  'status': 'submitted',
  'syncState': 'synced',
  'reviewState': 'pending',
  'revision': 1,
  'confirmation': {
    'name': name,
    'indianPhone': phone,
    'visitNumber': visitNumber,
    'confirmedAt': '2026-09-23T06:00:00.000Z',
  },
  'submittedAt': '2026-09-23T06:00:00.000Z',
};

void main() {
  late Directory tempDir;
  late HttpServer server;
  late LocalRecordStore store;
  late AccessKeys accessKeys;
  late String baseUrl;

  const collector1Key = 'collector-1-key-at-least-16-chars';
  const collector2Key = 'collector-2-key-at-least-16-chars';
  const adminKey = 'admin-secret-key-at-least-16-chars';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('study-e2e-');
    accessKeys = AccessKeys(
      collectorKeys: {collector1Key, collector2Key},
      admin: adminKey,
      collectorIdentities: {
        collector1Key: 'C001',
        collector2Key: 'C002',
      },
    );
    store = LocalRecordStore(tempDir);
    await store.load();

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.host}:${server.port}';
    server.listen((request) => handleRequest(request, store, accessKeys));
  });

  tearDown(() async {
    await server.close(force: true);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('E2E: two collectors, repeat visit by different collector, conflict inbox, resolve & retry, server restart & backup recovery', () async {
    final client = http.Client();
    addTearDown(client.close);

    // 1. Health check works for both collectors and admin
    final healthC1 = await client.get(
      Uri.parse('$baseUrl/health'),
      headers: {'x-local-sync-key': collector1Key},
    );
    expect(healthC1.statusCode, 200);

    final healthAdmin = await client.get(
      Uri.parse('$baseUrl/health'),
      headers: {'x-local-sync-key': adminKey},
    );
    expect(healthAdmin.statusCode, 200);

    // 2. Collector 1 enrolls participant C01-000001 (Visit 1)
    final visit1Payload = _makeRecord(
      id: 'VISIT-C01-1',
      studyId: 'C01-000001',
      name: 'Participant Alpha',
      phone: '+919876543210',
      visitNumber: 1,
      collectorId: 'C001',
      idempotencyKey: 'upload_c1_v1',
    );

    final upload1 = await client.post(
      Uri.parse('$baseUrl/records'),
      headers: {
        'x-local-sync-key': collector1Key,
        'content-type': 'application/json',
      },
      body: jsonEncode(visit1Payload),
    );
    expect(upload1.statusCode, 200);
    expect(jsonDecode(upload1.body)['id'], 'VISIT-C01-1');

    // 3. Collector 2 uses online lookup to find Participant Alpha by phone
    final lookup = await client.get(
      Uri.parse('$baseUrl/participants/lookup?phone=%2B919876543210'),
      headers: {'x-local-sync-key': collector2Key},
    );
    expect(lookup.statusCode, 200);
    final lookupJson = jsonDecode(lookup.body);
    expect(lookupJson['found'], isTrue);
    expect(lookupJson['participant']['studyId'], 'C01-000001');
    expect(lookupJson['participant']['name'], 'Participant Alpha');
    expect(lookupJson['participant']['nextVisitNumber'], 2);

    // 4. Collector 2 conducts repeat Visit 2 for Participant Alpha
    final visit2Payload = _makeRecord(
      id: 'VISIT-C02-2',
      studyId: 'C01-000001',
      name: 'Participant Alpha',
      phone: '+919876543210',
      visitNumber: 2,
      collectorId: 'C002',
      idempotencyKey: 'upload_c2_v2',
    );

    final upload2 = await client.post(
      Uri.parse('$baseUrl/records'),
      headers: {
        'x-local-sync-key': collector2Key,
        'content-type': 'application/json',
      },
      body: jsonEncode(visit2Payload),
    );
    expect(upload2.statusCode, 200);
    expect(jsonDecode(upload2.body)['id'], 'VISIT-C02-2');

    // 5. Collector 1 cannot spoof Collector 2's ID
    final spoofPayload = Map<String, dynamic>.from(visit1Payload)
      ..['id'] = 'SPOOF-1'
      ..['collectorId'] = 'C002';
    final spoofRes = await client.post(
      Uri.parse('$baseUrl/records'),
      headers: {
        'x-local-sync-key': collector1Key,
        'content-type': 'application/json',
      },
      body: jsonEncode(spoofPayload),
    );
    expect(spoofRes.statusCode, 403);

    // 6. Conflicting upload: Collector 2 uploads another Visit 2 for same participant -> 409 Conflict
    final duplicateVisitPayload = _makeRecord(
      id: 'VISIT-CONFLICT-1',
      studyId: 'C01-000001',
      name: 'Participant Alpha',
      phone: '+919876543210',
      visitNumber: 2, // duplicate visit number!
      collectorId: 'C002',
      idempotencyKey: 'upload_conflict_1',
    );

    final conflictRes = await client.post(
      Uri.parse('$baseUrl/records'),
      headers: {
        'x-local-sync-key': collector2Key,
        'content-type': 'application/json',
      },
      body: jsonEncode(duplicateVisitPayload),
    );
    expect(conflictRes.statusCode, 409);
    final conflictJson = jsonDecode(conflictRes.body);
    expect(conflictJson['error'], 'conflict');
    final conflictId = conflictJson['conflictId'] as String;
    expect(conflictId, isNotEmpty);

    // 7. Admin inspects the conflict in the conflict inbox
    final listConflicts = await client.get(
      Uri.parse('$baseUrl/conflicts'),
      headers: {'x-local-sync-key': adminKey},
    );
    expect(listConflicts.statusCode, 200);
    final conflictsList = jsonDecode(listConflicts.body) as List;
    expect(conflictsList, hasLength(1));
    expect(conflictsList.first['id'], conflictId);
    expect(conflictsList.first['status'], 'pending');

    // 8. Admin reviews the conflict
    final reviewRes = await client.post(
      Uri.parse('$baseUrl/conflicts/$conflictId/review'),
      headers: {
        'x-local-sync-key': adminKey,
        'content-type': 'application/json',
      },
      body: jsonEncode({'notes': 'Collector accidentally re-entered visit 2 instead of visit 3'}),
    );
    expect(reviewRes.statusCode, 200);

    // 9. Admin resolves the conflict by correcting visitNumber to 3
    final resolveRes = await client.post(
      Uri.parse('$baseUrl/conflicts/$conflictId/resolve'),
      headers: {
        'x-local-sync-key': adminKey,
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'action': 'accept_as_corrected',
        'visitNumber': 3,
      }),
    );
    expect(resolveRes.statusCode, 200);

    // 10. Collector retries upload idempotently -> now accepted as 200 OK!
    final retryRes = await client.post(
      Uri.parse('$baseUrl/records'),
      headers: {
        'x-local-sync-key': collector2Key,
        'content-type': 'application/json',
      },
      body: jsonEncode(duplicateVisitPayload),
    );
    expect(retryRes.statusCode, 200);

    // Verify exactly 3 accepted records exist for Participant Alpha (Visits 1, 2, 3)
    final adminRecords = await client.get(
      Uri.parse('$baseUrl/records'),
      headers: {'x-local-sync-key': adminKey},
    );
    expect(adminRecords.statusCode, 200);
    final allRecords = jsonDecode(adminRecords.body) as List;
    expect(allRecords, hasLength(3));

    // 11. Server restart & backup recovery:
    // Corrupt the primary records file with garbage
    await store.recordsFile.writeAsString('CORRUPTED-NOT-JSON', flush: true);

    // Create a new store instance pointing to same directory and reload
    final recoveredStore = LocalRecordStore(tempDir);
    await recoveredStore.load();
    // It seamlessly recovered from .bak!
    expect(recoveredStore.records().length, greaterThanOrEqualTo(1));
  });
}
