import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:project2/admin/local_api_visit_repository.dart';
import 'package:project2/domain/authenticated_user.dart';

void main() {
  const admin = AuthenticatedUser(id: 'admin.test', role: UserRole.admin);

  test('loads the direct /records response shape from the local API', () async {
    final repository = LocalApiVisitRepository(
      baseUrl: 'http://127.0.0.1:8787',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'http://127.0.0.1:8787/records');
        return http.Response(jsonEncode([_recordJson()]), 200);
      }),
    );

    final records = await repository.listVisibleTo(admin);

    expect(records, hasLength(1));
    expect(records.single.participant.name, 'Test Participant');
    expect(records.single.stepTwoPlaceholderNote, 'Follow-up requested.');
    expect(records.single.isArchived, isFalse);
  });

  test(
    'sends an admin update and decodes its direct record response',
    () async {
      final repository = LocalApiVisitRepository(
        baseUrl: 'http://127.0.0.1:8787',
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/records/visit-101');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['participant']['name'], 'Test Participant');
          expect(body['stepTwoPlaceholderNote'], 'Follow-up requested.');
          return http.Response(jsonEncode(_recordJson(revision: 3)), 200);
        }),
      );
      final record = (await LocalApiVisitRepository(
        client: MockClient(
          (_) async => http.Response(jsonEncode([_recordJson()]), 200),
        ),
      ).listVisibleTo(admin)).single;

      final saved = await repository.saveAdminRecord(
        actor: admin,
        record: record,
      );

      expect(saved.revision, 3);
    },
  );

  test(
    'archives through the dedicated endpoint and retains the record',
    () async {
      final repository = LocalApiVisitRepository(
        baseUrl: 'http://127.0.0.1:8787',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/records/visit-101/archive');
          expect(jsonDecode(request.body), {
            'archived': true,
            'actor': 'admin.test',
          });
          return http.Response(jsonEncode(_recordJson(archived: true)), 200);
        }),
      );

      final archived = await repository.setArchived(
        actor: admin,
        visitId: 'visit-101',
        archived: true,
      );

      expect(archived.id, 'visit-101');
      expect(archived.isArchived, isTrue);
      expect(archived.archiveMetadata!.archivedBy, 'admin.test');
    },
  );
}

Map<String, Object?> _recordJson({int revision = 2, bool archived = false}) => {
  'id': 'visit-101',
  'participant': {
    'studyId': 'P012',
    'name': 'Test Participant',
    'indianPhone': '+919000000001',
  },
  'visitNumber': 2,
  'collectorId': 'collector.sana',
  'createdAt': '2026-09-12T06:00:00.000Z',
  'updatedAt': '2026-09-12T08:00:00.000Z',
  'status': 'submitted',
  'syncState': 'synced',
  'reviewState': 'reviewed',
  'revision': revision,
  'confirmation': {
    'name': 'Test Participant',
    'indianPhone': '+919000000001',
    'visitNumber': 2,
    'confirmedAt': '2026-09-12T08:00:00.000Z',
  },
  'stepTwoMeasurement': null,
  'stepTwoPlaceholderNote': 'Follow-up requested.',
  'submittedAt': '2026-09-12T08:00:00.000Z',
  'archivedAt': archived ? '2026-09-13T08:00:00.000Z' : null,
  'archivedBy': archived ? 'admin.test' : null,
};
