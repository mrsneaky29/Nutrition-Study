import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:project2/admin/local_api_visit_repository.dart';
import 'package:project2/domain/authenticated_user.dart';
import 'package:project2/domain/ncd_questionnaire.dart';
import 'package:project2/domain/visit_record.dart';

void main() {
  const admin = AuthenticatedUser(id: 'admin.test', role: UserRole.admin);

  test('loads the direct /records response shape from the local API', () async {
    final repository = LocalApiVisitRepository(
      apiKey: 'admin-test-key-123',
      baseUrl: 'http://127.0.0.1:8787',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'http://127.0.0.1:8787/records');
        expect(request.headers['x-local-sync-key'], 'admin-test-key-123');
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
        apiKey: 'admin-test-key-123',
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
        apiKey: 'admin-test-key-123',
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
        apiKey: 'admin-test-key-123',
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

  test(
    'unarchives through the dedicated endpoint and restores the record',
    () async {
      final repository = LocalApiVisitRepository(
        apiKey: 'admin-test-key-123',
        baseUrl: 'http://127.0.0.1:8787',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/records/visit-101/archive');
          expect(jsonDecode(request.body), {
            'archived': false,
            'actor': 'admin.test',
          });
          return http.Response(jsonEncode(_recordJson(archived: false)), 200);
        }),
      );

      final restored = await repository.setArchived(
        actor: admin,
        visitId: 'visit-101',
        archived: false,
      );

      expect(restored.id, 'visit-101');
      expect(restored.isArchived, isFalse);
      expect(restored.archiveMetadata, isNull);
    },
  );

  test(
    'decodes records with sync conflict, neutral review states, and phone',
    () async {
      final repository = LocalApiVisitRepository(
        apiKey: 'admin-test-key-123',
        client: MockClient((request) async {
          final conflictRecord = _recordJson()
            ..['syncState'] = 'failed'
            ..['reviewState'] = 'pending'
            ..['participant'] = {
              'studyId': 'P012',
              'name': 'Conflict Participant',
              'indianPhone': '+919876543210',
            };
          return http.Response(jsonEncode([conflictRecord]), 200);
        }),
      );

      final records = await repository.listVisibleTo(admin);
      expect(records, hasLength(1));
      final record = records.single;
      expect(record.syncState, SyncState.failed);
      expect(record.reviewState, NeutralReviewState.pending);
      expect(record.participant.name, 'Conflict Participant');
      expect(record.participant.indianPhone, '+919876543210');
      expect(record.participant.studyId, 'P012');
      expect(record.collectorId, 'collector.sana');
      expect(record.visitNumber, 2);
    },
  );

  test(
    'decodes records with safe null defaults for missing syncState and reviewState',
    () async {
      final repository = LocalApiVisitRepository(
        apiKey: 'admin-test-key-123',
        client: MockClient((request) async {
          final minimalRecord = _recordJson()
            ..remove('syncState')
            ..remove('reviewState')
            ..['stepTwoPlaceholderNote'] = '';
          return http.Response(jsonEncode([minimalRecord]), 200);
        }),
      );

      final records = await repository.listVisibleTo(admin);
      expect(records, hasLength(1));
      final record = records.single;
      expect(record.syncState, SyncState.synced);
      expect(record.reviewState, NeutralReviewState.pending);
      expect(record.stepTwoPlaceholderNote, isNull);
    },
  );

  group('Server conflict inbox API', () {
    test('listConflicts sends GET /conflicts and decodes items', () async {
      final repository = LocalApiVisitRepository(
        apiKey: 'admin-test-key-123',
        baseUrl: 'http://127.0.0.1:8787',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/conflicts');
          expect(request.headers['x-local-sync-key'], 'admin-test-key-123');
          return http.Response(
            jsonEncode([
              {
                'id': 'conflict-1',
                'status': 'pending',
                'reason': 'participant_mismatch',
                'rejectedRecord': {
                  'participant': {
                    'studyId': 'C01-000001',
                    'name': 'Incoming Participant',
                    'indianPhone': '+919876543210',
                  },
                  'visitNumber': 1,
                  'collectorId': 'collector.1',
                },
                'conflictingRecord': {
                  'participant': {
                    'studyId': 'C01-000001',
                    'name': 'Existing Participant',
                    'indianPhone': '+919876543211',
                  },
                  'visitNumber': 1,
                  'collectorId': 'collector.2',
                },
              },
            ]),
            200,
          );
        }),
      );

      final conflicts = await repository.listConflicts();
      expect(conflicts, hasLength(1));
      expect(conflicts.first['id'], 'conflict-1');
      expect(conflicts.first['status'], 'pending');
      expect(
        conflicts.first['rejectedRecord']['participant']['studyId'],
        'C01-000001',
      );
    });

    test('listConflicts includes status query parameter when provided', () async {
      final repository = LocalApiVisitRepository(
        apiKey: 'admin-test-key-123',
        baseUrl: 'http://127.0.0.1:8787',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.toString(), 'http://127.0.0.1:8787/conflicts?status=pending');
          return http.Response(jsonEncode([]), 200);
        }),
      );

      final conflicts = await repository.listConflicts(status: 'pending');
      expect(conflicts, isEmpty);
    });

    test('getConflict returns conflict when found and null on 404', () async {
      final repository = LocalApiVisitRepository(
        apiKey: 'admin-test-key-123',
        baseUrl: 'http://127.0.0.1:8787',
        client: MockClient((request) async {
          if (request.url.path == '/conflicts/conflict-1') {
            return http.Response(
              jsonEncode({
                'id': 'conflict-1',
                'status': 'pending',
              }),
              200,
            );
          }
          return http.Response('Not Found', 404);
        }),
      );

      final conflict = await repository.getConflict('conflict-1');
      expect(conflict, isNotNull);
      expect(conflict!['id'], 'conflict-1');

      final notFound = await repository.getConflict('conflict-missing');
      expect(notFound, isNull);
    });

    test('reviewConflict sends POST /conflicts/:id/review with notes', () async {
      final repository = LocalApiVisitRepository(
        apiKey: 'admin-test-key-123',
        baseUrl: 'http://127.0.0.1:8787',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/conflicts/conflict-1/review');
          expect(request.headers['x-local-sync-key'], 'admin-test-key-123');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['notes'], 'Reviewed by lead supervisor');
          return http.Response(jsonEncode({'status': 'reviewed'}), 200);
        }),
      );

      await expectLater(
        repository.reviewConflict(
          'conflict-1',
          notes: 'Reviewed by lead supervisor',
        ),
        completes,
      );
    });

    test('resolveConflict sends POST /conflicts/:id/resolve with resolution map', () async {
      final repository = LocalApiVisitRepository(
        apiKey: 'admin-test-key-123',
        baseUrl: 'http://127.0.0.1:8787',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/conflicts/conflict-1/resolve');
          expect(request.headers['x-local-sync-key'], 'admin-test-key-123');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['action'], 'accept_corrected');
          expect(body['studyId'], 'C01-000002');
          expect(body['visitNumber'], 2);
          return http.Response(jsonEncode({'status': 'resolved'}), 200);
        }),
      );

      await expectLater(
        repository.resolveConflict('conflict-1', {
          'action': 'accept_corrected',
          'studyId': 'C01-000002',
          'visitNumber': 2,
        }),
        completes,
      );
    });
  });

  group('Questionnaire and Participant ID preservation', () {
    test('saveAdminRecord preserves questionnaire in payload and response', () async {
      final qMap = _sampleQuestionnaire().toMap();
      final repository = LocalApiVisitRepository(
        apiKey: 'admin-test-key-123',
        baseUrl: 'http://127.0.0.1:8787',
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/records/visit-101');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['questionnaire'], isNotNull);
          expect(body['questionnaire']['age'], 45);
          expect(body['questionnaire']['studySite'], 'Site A');

          final responseJson = _recordJson(revision: 3)..['questionnaire'] = qMap;
          return http.Response(jsonEncode(responseJson), 200);
        }),
      );

      final record = (await LocalApiVisitRepository(
        apiKey: 'admin-test-key-123',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode([_recordJson()..['questionnaire'] = qMap]),
            200,
          ),
        ),
      ).listVisibleTo(admin)).single;

      expect(record.questionnaire, isNotNull);
      expect(record.questionnaire!.age, 45);

      final saved = await repository.saveAdminRecord(
        actor: admin,
        record: record,
      );

      expect(saved.revision, 3);
      expect(saved.questionnaire, isNotNull);
      expect(saved.questionnaire!.age, 45);
      expect(saved.questionnaire!.studySite, 'Site A');
    });

    test('supports both C01-000001 and legacy P001 participant study IDs', () async {
      final repository = LocalApiVisitRepository(
        apiKey: 'admin-test-key-123',
        client: MockClient((_) async {
          final cRecord = _recordJson()..['participant'] = {
            'studyId': 'C01-000001',
            'name': 'Collector Scoped',
            'indianPhone': '+919000000001',
          };
          final pRecord = _recordJson()..['id'] = 'visit-102'..['participant'] = {
            'studyId': 'P001',
            'name': 'Legacy Demo',
            'indianPhone': '+919000000002',
          };
          return http.Response(jsonEncode([cRecord, pRecord]), 200);
        }),
      );

      final records = await repository.listVisibleTo(admin);
      expect(records, hasLength(2));
      expect(records[0].participant.studyId, 'C01-000001');
      expect(records[1].participant.studyId, 'P001');
    });

    test('throws LocalApiException on invalid participant study ID', () async {
      final repository = LocalApiVisitRepository(
        apiKey: 'admin-test-key-123',
        client: MockClient((_) async {
          final invalidRecord = _recordJson()..['participant'] = {
            'studyId': 'INVALID_ID_999',
            'name': 'Bad ID Participant',
            'indianPhone': '+919000000001',
          };
          return http.Response(jsonEncode([invalidRecord]), 200);
        }),
      );

      expect(
        () => repository.listVisibleTo(admin),
        throwsA(isA<LocalApiException>()),
      );
    });
  });
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

NcdQuestionnaire _sampleQuestionnaire() => const NcdQuestionnaire(
  studySite: 'Site A',
  age: 45,
  sex: 'female',
  education: 'Secondary',
  employment: 'Employed',
  fruitFrequency: 'Daily',
  vegetableFrequency: 'Daily',
  sugaryDrinkFrequency: 'Rarely',
  processedFoodFrequency: 'Rarely',
  activeDaysPerWeek: 5,
  activeMinutesPerDay: 30,
  sleepHours: 7.5,
  heightCm: 162.0,
  weightKg: 65.0,
  waistCm: 80.0,
  bpOneSystolic: 120,
  bpOneDiastolic: 80,
  bpTwoSystolic: 118,
  bpTwoDiastolic: 78,
);
