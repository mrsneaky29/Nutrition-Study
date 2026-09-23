import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:project2/local_sync/http_local_record_sync_client.dart';
import 'package:project2/local_sync/local_record_sync_gateway.dart';

void main() {
  test('generic APK does not compile a server address or collector key', () {
    expect(HttpLocalRecordSyncClient.configuredApiBaseUrl, isEmpty);
    expect(HttpLocalRecordSyncClient.configuredApiKey, isEmpty);
    expect(const String.fromEnvironment('LOCAL_COLLECTOR_ID'), isEmpty);
    expect(const String.fromEnvironment('LOCAL_COLLECTOR_NUMBER'), isEmpty);
  }, skip: !const bool.fromEnvironment('LOCAL_GENERIC_RELEASE'));

  test('same client configuration supports latest-login-wins on either phone', () async {
    const server = 'http://192.168.1.5:8787';
    const accessKey = 'synthetic-collector-key';
    String? activeToken;
    var issued = 0;
    final transport = MockClient((request) async {
      expect(request.headers['x-local-sync-key'], accessKey);
      if (request.url.path == '/collector/session') {
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {'collectorId': 'C007'});
        activeToken = 'test-session-${++issued}';
        return http.Response(
          jsonEncode({'collectorId': 'C007', 'sessionToken': activeToken}),
          200,
        );
      }
      expect(request.url.path, '/records');
      if (request.headers['x-local-session'] != activeToken) {
        return http.Response('{"error":"collector_session_expired"}', 401);
      }
      return http.Response('{"stored":true}', 201);
    });

    final firstPhone = HttpLocalRecordSyncClient(
      client: transport,
      apiBaseUrl: server,
      apiKey: accessKey,
    );
    final secondPhone = HttpLocalRecordSyncClient(
      client: transport,
      apiBaseUrl: server,
      apiKey: accessKey,
    );
    final firstToken = await firstPhone.startSession('C007');
    expect(firstToken, 'test-session-1');
    expect(
      (await firstPhone.sendRecordDetailed({'id': 'synthetic-1'})).result,
      LocalRecordSyncResult.synced,
    );

    final secondToken = await secondPhone.startSession('C007');
    expect(secondToken, 'test-session-2');
    final stale = await firstPhone.sendRecordDetailed({'id': 'synthetic-2'});
    expect(stale.statusCode, 401);
    expect(stale.result, LocalRecordSyncResult.failed);
    expect(
      (await secondPhone.sendRecordDetailed({'id': 'synthetic-3'})).result,
      LocalRecordSyncResult.synced,
    );

    // Switching back is an ordinary login; there is no permanent phone binding.
    expect(await firstPhone.startSession('C007'), 'test-session-3');
    expect(
      (await firstPhone.sendRecordDetailed({'id': 'synthetic-4'})).result,
      LocalRecordSyncResult.synced,
    );
    expect(
      (await secondPhone.sendRecordDetailed({'id': 'synthetic-5'})).statusCode,
      401,
    );
  });

  test(
    'participant lookup 401 reports a superseded session, not offline',
    () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.5:8787',
        apiKey: 'synthetic-collector-key',
        sessionToken: 'superseded-test-session',
        client: MockClient((request) async {
          expect(request.url.path, '/participants/lookup');
          expect(request.headers['x-local-session'], 'superseded-test-session');
          return http.Response('{"error":"collector_session_expired"}', 401);
        }),
      );

      await expectLater(
        client.lookupParticipant('+919000000000'),
        throwsA(isA<CollectorSessionExpiredException>()),
      );
    },
  );
}
