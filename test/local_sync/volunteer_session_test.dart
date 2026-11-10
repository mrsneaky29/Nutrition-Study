import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:project2/local_sync/http_local_record_sync_client.dart';
import 'package:project2/admin/local_api_visit_repository.dart';
import 'package:project2/domain/authenticated_user.dart';

import '../../tool/local_sync_server.dart' as api;

void main() {
  late Directory directory;
  late api.LocalRecordStore store;
  late HttpServer listener;
  late http.Client client;
  late String base;
  const admin = 'synthetic-admin-key-1234567890123456';
  const staff = 'synthetic-staff-key-1234567890123456';
  const key =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const keys = api.AccessKeys(
    collectorKeys: {staff},
    collectorIdentities: {staff: 'C001'},
    admin: admin,
    requireCollectorSession: true,
  );

  setUp(() async {
    api.resetAuthLimiterForTesting();
    directory = await Directory.systemTemp.createTemp('vivayu-volunteer-');
    store = api.LocalRecordStore(directory);
    await store.load();
    listener = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    listener.listen((r) => api.handleRequest(r, store, keys));
    client = http.Client();
    base = 'http://127.0.0.1:${listener.port}';
  });
  tearDown(() async {
    client.close();
    await listener.close(force: true);
    await directory.delete(recursive: true);
  });

  Future<http.Response> signup(String secret) => client.post(
    Uri.parse('$base/volunteer/session'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({'installationKey': secret}),
  );

  test('anonymous sign-in is isolated, persistent and recoverable; disable is final', () async {
    final response = await signup(key);
    expect(response.statusCode, 200);
    expect(response.headers['cache-control'], 'no-store');
    final session = jsonDecode(response.body) as Map;
    final code = session['collectorId'] as String;
    expect(code, 'C002');
    expect(session['displayName'], 'Volunteer');
    final headers = {
      'content-type': 'application/json',
      'x-local-sync-key': key,
      'x-local-session': session['sessionToken'] as String,
    };
    final saved = await client.post(
      Uri.parse('$base/records'),
      headers: headers,
      body: jsonEncode(_record(code)),
    );
    expect(saved.statusCode, 200, reason: saved.body);
    for (final path in [
      '/records',
      '/collectors',
      '/conflicts',
      '/records/volunteer-visit/research-risk',
    ]) {
      expect(
        (await client.get(
          Uri.parse('$base$path'),
          headers: headers,
        )).statusCode,
        403,
        reason: path,
      );
    }
    expect(
      (await client.post(
        Uri.parse('$base/collectors'),
        headers: headers,
        body: '{}',
      )).statusCode,
      403,
    );
    expect(
      (await client.put(
        Uri.parse('$base/records/volunteer-visit'),
        headers: headers,
        body: '{}',
      )).statusCode,
      403,
    );
    final listing = await client.get(
      Uri.parse('$base/records'),
      headers: {'x-local-sync-key': admin},
    );
    expect(
      (jsonDecode(listing.body) as List).single['collectorDisplayName'],
      'Volunteer',
    );
    expect(store.records().single.containsKey('collectorDisplayName'), false);
    final repository = LocalApiVisitRepository(
      apiKey: admin,
      baseUrl: base,
      client: client,
    );
    const actor = AuthenticatedUser(
      id: 'synthetic-admin',
      role: UserRole.admin,
    );
    final parsed = (await repository.listVisibleTo(actor)).single;
    expect(parsed.collectorLabel, 'Volunteer');
    expect(
      parsed.copyWith(revision: parsed.revision + 1).collectorLabel,
      'Volunteer',
    );
    final archived = await repository.setArchived(
      actor: actor,
      visitId: parsed.id,
      archived: true,
    );
    expect(archived.collectorLabel, 'Volunteer');
    final restored = await repository.setArchived(
      actor: actor,
      visitId: parsed.id,
      archived: false,
    );
    expect(restored.collectorLabel, 'Volunteer');
    final restarted = api.LocalRecordStore(directory);
    await restarted.load();
    expect(restarted.isVolunteer(code), true);
    expect(await restarted.openVolunteerAccount(key), code);
    expect(
      restarted
          .records(includeResearchRisk: true)
          .single['collectorDisplayName'],
      'Volunteer',
    );
    final again = jsonDecode((await signup(key)).body) as Map;
    expect(again['collectorId'], code);
    expect(again['sessionToken'], isNot(session['sessionToken']));
    expect(
      (await client.get(
        Uri.parse('$base/health'),
        headers: headers,
      )).statusCode,
      401,
    );
    await store.disableCollectorAccount(code);
    expect((await signup(key)).statusCode, 403);
  });

  test(
    'volunteers cannot discover or attach records to other collectors',
    () async {
      store.seedCollectorAccounts(keys);
      await store.upsertCollector(
        _record('C001', id: 'staff-visit', studyId: 'C01-000001'),
      );
      final session = jsonDecode((await signup(key)).body) as Map;
      final code = session['collectorId'] as String;
      final headers = {
        'content-type': 'application/json',
        'x-local-sync-key': key,
        'x-local-session': session['sessionToken'] as String,
      };
      final lookup = await client.get(
        Uri.parse('$base/participants/lookup?phone=9000000001'),
        headers: headers,
      );
      expect(jsonDecode(lookup.body), {'found': false});
      final health = await client.get(
        Uri.parse('$base/health'),
        headers: headers,
      );
      expect(jsonDecode(health.body)['records'], 0);
      for (final record in [
        _record(code, id: 'other-visit', studyId: 'C01-000001'),
        _record(code, id: 'staff-visit'),
        {..._record(code), 'idempotencyKey': 'upload-staff-visit'},
        _record('C001'),
      _record(code, studyId: 'P001'),
      ]) {
        final response = await client.post(
          Uri.parse('$base/records'),
          headers: headers,
          body: jsonEncode(record),
        );
        expect(response.statusCode, 403, reason: response.body);
        expect(response.body, isNot(contains('Fictional Participant')));
      }
      expect(store.length, 1);
    },
  );

  test(
    'invalid anonymous requests fail and registration is rate limited',
    () async {
      expect((await signup('short')).statusCode, 400);
      for (var i = 0; i < 19; i++) {
        expect((await signup(key)).statusCode, 200);
      }
      expect((await signup(key)).statusCode, 429);
      expect(
        store.listCollectorAccounts().where((a) => a['isVolunteer'] == true),
        hasLength(1),
      );
    },
  );

  test(
    'client bootstrap and regular session work without embedded credentials',
    () async {
      final bootstrap = HttpLocalRecordSyncClient(
        client: client,
        apiBaseUrl: base,
      );
      final session = await bootstrap.startVolunteerSession(key);
      final authenticated = HttpLocalRecordSyncClient(
        client: client,
        apiBaseUrl: base,
        apiKey: key,
      );
      expect(await authenticated.startSession(session.collectorId), isNotEmpty);
    },
  );
}

Map<String, dynamic> _record(
  String collector, {
  String id = 'volunteer-visit',
  String? studyId,
}) => {
  'id': id,
  'idempotencyKey': 'upload-$id',
  'participant': {
    'studyId':
        studyId ??
        'C${int.parse(collector.substring(1)).toString().padLeft(2, '0')}-000001',
    'name': 'Fictional Participant',
    'indianPhone': '+919000000001',
  },
  'collectorId': collector,
  'visitNumber': 1,
  'createdAt': '2026-11-09T00:00:00.000Z',
  'updatedAt': '2026-11-09T00:00:00.000Z',
  'status': 'submitted',
  'syncState': 'pending',
  'reviewState': 'pending',
  'revision': 1,
  'confirmation': {
    'name': 'Fictional Participant',
    'indianPhone': '+919000000001',
    'visitNumber': 1,
    'confirmedAt': '2026-11-09T00:00:00.000Z',
  },
  'stepTwoMeasurement': null,
  'questionnaire': null,
  'submittedAt': '2026-11-09T00:00:00.000Z',
};
