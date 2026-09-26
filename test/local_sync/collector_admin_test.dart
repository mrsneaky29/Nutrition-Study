import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:project2/collector_auth/collector_qr_payload.dart';

import '../../tool/local_sync_server.dart' as server;

void main() {
  test(
    'admin issues persistent QR credentials; existing keys and data survive',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'collector-admin-test-',
      );
      final store = server.LocalRecordStore(dir);
      await store.load();
      const keys = server.AccessKeys(
        collectorKeys: {'existing-collector-key-0123456789012345'},
        collectorIdentities: {
          'existing-collector-key-0123456789012345': 'C001',
        },
        admin: 'independent-admin-key-0123456789012345',
        requireCollectorSession: true,
      );
      final listener = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      listener.listen((r) => server.handleRequest(r, store, keys));
      final client = http.Client();
      final base = 'http://127.0.0.1:${listener.port}';
      Future<http.Response> post(
        String path,
        String key, [
        Map<String, Object?> body = const {},
      ]) => client.post(
        Uri.parse('$base$path'),
        headers: {'x-local-sync-key': key, 'content-type': 'application/json'},
        body: jsonEncode(body),
      );
      try {
        expect((await post('/collectors', '')).statusCode, 401);
        expect((await post('/collectors', keys.collector)).statusCode, 403);
        final created = await post('/collectors', keys.admin, {
          'displayName': 'Collector Two',
        });
        expect(created.statusCode, 201);
        expect(jsonDecode(created.body)['code'], 'C002');
        expect(created.body, isNot(contains('collectorKey')));
        final listing = await client.get(
          Uri.parse('$base/collectors'),
          headers: {'x-local-sync-key': keys.admin},
        );
        expect(jsonDecode(listing.body)['collectors'], hasLength(2));
        expect(listing.body, isNot(contains(keys.collector)));
        final qr = await post('/collectors/C002/qr', keys.admin);
        expect(qr.headers['cache-control'], 'no-store');
        final parsed = CollectorQrPayload.parse(qr.body);
        expect(parsed.collectorNumber, 2);
        expect(
          (await post('/collector/session', parsed.collectorKey, {
            'collectorId': 'C002',
          })).statusCode,
          200,
        );
        expect(
          (await post('/collector/session', keys.collector, {
            'collectorId': 'C001',
          })).statusCode,
          200,
        );
        final reloaded = server.LocalRecordStore(dir);
        await reloaded.load();
        reloaded.seedCollectorAccounts(keys);
        expect(reloaded.collectorIdentityForKey(parsed.collectorKey), 'C002');
        expect(reloaded.collectorIdentityForKey(keys.collector), 'C001');
        expect(
          (await post('/collectors/C002/disable', keys.admin)).statusCode,
          200,
        );
        expect(
          (await post('/collector/session', parsed.collectorKey)).statusCode,
          401,
        );
        expect((await post('/collectors/C002/qr', keys.admin)).statusCode, 403);
        final disabledReload = server.LocalRecordStore(dir);
        await disabledReload.load();
        disabledReload.seedCollectorAccounts(keys);
        expect(
          disabledReload.collectorIdentityForKey(parsed.collectorKey),
          isNull,
        );
        expect(disabledReload.listCollectorAccounts(), hasLength(2));
        expect(store.length, 0);
      } finally {
        client.close();
        await listener.close(force: true);
        await dir.delete(recursive: true);
      }
    },
  );

  test('concurrent creates use distinct sequential numbers; corruption fails closed', () async {
    final dir = await Directory.systemTemp.createTemp(
      'collector-registry-test-',
    );
    try {
      final store = server.LocalRecordStore(dir);
      await store.load();
      final values = await Future.wait(
        List.generate(5, (_) => store.createCollectorAccount(null)),
      );
      expect(values.map((v) => v['code']).toSet(), hasLength(5));
      expect(store.listCollectorAccounts().last['code'], 'C005');
      await File('${dir.path}/collector_accounts.json')
          .writeAsString('{broken');
      await expectLater(
        server.LocalRecordStore(dir).load(),
        throwsFormatException,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
