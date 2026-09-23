import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/local_sync_server.dart' as server;

void main() {
  test(
    'duplicate record IDs on disk fail closed without replacing either file',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'study-duplicate-id-',
      );
      try {
        final store = server.LocalRecordStore(directory);
        await store.load();
        final first = await store.upsertCollector(
          _submission(
            id: 'visit-first',
            key: 'upload-first',
            studyId: 'P001',
            phone: '+919000000001',
          ),
        );
        await store.upsertCollector(
          _submission(
            id: 'visit-second',
            key: 'upload-second',
            studyId: 'P002',
            phone: '+919000000002',
          ),
        );

        // The two rows are distinct, but a damaged/imported file has reused one ID.
        final second = store.records().firstWhere(
          (record) => record['id'] == 'visit-second',
        );
        final duplicateRows = [
          first,
          {...second, 'id': first['id']},
        ];
        final duplicateJson = jsonEncode(duplicateRows);
        await store.recordsFile.writeAsString(duplicateJson, flush: true);
        final backupFile = File('${store.recordsFile.path}.bak');
        final backupBeforeLoad = await backupFile.readAsString();

        final recovered = server.LocalRecordStore(directory);
        await expectLater(
          recovered.load(),
          throwsA(isA<server.DuplicateStoredRecordIdException>()),
        );

        expect(await store.recordsFile.readAsString(), duplicateJson);
        expect(await backupFile.readAsString(), backupBeforeLoad);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}

Map<String, dynamic> _submission({
  required String id,
  required String key,
  required String studyId,
  required String phone,
}) => {
  'id': id,
  'idempotencyKey': key,
  'participant': {
    'studyId': studyId,
    'name': 'Synthetic Participant $studyId',
    'indianPhone': phone,
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
    'name': 'Synthetic Participant $studyId',
    'indianPhone': phone,
    'visitNumber': 1,
    'confirmedAt': '2026-09-13T00:00:00.000Z',
  },
  'stepTwoMeasurement': null,
  'questionnaire': null,
  'submittedAt': '2026-09-13T00:00:00.000Z',
};
