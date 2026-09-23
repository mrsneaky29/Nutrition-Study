import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/local_sync_server.dart' as server;

void main() {
  test('latest collector login wins and survives server restart', () async {
    final dir = await Directory.systemTemp.createTemp('study-session-test-');
    final store = server.LocalRecordStore(dir);
    await store.load();
    const key = 'collector-test-key-long-enough';
    const keys = server.AccessKeys(
      collectorKeys: {key},
      admin: 'admin-test-key-long-enough',
      collectorIdentities: {key: 'C001'},
      requireCollectorSession: true,
    );
    final listener = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    listener.listen((request) => server.handleRequest(request, store, keys));
    final client = HttpClient();
    try {
      Future<String> login() async {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:${listener.port}/collector/session'),
        );
        request.headers.set('x-local-sync-key', key);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'collectorId': 'C001'}));
        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok);
        final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
        return body['sessionToken'] as String;
      }

      Future<int> health(String token) async {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${listener.port}/health'),
        );
        request.headers.set('x-local-sync-key', key);
        request.headers.set('x-local-session', token);
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      final first = await login();
      expect(await health(first), HttpStatus.ok);
      final second = await login();
      expect(second, isNot(first));
      expect(await health(first), HttpStatus.unauthorized);
      expect(await health(second), HttpStatus.ok);

      final reloaded = server.LocalRecordStore(dir);
      await reloaded.load();
      expect(reloaded.isCurrentCollectorSession('C001', first), isFalse);
      expect(reloaded.isCurrentCollectorSession('C001', second), isTrue);
    } finally {
      client.close(force: true);
      await listener.close(force: true);
      await dir.delete(recursive: true);
    }
  });
}
