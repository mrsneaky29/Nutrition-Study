import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/local_sync_server.dart' as server;

void main() {
  test('interrupted session replacement invalidates all old tokens without losing records', () async {
    final directory = await Directory.systemTemp.createTemp(
      'study-session-recover-',
    );
    try {
      final store = server.LocalRecordStore(directory);
      await store.load();
      final token = await store.openCollectorSession('C001');
      await store.upsertCollector(
        _submission('saved-visit'),
        authenticatedCollectorId: 'C001',
        collectorSessionToken: token,
      );
      final primary = File(
        '${directory.path}${Platform.pathSeparator}collector_sessions.json',
      );
      final backup = File('${primary.path}.bak');
      await primary.copy(backup.path);
      await primary.delete();

      final recovered = server.LocalRecordStore(directory);
      await recovered.load();
      expect(recovered.records(), hasLength(1));
      expect(recovered.isCurrentCollectorSession('C001', token), isFalse);
      final newToken = await recovered.openCollectorSession('C001');
      expect(recovered.isCurrentCollectorSession('C001', newToken), isTrue);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('corrupt session state does not revive a superseded phone', () async {
    final directory = await Directory.systemTemp.createTemp(
      'study-session-corrupt-',
    );
    try {
      final store = server.LocalRecordStore(directory);
      await store.load();
      final token = await store.openCollectorSession('C001');
      final primary = File(
        '${directory.path}${Platform.pathSeparator}collector_sessions.json',
      );
      await primary.writeAsString('{invalid json', flush: true);

      final recovered = server.LocalRecordStore(directory);
      await recovered.load();
      expect(recovered.isCurrentCollectorSession('C001', token), isFalse);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'an upload queued before a newer login cannot write afterward',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'study-session-race-',
      );
      try {
        final store = server.LocalRecordStore(directory);
        await store.load();

        final oldToken = await store.openCollectorSession('C001');
        // This is the request-handler check, before it reads the request body.
        expect(store.isCurrentCollectorSession('C001', oldToken), isTrue);

        final newToken = await store.openCollectorSession('C001');
        expect(newToken, isNot(oldToken));

        await expectLater(
          store.upsertCollector(
            _submission('stale-visit'),
            authenticatedCollectorId: 'C001',
            collectorSessionToken: oldToken,
          ),
          throwsA(
            isA<server.ApiException>()
                .having(
                  (error) => error.statusCode,
                  'status',
                  HttpStatus.unauthorized,
                )
                .having(
                  (error) => error.errorName,
                  'error',
                  'collector_session_expired',
                ),
          ),
        );
        expect(store.records(), isEmpty);

        final accepted = await store.upsertCollector(
          _submission('current-visit'),
          authenticatedCollectorId: 'C001',
          collectorSessionToken: newToken,
        );
        expect(accepted['id'], 'current-visit');
        expect(store.records(), hasLength(1));
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}

Map<String, dynamic> _submission(String id) => {
  'id': id,
  'idempotencyKey': 'upload-$id',
  'participant': {
    'studyId': 'C01-000001',
    'name': 'Fictional Participant',
    'indianPhone': '+919000000001',
  },
  'visitNumber': 1,
  'collectorId': 'C001',
  'createdAt': '2026-09-13T00:00:00.000Z',
  'updatedAt': '2026-09-13T00:00:00.000Z',
  'status': 'submitted',
  'syncState': 'pending',
  'reviewState': 'pending',
  'revision': 1,
  'confirmation': {
    'name': 'Fictional Participant',
    'indianPhone': '+919000000001',
    'visitNumber': 1,
    'confirmedAt': '2026-09-13T00:00:00.000Z',
  },
  'stepTwoMeasurement': null,
  'questionnaire': null,
  'submittedAt': '2026-09-13T00:00:00.000Z',
};
