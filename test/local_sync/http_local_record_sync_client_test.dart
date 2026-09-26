import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:project2/local_sync/http_local_record_sync_client.dart';
import 'package:project2/local_sync/local_record_sync_gateway.dart';

void main() {
  group('public HTTPS endpoint mode', () {
    test(
      'validates clean HTTPS base URLs and rejects unsafe URL components',
      () {
        expect(
          HttpLocalRecordSyncClient.isValidApiBaseUrl(
            'https://collector.example.org/api/',
            requireHttps: true,
          ),
          isTrue,
        );
        for (final url in [
          'http://collector.example.org',
          'https://user:password@collector.example.org',
          'https://collector.example.org?token=x',
          'https://collector.example.org#section',
          'https://collector example.org',
          'collector.example.org',
        ]) {
          expect(
            HttpLocalRecordSyncClient.isValidApiBaseUrl(
              url,
              requireHttps: true,
            ),
            isFalse,
            reason: url,
          );
        }
        // The option is opt-in; local HTTP builds keep their existing behavior.
        expect(
          HttpLocalRecordSyncClient.isValidApiBaseUrl(
            'http://192.168.1.5:8787',
          ),
          isTrue,
        );
      },
    );

    test(
      'rejects an invalid endpoint before login, lookup, or upload requests',
      () async {
        var requests = 0;
        final client = HttpLocalRecordSyncClient(
          apiBaseUrl: 'http://user:password@collector.example.org?token=x',
          requireHttps: true,
          client: MockClient((_) async {
            requests++;
            return http.Response('{}', 200);
          }),
        );

        await expectLater(client.startSession('C001'), throwsFormatException);
        expect(
          await client.lookupParticipant('+919000000001'),
          isA<ParticipantLookupResult>(),
        );
        expect(
          await client.sendRecord(_record()),
          LocalRecordSyncResult.pending,
        );
        expect(requests, 0);
      },
    );

    test('allows valid HTTPS for login, lookup, and upload', () async {
      final seen = <Uri>[];
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'https://collector.example.org/api/',
        requireHttps: true,
        client: MockClient((request) async {
          seen.add(request.url);
          if (request.url.path.endsWith('/collector/session')) {
            return http.Response(
              '{"sessionToken":"session","collectorId":"C001"}',
              200,
            );
          }
          if (request.url.path.endsWith('/participants/lookup')) {
            return http.Response('{"found":false}', 200);
          }
          return http.Response('{"ok":true}', 201);
        }),
      );

      await client.startSession('C001');
      expect(
        await client.lookupParticipant('+919000000001'),
        isA<ParticipantLookupResult>(),
      );
      expect(await client.sendRecord(_record()), LocalRecordSyncResult.synced);
      expect(seen.map((uri) => uri.scheme), everyElement('https'));
      expect(seen.map((uri) => uri.path), [
        '/api/collector/session',
        '/api/participants/lookup',
        '/api/records',
      ]);
    });
  });

  group('HTTP 2xx Success (synced)', () {
    test('posts a VisitRecord-shaped payload to the configured LAN endpoint and returns 201 synced', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        apiKey: 'test-key-123',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url, Uri.parse('http://192.168.1.20:8787/records'));
          expect(request.headers['content-type'], 'application/json');
          expect(request.headers['x-local-sync-key'], 'test-key-123');
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
      expect(client.lastResponse?.isSynced, isTrue);
      expect(client.lastResponse?.statusCode, 201);
      expect(client.lastResponse?.body, {'id': 'LOCAL-1'});
    });

    test('returns synced on HTTP 200 OK with detailed SyncResponse', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient((_) async => http.Response('{"status":"ok"}', 200)),
      );

      final response = await client.sendRecordDetailed(_record());

      expect(response.result, LocalRecordSyncResult.synced);
      expect(response.isSynced, isTrue);
      expect(response.statusCode, 200);
      expect(response.body, {'status': 'ok'});
      expect(client.lastResponse, response);
    });

    test('returns synced on HTTP 204 No Content', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient((_) async => http.Response('', 204)),
      );

      final result = await client.sendRecord(_record());

      expect(result, LocalRecordSyncResult.synced);
      expect(client.lastResponse?.isSynced, isTrue);
      expect(client.lastResponse?.statusCode, 204);
    });
  });

  group('HTTP 409 Conflict (conflict)', () {
    test('distinguishes a server conflict from a connection outage', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient(
          (_) async => http.Response('{"error":"conflict"}', 409),
        ),
      );

      expect(
        await client.sendRecord(_record()),
        LocalRecordSyncResult.conflict,
      );
      expect(client.lastResponse?.isConflict, isTrue);
      expect(client.lastResponse?.message, 'conflict');
    });

    test('extracts rich conflict explanations with conflictType and custom message', () async {
      final conflictPayload = jsonEncode({
        'error': 'conflict',
        'message': 'Participant number belongs to another phone. Resolve this conflict before syncing.',
        'conflictType': 'participant_mismatch',
      });

      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient((_) async => http.Response(conflictPayload, 409)),
      );

      final response = await client.sendRecordDetailed(_record());

      expect(response.result, LocalRecordSyncResult.conflict);
      expect(response.isConflict, isTrue);
      expect(response.statusCode, 409);
      expect(
        response.message,
        'Participant number belongs to another phone. Resolve this conflict before syncing.',
      );
      expect(response.conflictType, 'participant_mismatch');
      expect(client.lastConflictMessage, response.message);
      expect(client.lastConflictType, 'participant_mismatch');
      expect(client.lastConflict, isNotNull);
    });

    test('extracts reason field from JSON conflict body if present', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient(
          (_) async => http.Response(
            '{"error":"conflict","reason":"duplicate_visit_number"}',
            409,
          ),
        ),
      );

      final response = await client.sendRecordDetailed(_record());

      expect(response.result, LocalRecordSyncResult.conflict);
      expect(response.message, 'duplicate_visit_number');
    });

    test(
      'falls back to raw body text when conflict body is not JSON',
      () async {
        final client = HttpLocalRecordSyncClient(
          apiBaseUrl: 'http://192.168.1.20:8787',
          client: MockClient(
            (_) async =>
                http.Response('Conflict: Record already submitted', 409),
          ),
        );

        final response = await client.sendRecordDetailed(_record());

        expect(response.result, LocalRecordSyncResult.conflict);
        expect(response.message, 'Conflict: Record already submitted');
        expect(response.rawBody, 'Conflict: Record already submitted');
      },
    );

    test(
      'extracts conflictId from JSON response body when status code is 409',
      () async {
        final conflictPayload = jsonEncode({
          'error': 'conflict',
          'message': 'Participant number belongs to another phone.',
          'conflictType': 'participant_mismatch',
          'conflictId': 'CONF-P001-99',
        });

        final client = HttpLocalRecordSyncClient(
          apiBaseUrl: 'http://192.168.1.20:8787',
          client: MockClient((_) async => http.Response(conflictPayload, 409)),
        );

        final response = await client.sendRecordDetailed(_record());

        expect(response.result, LocalRecordSyncResult.conflict);
        expect(response.isConflict, isTrue);
        expect(response.statusCode, 409);
        expect(response.conflictType, 'participant_mismatch');
        expect(response.conflictId, 'CONF-P001-99');
        expect(client.lastConflictId, 'CONF-P001-99');
      },
    );

    test('handles empty body gracefully on HTTP 409', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient((_) async => http.Response('', 409)),
      );

      final response = await client.sendRecordDetailed(_record());

      expect(response.result, LocalRecordSyncResult.conflict);
      expect(response.message, isNull);
      expect(response.conflictType, isNull);
    });
  });

  group('Network Timeouts and Connection Errors (pending)', () {
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
        expect(client.lastResponse?.isPending, isTrue);
      },
    );

    test(
      'returns pending when request times out via timeout duration',
      () async {
        final client = HttpLocalRecordSyncClient(
          apiBaseUrl: 'http://192.168.1.20:8787',
          timeout: const Duration(milliseconds: 50),
          client: MockClient((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 150));
            return http.Response('{"status":"ok"}', 200);
          }),
        );

        final result = await client.sendRecord(_record());

        expect(result, LocalRecordSyncResult.pending);
        expect(client.lastResponse?.isPending, isTrue);
        expect(client.lastResponse?.message, contains('timed out'));
      },
    );

    test('returns pending when TimeoutException is thrown directly', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient(
          (_) async => throw TimeoutException('Connection timed out'),
        ),
      );

      final response = await client.sendRecordDetailed(_record());

      expect(response.result, LocalRecordSyncResult.pending);
      expect(response.isPending, isTrue);
      expect(response.message, contains('Connection timed out'));
    });

    test(
      'returns pending on SocketException (server down / connection refused)',
      () async {
        final client = HttpLocalRecordSyncClient(
          apiBaseUrl: 'http://192.168.1.20:8787',
          client: MockClient(
            (_) async => throw const SocketException(
              'OS Error: Connection refused, errno = 111',
            ),
          ),
        );

        final result = await client.sendRecord(_record());

        expect(result, LocalRecordSyncResult.pending);
        expect(client.lastResponse?.isPending, isTrue);
        expect(client.lastResponse?.message, contains('Connection refused'));
      },
    );

    test(
      'returns pending on http.ClientException (connection closed / reset)',
      () async {
        final client = HttpLocalRecordSyncClient(
          apiBaseUrl: 'http://192.168.1.20:8787',
          client: MockClient(
            (_) async => throw http.ClientException(
              'Connection closed before full headers received',
            ),
          ),
        );

        final result = await client.sendRecord(_record());

        expect(result, LocalRecordSyncResult.pending);
        expect(client.lastResponse?.isPending, isTrue);
        expect(client.lastResponse?.message, contains('Connection closed'));
      },
    );

    test('returns pending on generic network or IO exceptions', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient(
          (_) async => throw const HttpException('Service unreachable'),
        ),
      );

      final result = await client.sendRecord(_record());

      expect(result, LocalRecordSyncResult.pending);
      expect(client.lastResponse?.isPending, isTrue);
    });
  });

  group('Other HTTP Errors (failed)', () {
    test('returns failed on HTTP 400 Bad Request', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient(
          (_) async => http.Response('{"error":"bad_request"}', 400),
        ),
      );

      final response = await client.sendRecordDetailed(_record());

      expect(response.result, LocalRecordSyncResult.failed);
      expect(response.isFailed, isTrue);
      expect(response.statusCode, 400);
      expect(response.message, 'bad_request');
      expect(await client.sendRecord(_record()), LocalRecordSyncResult.failed);
    });

    test('returns failed on HTTP 401 Unauthorized', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient(
          (_) async => http.Response('{"error":"unauthorized"}', 401),
        ),
      );

      final response = await client.sendRecordDetailed(_record());

      expect(response.result, LocalRecordSyncResult.failed);
      expect(response.statusCode, 401);
      expect(response.message, 'unauthorized');
    });

    test('returns failed on HTTP 403 Forbidden', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient(
          (_) async => http.Response('{"error":"forbidden"}', 403),
        ),
      );

      final result = await client.sendRecord(_record());

      expect(result, LocalRecordSyncResult.failed);
      expect(client.lastResponse?.statusCode, 403);
    });

    test('returns failed on HTTP 404 Not Found', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient((_) async => http.Response('Not Found', 404)),
      );

      final response = await client.sendRecordDetailed(_record());

      expect(response.result, LocalRecordSyncResult.failed);
      expect(response.statusCode, 404);
      expect(response.message, 'Not Found');
    });

    test('returns failed on HTTP 500 Internal Server Error', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient(
          (_) async => http.Response('{"error":"internal_server_error"}', 500),
        ),
      );

      final response = await client.sendRecordDetailed(_record());

      expect(response.result, LocalRecordSyncResult.failed);
      expect(response.isFailed, isTrue);
      expect(response.statusCode, 500);
      expect(response.message, 'internal_server_error');
    });

    test('returns failed on HTTP 502 Bad Gateway', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient((_) async => http.Response('Bad Gateway', 502)),
      );

      final result = await client.sendRecord(_record());

      expect(result, LocalRecordSyncResult.failed);
      expect(client.lastResponse?.statusCode, 502);
    });

    test('returns failed on HTTP 503 Service Unavailable', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient(
          (_) async => http.Response('Service Unavailable', 503),
        ),
      );

      final response = await client.sendRecordDetailed(_record());

      expect(response.result, LocalRecordSyncResult.failed);
      expect(response.statusCode, 503);
      expect(response.message, 'Service Unavailable');
    });
  });

  group('SyncResponse and LocalRecordSyncResult Model & Gateway Extensions', () {
    test('enum and model helper getters work consistently', () {
      expect(LocalRecordSyncResult.synced.isSynced, isTrue);
      expect(LocalRecordSyncResult.pending.isPending, isTrue);
      expect(LocalRecordSyncResult.failed.isFailed, isTrue);
      expect(LocalRecordSyncResult.conflict.isConflict, isTrue);

      const synced = SyncResponse.synced();
      expect(synced.isSynced, isTrue);
      expect(synced.result, LocalRecordSyncResult.synced);

      const conflict = SyncResponse.conflict(
        message: 'oops',
        conflictType: 'bad',
      );
      expect(conflict.isConflict, isTrue);
      expect(conflict.result, LocalRecordSyncResult.conflict);
      expect(conflict.message, 'oops');
      expect(conflict.conflictType, 'bad');

      final fromEnum = LocalRecordSyncResult.conflict.toResponse(
        message: 'custom',
        conflictType: 'custom_type',
      );
      expect(fromEnum.isConflict, isTrue);
      expect(fromEnum.message, 'custom');
      expect(fromEnum.conflictType, 'custom_type');
    });

    test(
      'LocalRecordSyncGateway extension sendRecordDetailed delegates to client',
      () async {
        final LocalRecordSyncGateway gateway = HttpLocalRecordSyncClient(
          apiBaseUrl: 'http://192.168.1.20:8787',
          client: MockClient(
            (_) async => http.Response(
              '{"error":"conflict","message":"collision"}',
              409,
            ),
          ),
        );

        final detailed = await gateway.sendRecordDetailed(_record());

        expect(detailed.result, LocalRecordSyncResult.conflict);
        expect(detailed.message, 'collision');
        expect(gateway.lastResponse?.message, 'collision');
      },
    );

    test('HttpLocalRecordSyncClient syncRecord alias delegates to sendRecordDetailed', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient((_) async => http.Response('{"status":"ok"}', 200)),
      );

      final detailed = await client.syncRecord(_record());

      expect(detailed.isSynced, isTrue);
      expect(detailed.statusCode, 200);
    });
    test('ParticipantLookupResult constructors work as expected', () {
      const found = ParticipantLookupResult.found(
        studyId: 'P001',
        name: 'Test',
        nextVisitNumber: 2,
      );
      expect(found.found, isTrue);
      expect(found.isOffline, isFalse);
      expect(found.studyId, 'P001');
      expect(found.name, 'Test');
      expect(found.nextVisitNumber, 2);

      const notFound = ParticipantLookupResult.notFound();
      expect(notFound.found, isFalse);
      expect(notFound.isOffline, isFalse);
      expect(notFound.studyId, isNull);

      const offline = ParticipantLookupResult.offline();
      expect(offline.found, isFalse);
      expect(offline.isOffline, isTrue);
    });
  });

  group('Participant Lookup (lookupParticipant)', () {
    test(
      'parses an ambiguous shared-phone response without picking an ID',
      () async {
        final client = HttpLocalRecordSyncClient(
          apiBaseUrl: 'http://192.168.1.20:8787',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'found': true,
                'ambiguous': true,
                'participants': [
                  {
                    'studyId': 'C01-000001',
                    'name': 'Asha',
                    'nextVisitNumber': 2,
                  },
                  {
                    'studyId': 'C02-000001',
                    'name': 'Ravi',
                    'nextVisitNumber': 3,
                  },
                ],
              }),
              200,
            ),
          ),
        );
        final result = await client.lookupParticipant('9000000001');
        expect(result.isAmbiguous, isTrue);
        expect(result.studyId, isNull);
        expect(result.candidates.map((c) => c.studyId), [
          'C01-000001',
          'C02-000001',
        ]);
      },
    );

    test('malformed found response is unknown, never not-found', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient((_) async => http.Response('{"found":true}', 200)),
      );
      final result = await client.lookupParticipant('9000000001');
      expect(result.isOffline, isTrue);
      expect(result.found, isFalse);
    });

    test('successful online lookup calls GET /participants/lookup with key and returns ParticipantLookupResult.found', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        apiKey: 'test-key-123',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url,
            Uri.parse(
              'http://192.168.1.20:8787/participants/lookup?phone=%2B919000000001',
            ),
          );
          expect(request.headers['x-local-sync-key'], 'test-key-123');
          return http.Response(
            jsonEncode({
              'found': true,
              'participant': {
                'studyId': 'P001',
                'name': 'Test Participant',
                'nextVisitNumber': 2,
              },
            }),
            200,
          );
        }),
      );

      final result = await client.lookupParticipant('+919000000001');

      expect(result.found, isTrue);
      expect(result.isOffline, isFalse);
      expect(result.studyId, 'P001');
      expect(result.name, 'Test Participant');
      expect(result.nextVisitNumber, 2);
    });

    test('returns notFound when 200 OK has found = false', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient((_) async => http.Response('{"found":false}', 200)),
      );

      final result = await client.lookupParticipant('9000000001');

      expect(result.found, isFalse);
      expect(result.isOffline, isFalse);
      expect(result.studyId, isNull);
      expect(result.name, isNull);
      expect(result.nextVisitNumber, isNull);
    });

    test('returns notFound on HTTP 404', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient((_) async => http.Response('Not Found', 404)),
      );

      final result = await client.lookupParticipant('9000000001');

      expect(result.found, isFalse);
      expect(result.isOffline, isFalse);
      expect(result.studyId, isNull);
    });

    test(
      'returns offline when physical-LAN endpoint is unconfigured',
      () async {
        final client = HttpLocalRecordSyncClient(
          apiBaseUrl: '',
          client: MockClient((_) async => http.Response('', 200)),
        );

        final result = await client.lookupParticipant('9000000001');

        expect(result.found, isFalse);
        expect(result.isOffline, isTrue);
      },
    );

    test('returns offline on request timeout via duration', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return http.Response('{"found":true}', 200);
        }),
      );

      final result = await client.lookupParticipant(
        '9000000001',
        timeout: const Duration(milliseconds: 20),
      );

      expect(result.found, isFalse);
      expect(result.isOffline, isTrue);
    });

    test('returns offline when TimeoutException is thrown directly', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient(
          (_) async => throw TimeoutException('Connection timed out'),
        ),
      );

      final result = await client.lookupParticipant('9000000001');

      expect(result.found, isFalse);
      expect(result.isOffline, isTrue);
    });

    test(
      'returns offline on SocketException (server down / connection refused)',
      () async {
        final client = HttpLocalRecordSyncClient(
          apiBaseUrl: 'http://192.168.1.20:8787',
          client: MockClient(
            (_) async => throw const SocketException(
              'OS Error: Connection refused, errno = 111',
            ),
          ),
        );

        final result = await client.lookupParticipant('9000000001');

        expect(result.found, isFalse);
        expect(result.isOffline, isTrue);
      },
    );

    test(
      'returns offline on http.ClientException (connection closed / reset)',
      () async {
        final client = HttpLocalRecordSyncClient(
          apiBaseUrl: 'http://192.168.1.20:8787',
          client: MockClient(
            (_) async => throw http.ClientException(
              'Connection closed before full headers received',
            ),
          ),
        );

        final result = await client.lookupParticipant('9000000001');

        expect(result.found, isFalse);
        expect(result.isOffline, isTrue);
      },
    );

    test('returns offline on generic server error (HTTP 500 / 503)', () async {
      final client = HttpLocalRecordSyncClient(
        apiBaseUrl: 'http://192.168.1.20:8787',
        client: MockClient(
          (_) async => http.Response('Internal Server Error', 500),
        ),
      );

      final result = await client.lookupParticipant('9000000001');

      expect(result.found, isFalse);
      expect(result.isOffline, isTrue);
    });
  });
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
