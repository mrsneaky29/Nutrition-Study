import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../tool/local_sync_server.dart';

void main() {
  late Directory dataDirectory;
  late LocalRecordStore store;

  setUp(() async {
    dataDirectory = await Directory.systemTemp.createTemp('study-sync-test-');
    store = LocalRecordStore(dataDirectory);
    await store.load();
  });

  tearDown(() async {
    await dataDirectory.delete(recursive: true);
  });

  group('LocalRecordStore core persistence and idempotency', () {
    test(
      'resolving a reused record ID cannot overwrite an accepted visit',
      () async {
        await store.upsertCollector(_submission());
        final rejected = _submission(
          id: 'visit-1',
          key: 'different-upload-key',
          studyId: 'P002',
          phone: '+919000000002',
        );
        await _expectConflict(
          store.upsertCollector(rejected),
          conflictType: 'idempotency_collision',
        );
        final conflictId = store.conflicts().single['id'] as String;
        await _expectConflict(
          store.resolveConflict(conflictId, {'studyId': 'P002'}),
          conflictType: 'record_id_collision',
        );
        expect(store.records().single['participant']['studyId'], 'P001');
        expect(store.getConflict(conflictId)!['status'], 'pending');

        await store.resolveConflict(conflictId, {
          'recordId': 'visit-2',
          'studyId': 'P002',
        });
        expect(
          (await store.resolveConflict(conflictId, {
            'recordId': 'visit-2',
          }))['status'],
          'resolved',
        );
        await _expectConflict(store.reviewConflict(conflictId));
        expect(store.length, 2);
        expect(
          store.records().firstWhere(
            (r) => r['id'] == 'visit-1',
          )['participant']['studyId'],
          'P001',
        );
        expect(
          store.records().firstWhere(
            (r) => r['id'] == 'visit-2',
          )['participant']['studyId'],
          'P002',
        );
        final retried = await store.upsertCollector(rejected);
        expect(retried['id'], 'visit-2');
      },
    );

    test('finishes conflict resolution after restart when the record was already saved', () async {
      await store.upsertCollector(_submission());
      final rejected = _submission(
        id: 'visit-2',
        key: 'upload-visit-2',
        studyId: 'P001',
        phone: '+919000000099',
      );
      await _expectConflict(
        store.upsertCollector(rejected),
        conflictType: 'participant_mismatch',
      );
      final conflictId = store.conflicts().single['id'] as String;

      // Model a restart after records.json committed but before
      // conflicts.json recorded the resolution.
      final acceptedAfterCrash =
          Map<String, dynamic>.from(
              store.conflicts().single['rejectedRecord'] as Map,
            )
            ..['participant'] = {
              ...(rejected['participant'] as Map<String, dynamic>),
              'studyId': 'P002',
            }
            ..['createdAt'] = '2026-09-13T00:00:00.000Z'
            ..['updatedAt'] = '2026-09-13T00:00:00.000Z'
            ..['revision'] = 1
            ..['syncState'] = 'synced';
      await store.recordsFile.writeAsString(
        jsonEncode([...store.records(), acceptedAfterCrash]),
        flush: true,
      );

      final restarted = LocalRecordStore(dataDirectory);
      await restarted.load();
      final resolved = await restarted.resolveConflict(conflictId, {
        'studyId': 'P002',
      });

      expect(resolved['status'], 'resolved');
      expect(resolved['acceptedRecordId'], 'visit-2');
      expect(restarted.length, 2);
    });

    test(
      'resolving reused upload key keeps accepted records distinct',
      () async {
        await store.upsertCollector(_submission());
        final rejected = _submission(
          id: 'visit-2',
          key: 'upload-visit-1',
          studyId: 'P002',
          phone: '+919000000002',
        );
        await _expectConflict(
          store.upsertCollector(rejected),
          conflictType: 'idempotency_collision',
        );
        final conflictId = store.conflicts().single['id'] as String;
        await store.resolveConflict(conflictId, {'studyId': 'P002'});
        expect(store.length, 2);
        final accepted = store.records().firstWhere(
          (r) => r['id'] == 'visit-2',
        );
        expect(accepted['idempotencyKey'], isNot('upload-visit-1'));
        expect((await store.upsertCollector(rejected))['id'], 'visit-2');
        final reloaded = LocalRecordStore(dataDirectory);
        await reloaded.load();
        expect(reloaded.records(), hasLength(2));
      },
    );

    test(
      'accepts the collector payload and persists it across restart',
      () async {
        final saved = await store.upsertCollector(_submission());

        expect(saved['idempotencyKey'], 'upload-visit-1');
        expect(saved['syncState'], 'synced');
        expect(saved['revision'], 1);

        final reloaded = LocalRecordStore(dataDirectory);
        await reloaded.load();
        expect(reloaded.records(), hasLength(1));
        expect(reloaded.records().single['id'], 'visit-1');
      },
    );

    test('accepts legacy and v1 full-numeric questionnaires', () async {
      await store.upsertCollector(
        _submission(
          id: 'legacy-questionnaire',
          key: 'legacy-questionnaire-key',
          questionnaire: _validQuestionnaire(),
        ),
      );
      await store.upsertCollector(
        _submission(
          id: 'v1-questionnaire',
          key: 'v1-questionnaire-key',
          studyId: 'P002',
          phone: '+919000000002',
          questionnaire: {..._validQuestionnaire(), 'schemaVersion': 1},
        ),
      );

      expect(store.length, 2);
    });

    test(
      'accepts schema v2 missing measurements with reasons and null summaries',
      () async {
        final questionnaire = _validQuestionnaireV2()
          ..['heightCm'] = null
          ..['heightMissingReason'] = 'unable'
          ..['weightKg'] = null
          ..['weightMissingReason'] = 'declined'
          ..['bpOneSystolic'] = null
          ..['bpOneDiastolic'] = null
          ..['bpOneMissingReason'] = 'unable'
          ..['bmi'] = null
          ..['averageSystolic'] = null
          ..['averageDiastolic'] = null;

        final accepted = await store.upsertCollector(
          _submission(questionnaire: questionnaire),
        );

        expect(accepted['questionnaire']['heightCm'], isNull);
        expect(accepted['questionnaire']['heightMissingReason'], 'unable');
        expect(accepted['questionnaire']['bmi'], isNull);
        expect(accepted['questionnaire']['averageSystolic'], isNull);
      },
    );

    test(
      'rejects schema v2 missing measurements without valid paired reasons',
      () async {
        final missingReason = _validQuestionnaireV2()
          ..['heightCm'] = null
          ..['heightMissingReason'] = null
          ..['bmi'] = null;
        await _expectBadRequest(
          store.upsertCollector(_submission(questionnaire: missingReason)),
        );

        final partialBloodPressure = _validQuestionnaireV2()
          ..['bpOneSystolic'] = null
          ..['bpOneMissingReason'] = 'declined'
          ..['averageSystolic'] = null
          ..['averageDiastolic'] = null;
        await _expectBadRequest(
          store.upsertCollector(
            _submission(
              id: 'partial-bp',
              key: 'partial-bp-key',
              questionnaire: partialBloodPressure,
            ),
          ),
        );

        final staleSummary = _validQuestionnaireV2()
          ..['heightCm'] = null
          ..['heightMissingReason'] = 'declined';
        await _expectBadRequest(
          store.upsertCollector(
            _submission(
              id: 'stale-summary',
              key: 'stale-summary-key',
              questionnaire: staleSummary,
            ),
          ),
        );
      },
    );

    test(
      'retains a previous snapshot and loads it after primary corruption',
      () async {
        await store.upsertCollector(_submission());
        await store.upsertCollector(
          _submission(
            id: 'visit-2',
            key: 'upload-visit-2',
            studyId: 'P002',
            phone: '+919000000002',
          ),
        );
        final backup = File('${store.recordsFile.path}.bak');
        expect(backup.existsSync(), isTrue);
        expect(jsonDecode(await backup.readAsString()), hasLength(1));

        await store.recordsFile.writeAsString('{invalid json', flush: true);
        final recovered = LocalRecordStore(dataDirectory);
        await recovered.load();

        expect(recovered.recoveredFromBackup, isTrue);
        expect(recovered.records(), hasLength(1));
        expect(recovered.records().single['id'], 'visit-1');
        await recovered.upsertCollector(
          _submission(
            id: 'visit-3',
            key: 'upload-visit-3',
            studyId: 'P003',
            phone: '+919000000003',
          ),
        );
        expect(jsonDecode(await backup.readAsString()), hasLength(1));
        expect(
          jsonDecode(await recovered.recordsFile.readAsString()),
          hasLength(2),
        );
      },
    );

    test(
      'recovers from non-utf8 binary garbage in primary data file using .bak',
      () async {
        await store.upsertCollector(_submission());
        await store.upsertCollector(
          _submission(
            id: 'visit-2',
            key: 'upload-visit-2',
            studyId: 'P002',
            phone: '+919000000002',
          ),
        );
        final backup = File('${store.recordsFile.path}.bak');
        expect(backup.existsSync(), isTrue);

        // Corrupt primary file with arbitrary binary bytes
        await store.recordsFile.writeAsBytes([
          0xFF,
          0xFE,
          0x00,
          0x01,
          0x80,
        ], flush: true);

        final recovered = LocalRecordStore(dataDirectory);
        await recovered.load();

        expect(recovered.records(), hasLength(1));
        expect(recovered.records().single['id'], 'visit-1');
      },
    );

    test(
      'recreates primary file from .bak when primary file is missing',
      () async {
        await store.upsertCollector(_submission());
        await store.upsertCollector(
          _submission(
            id: 'visit-2',
            key: 'upload-visit-2',
            studyId: 'P002',
            phone: '+919000000002',
          ),
        );
        // Delete primary file
        await store.recordsFile.delete();
        expect(store.recordsFile.existsSync(), isFalse);

        final recovered = LocalRecordStore(dataDirectory);
        await recovered.load();

        expect(recovered.records(), hasLength(1));
        expect(recovered.recordsFile.existsSync(), isTrue);
      },
    );

    test(
      'retry is idempotent and cannot overwrite an admin correction',
      () async {
        final original = await store.upsertCollector(_submission());
        final edited = Map<String, dynamic>.from(original)
          ..['stepTwoPlaceholderNote'] = 'Corrected by admin';
        final correction = await store.replaceAdmin('visit-1', edited);

        final retry = await store.upsertCollector(_submission());

        expect(retry['stepTwoPlaceholderNote'], 'Corrected by admin');
        expect(retry['revision'], correction['revision']);
        expect(store.length, 1);
      },
    );

    test('retry after archive cannot unarchive a record', () async {
      await store.upsertCollector(_submission());
      final archived = await store.setArchived(
        'visit-1',
        archived: true,
        actor: 'admin',
      );

      final retry = await store.upsertCollector(_submission());

      expect(retry['archivedAt'], archived['archivedAt']);
      expect(retry['revision'], archived['revision']);
    });
  });

  group('AccessKeys multi-collector configuration', () {
    const publicCollector = 'a-very-long-independent-collector-secret-000001';
    const publicAdmin = 'a-very-long-independent-admin-secret-00000001';
    const publicOrigin = 'https://admin.example.org';

    test('public mode requires mapped strong keys and exact origins', () {
      final keys = AccessKeys.fromEnvironment({
        'LOCAL_SYNC_PUBLIC_MODE': 'true',
        'LOCAL_SYNC_COLLECTOR_KEYS': 'C007:$publicCollector',
        'LOCAL_SYNC_ADMIN_KEY': publicAdmin,
        'LOCAL_SYNC_ALLOWED_ORIGINS': publicOrigin,
      });

      expect(keys, isNotNull);
      expect(keys!.publicMode, isTrue);
      expect(keys.requireCollectorSession, isTrue);
      expect(keys.collectorIdForKey(publicCollector), 'C007');
      expect(keys.allowedOrigins, {publicOrigin});
    });

    test('public mode accepts C1000+ collector IDs', () {
      final keys = AccessKeys.fromEnvironment({
        'LOCAL_SYNC_PUBLIC_MODE': 'true',
        'LOCAL_SYNC_COLLECTOR_KEYS': 'C1000:$publicCollector',
        'LOCAL_SYNC_ADMIN_KEY': publicAdmin,
        'LOCAL_SYNC_ALLOWED_ORIGINS': publicOrigin,
      });

      expect(keys, isNotNull);
      expect(keys!.publicMode, isTrue);
      expect(keys.collectorIdForKey(publicCollector), 'C1000');
    });

    test(
      'public mode fails closed for weak, shared, legacy, or wildcard config',
      () {
        Map<String, String> config({
          String collector = publicCollector,
          String admin = publicAdmin,
          String origin = publicOrigin,
          String? legacy,
          String? singularCollector,
        }) {
          final values = <String, String>{
            'LOCAL_SYNC_PUBLIC_MODE': 'true',
            'LOCAL_SYNC_COLLECTOR_KEYS': 'C001:$collector',
            'LOCAL_SYNC_ADMIN_KEY': admin,
            'LOCAL_SYNC_ALLOWED_ORIGINS': origin,
          };
          if (legacy != null) values['LOCAL_SYNC_KEY'] = legacy;
          if (singularCollector != null) {
            values['LOCAL_SYNC_COLLECTOR_KEY'] = singularCollector;
          }
          return values;
        }

        expect(
          () => AccessKeys.fromEnvironment(config(collector: 'short-key')),
          throwsFormatException,
        );
        expect(
          () => AccessKeys.fromEnvironment(config(admin: publicCollector)),
          throwsFormatException,
        );
        expect(
          () => AccessKeys.fromEnvironment(config(origin: '*')),
          throwsFormatException,
        );
        expect(
          () => AccessKeys.fromEnvironment(
            config(origin: 'https://admin.example.org/'),
          ),
          throwsFormatException,
        );
        expect(
          () => AccessKeys.fromEnvironment(
            config(origin: 'http://admin.example.org'),
          ),
          throwsFormatException,
        );
        expect(
          () => AccessKeys.fromEnvironment(
            config(legacy: 'old-shared-secret-1234567890'),
          ),
          throwsFormatException,
        );
        expect(
          () => AccessKeys.fromEnvironment(
            config(singularCollector: publicCollector),
          ),
          throwsFormatException,
        );
        expect(
          () => AccessKeys.fromEnvironment({
            'LOCAL_SYNC_PUBLIC_MODE': 'sometimes',
          }),
          throwsFormatException,
        );
      },
    );

    test(
      'legacy shared-key mode stays available when public mode is absent',
      () {
        final keys = AccessKeys.fromEnvironment({
          'LOCAL_SYNC_KEY': 'legacy-local-demo-key-123',
        });
        expect(keys, isNotNull);
        expect(keys!.publicMode, isFalse);
        expect(keys.isAdmin('legacy-local-demo-key-123'), isTrue);
      },
    );

    test('parses multiple collector keys from LOCAL_SYNC_COLLECTOR_KEYS', () {
      final keys = AccessKeys.fromEnvironment({
        'LOCAL_SYNC_COLLECTOR_KEYS':
            'collector-key-alpha-1234, collector-key-beta-5678',
        'LOCAL_SYNC_ADMIN_KEY': 'admin-key-secure-12345',
      });

      expect(keys, isNotNull);
      expect(
        keys!.collectorKeys,
        containsAll(['collector-key-alpha-1234', 'collector-key-beta-5678']),
      );
      expect(keys.admin, 'admin-key-secure-12345');
      expect(keys.isCollector('collector-key-alpha-1234'), isTrue);
      expect(keys.isCollector('collector-key-beta-5678'), isTrue);
      expect(keys.isCollector('admin-key-secure-12345'), isFalse);
      expect(keys.isAdmin('admin-key-secure-12345'), isTrue);
    });

    test('parses multiple collector keys from LOCAL_SYNC_COLLECTOR_KEY', () {
      final keys = AccessKeys.fromEnvironment({
        'LOCAL_SYNC_COLLECTOR_KEY':
            'collector-key-one-12345,collector-key-two-67890',
        'LOCAL_SYNC_ADMIN_KEY': 'admin-key-secure-12345',
      });

      expect(keys, isNotNull);
      expect(keys!.collectorKeys.length, 2);
      expect(keys.isCollector('collector-key-one-12345'), isTrue);
      expect(keys.isCollector('collector-key-two-67890'), isTrue);
    });

    test('combines collector keys from both environment variables', () {
      final keys = AccessKeys.fromEnvironment({
        'LOCAL_SYNC_COLLECTOR_KEYS': 'collector-key-first-123',
        'LOCAL_SYNC_COLLECTOR_KEY': 'collector-key-second-456',
        'LOCAL_SYNC_ADMIN_KEY': 'admin-key-secure-12345',
      });

      expect(keys, isNotNull);
      expect(keys!.collectorKeys.length, 2);
      expect(keys.isCollector('collector-key-first-123'), isTrue);
      expect(keys.isCollector('collector-key-second-456'), isTrue);
    });

    test('rejects collector key shorter than 16 characters', () {
      final keys = AccessKeys.fromEnvironment({
        'LOCAL_SYNC_COLLECTOR_KEYS': 'short-key,collector-valid-key-1234',
        'LOCAL_SYNC_ADMIN_KEY': 'admin-key-secure-12345',
      });

      expect(keys, isNull);
    });

    test('rejects admin key shorter than 16 characters', () {
      final keys = AccessKeys.fromEnvironment({
        'LOCAL_SYNC_COLLECTOR_KEY': 'collector-valid-key-1234',
        'LOCAL_SYNC_ADMIN_KEY': 'short-admin',
      });

      expect(keys, isNull);
    });

    test('rejects configuration when admin key equals a collector key', () {
      final keys = AccessKeys.fromEnvironment({
        'LOCAL_SYNC_COLLECTOR_KEY': 'same-key-used-for-both-1',
        'LOCAL_SYNC_ADMIN_KEY': 'same-key-used-for-both-1',
      });

      expect(keys, isNull);
    });

    test('rejects configuration with collectors set but admin key missing', () {
      final keys = AccessKeys.fromEnvironment({
        'LOCAL_SYNC_COLLECTOR_KEY': 'collector-valid-key-1234',
      });

      expect(keys, isNull);
    });

    test('rejects configuration with admin set but collector keys missing', () {
      final keys = AccessKeys.fromEnvironment({
        'LOCAL_SYNC_ADMIN_KEY': 'admin-key-secure-12345',
      });

      expect(keys, isNull);
    });

    test('supports legacy LOCAL_SYNC_KEY when at least 16 characters', () {
      final keys = AccessKeys.fromEnvironment({
        'LOCAL_SYNC_KEY': 'legacy-local-demo-key-123',
      });

      expect(keys, isNotNull);
      expect(keys!.isCollector('legacy-local-demo-key-123'), isTrue);
      expect(keys.isAdmin('legacy-local-demo-key-123'), isTrue);
    });

    test('rejects legacy LOCAL_SYNC_KEY when under 16 characters', () {
      final keys = AccessKeys.fromEnvironment({'LOCAL_SYNC_KEY': 'short-key'});

      expect(keys, isNull);
    });
  });

  group('Public mode HTTP protections', () {
    const collectorKey = 'a-very-long-independent-collector-secret-000001';
    const adminKey = 'a-very-long-independent-admin-secret-00000001';
    const allowedOrigin = 'https://admin.example.org';

    late HttpServer server;
    late HttpClient client;
    late AccessKeys keys;

    setUp(() async {
      keys = AccessKeys.fromEnvironment({
        'LOCAL_SYNC_PUBLIC_MODE': 'true',
        'LOCAL_SYNC_COLLECTOR_KEYS': 'C001:$collectorKey',
        'LOCAL_SYNC_ADMIN_KEY': adminKey,
        'LOCAL_SYNC_ALLOWED_ORIGINS': allowedOrigin,
      })!;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) => handleRequest(request, store, keys));
      client = HttpClient();
      resetAuthLimiterForTesting();
    });

    tearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });

    test('only exact admin origin receives CORS permission', () async {
      final allowed = await client.openUrl(
        'OPTIONS',
        Uri.parse('http://127.0.0.1:${server.port}/records'),
      );
      allowed.headers
        ..set('origin', allowedOrigin)
        ..set('x-forwarded-proto', 'https')
        ..set(HttpHeaders.accessControlRequestMethodHeader, 'GET')
        ..set(
          HttpHeaders.accessControlRequestHeadersHeader,
          'x-local-sync-key',
        );
      final allowedResponse = await allowed.close();
      expect(allowedResponse.statusCode, HttpStatus.noContent);
      expect(
        allowedResponse.headers.value(
          HttpHeaders.accessControlAllowOriginHeader,
        ),
        allowedOrigin,
      );
      await allowedResponse.drain<void>();

      final denied = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/records'),
      );
      denied.headers
        ..set('origin', 'https://evil.example.org')
        ..set('x-forwarded-proto', 'https')
        ..set('x-local-sync-key', adminKey);
      final deniedResponse = await denied.close();
      expect(deniedResponse.statusCode, HttpStatus.forbidden);
      expect(
        deniedResponse.headers.value(
          HttpHeaders.accessControlAllowOriginHeader,
        ),
        isNull,
      );
      await deniedResponse.drain<void>();
    });

    test('collector bootstrap creates a required current session', () async {
      final login = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/collector/session'),
      );
      login.headers
        ..set('x-forwarded-proto', 'https')
        ..set('x-local-sync-key', collectorKey)
        ..contentType = ContentType.json;
      login.write(jsonEncode({'collectorId': 'C001'}));
      final loginResponse = await login.close();
      expect(loginResponse.statusCode, HttpStatus.ok);
      final payload =
          jsonDecode(await utf8.decoder.bind(loginResponse).join()) as Map;
      final token = payload['sessionToken'] as String;

      final withoutSession = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/health'),
      );
      withoutSession.headers
        ..set('x-forwarded-proto', 'https')
        ..set('x-local-sync-key', collectorKey);
      final rejected = await withoutSession.close();
      expect(rejected.statusCode, HttpStatus.unauthorized);
      await rejected.drain<void>();

      final withSession = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/health'),
      );
      withSession.headers
        ..set('x-forwarded-proto', 'https')
        ..set('x-local-sync-key', collectorKey)
        ..set('x-local-session', token);
      final accepted = await withSession.close();
      expect(accepted.statusCode, HttpStatus.ok);
      await accepted.drain<void>();
    });

    test(
      'requires TLS proxy marker and applies bounded auth throttling',
      () async {
        final direct = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/health'),
        );
        direct.headers.set('x-local-sync-key', adminKey);
        final directResponse = await direct.close();
        expect(directResponse.statusCode, HttpStatus.forbidden);
        await directResponse.drain<void>();

        for (var attempt = 1; attempt <= 21; attempt++) {
          final request = await client.getUrl(
            Uri.parse('http://127.0.0.1:${server.port}/health'),
          );
          request.headers
            ..set('x-forwarded-proto', 'https')
            ..set('x-local-sync-key', 'incorrect-public-key');
          final response = await request.close();
          expect(
            response.statusCode,
            attempt <= 20
                ? HttpStatus.unauthorized
                : HttpStatus.tooManyRequests,
          );
          await response.drain<void>();
        }
      },
    );

    test('resolveClientKey enforces trusted loopback proxy and validates IPs', () {
      final loopback = InternetAddress.loopbackIPv4;
      final externalIp = InternetAddress('198.51.100.5');

      // Forwarded addresses are ignored when connection is NOT from loopback
      expect(
        resolveClientKey(
          remoteAddress: externalIp,
          forwardedFor: '203.0.113.10',
          realIp: '203.0.113.20',
        ),
        externalIp.address,
      );

      // Malformed/non-IP values are ignored and fall back safely
      expect(
        resolveClientKey(
          remoteAddress: loopback,
          forwardedFor: 'spoofed-ip-1, bad*ip',
        ),
        loopback.address,
      );

      // Valid client IP from loopback proxy is accepted
      expect(
        resolveClientKey(
          remoteAddress: loopback,
          forwardedFor: '203.0.113.10, 10.0.0.1',
        ),
        '203.0.113.10',
      );

      // Forwarded loopback IP is rejected (not an external client IP)
      expect(
        resolveClientKey(
          remoteAddress: loopback,
          forwardedFor: '127.0.0.1',
        ),
        loopback.address,
      );

      // X-Real-IP is used when X-Forwarded-For is absent or empty
      expect(
        resolveClientKey(
          remoteAddress: loopback,
          realIp: '203.0.113.20',
        ),
        '203.0.113.20',
      );
    });

    test('different forwarded client IPs have independent rate-limiting buckets', () async {
      const clientIp1 = '203.0.113.100';
      const clientIp2 = '203.0.113.101';

      // clientIp1 exhausts attempts (20 failures -> 401, 21st -> 429)
      for (var attempt = 1; attempt <= 21; attempt++) {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/health'),
        );
        request.headers
          ..set('x-forwarded-proto', 'https')
          ..set('x-forwarded-for', clientIp1)
          ..set('x-local-sync-key', 'incorrect-public-key');
        final response = await request.close();
        expect(
          response.statusCode,
          attempt <= 20 ? HttpStatus.unauthorized : HttpStatus.tooManyRequests,
        );
        await response.drain<void>();
      }

      // clientIp2 is NOT throttled by clientIp1's failures
      final request2 = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/health'),
      );
      request2.headers
        ..set('x-forwarded-proto', 'https')
        ..set('x-forwarded-for', clientIp2)
        ..set('x-local-sync-key', 'incorrect-public-key');
      final response2 = await request2.close();
      expect(response2.statusCode, HttpStatus.unauthorized);
      await response2.drain<void>();
    });

    test('spoofed non-IP forwarded headers do not bypass rate limiting', () async {
      for (var attempt = 1; attempt <= 21; attempt++) {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/health'),
        );
        request.headers
          ..set('x-forwarded-proto', 'https')
          ..set('x-forwarded-for', 'spoofed-random-$attempt')
          ..set('x-local-sync-key', 'incorrect-public-key');
        final response = await request.close();
        expect(
          response.statusCode,
          attempt <= 20 ? HttpStatus.unauthorized : HttpStatus.tooManyRequests,
        );
        await response.drain<void>();
      }
    });
  });

  group('HTTP Server multi-collector authentication & authorization', () {
    late HttpServer server;
    late String baseUrl;
    const collectorKeyA = 'collector-alpha-key-123';
    const collectorKeyB = 'collector-bravo-key-456';
    const adminKey = 'admin-secure-master-key-789';

    setUp(() async {
      final accessKeys = const AccessKeys(
        collectorKeys: {collectorKeyA, collectorKeyB},
        admin: adminKey,
      );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) => handleRequest(request, store, accessKeys));
      baseUrl = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test(
      'both collector A and collector B can upload records via POST /records',
      () async {
        final responseA = await http.post(
          Uri.parse('$baseUrl/records'),
          headers: {
            'content-type': 'application/json',
            'x-local-sync-key': collectorKeyA,
          },
          body: jsonEncode(
            _submission(
              id: 'visit-col-a',
              key: 'key-col-a',
              studyId: 'P101',
              phone: '+919000000101',
              collectorId: 'C001',
            ),
          ),
        );
        expect(responseA.statusCode, HttpStatus.ok);
        final decodedA = jsonDecode(responseA.body) as Map<String, dynamic>;
        expect(decodedA['id'], 'visit-col-a');

        final responseB = await http.post(
          Uri.parse('$baseUrl/records'),
          headers: {
            'content-type': 'application/json',
            'x-local-sync-key': collectorKeyB,
          },
          body: jsonEncode(
            _submission(
              id: 'visit-col-b',
              key: 'key-col-b',
              studyId: 'P102',
              phone: '+919000000102',
              collectorId: 'C002',
            ),
          ),
        );
        expect(responseB.statusCode, HttpStatus.ok);
        final decodedB = jsonDecode(responseB.body) as Map<String, dynamic>;
        expect(decodedB['id'], 'visit-col-b');
        expect(store.length, 2);
      },
    );

    test('rejects unauthenticated requests with 401 Unauthorized', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/records'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': 'invalid-or-unknown-key',
        },
        body: jsonEncode(_submission()),
      );
      expect(response.statusCode, HttpStatus.unauthorized);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['error'], 'Invalid local access key.');
    });

    test('collector key is forbidden from admin routes', () async {
      // GET /records
      final getResponse = await http.get(
        Uri.parse('$baseUrl/records'),
        headers: {'x-local-sync-key': collectorKeyA},
      );
      expect(getResponse.statusCode, HttpStatus.forbidden);
      expect(
        jsonDecode(getResponse.body)['error'],
        'Administrator access required.',
      );

      // PUT /records/:id
      final putResponse = await http.put(
        Uri.parse('$baseUrl/records/visit-1'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': collectorKeyA,
        },
        body: jsonEncode(_submission()),
      );
      expect(putResponse.statusCode, HttpStatus.forbidden);
      expect(
        jsonDecode(putResponse.body)['error'],
        'Administrator access required.',
      );

      // POST /records/:id/archive
      final archiveResponse = await http.post(
        Uri.parse('$baseUrl/records/visit-1/archive'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': collectorKeyA,
        },
        body: jsonEncode({'archived': true, 'actor': 'collector'}),
      );
      expect(archiveResponse.statusCode, HttpStatus.forbidden);
      expect(
        jsonDecode(archiveResponse.body)['error'],
        'Administrator access required.',
      );
    });

    test('admin key cannot upload records via collector route', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/records'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': adminKey,
        },
        body: jsonEncode(_submission()),
      );
      expect(response.statusCode, HttpStatus.forbidden);
      expect(jsonDecode(response.body)['error'], 'Collector access required.');
    });

    test('admin key can list, edit, and archive records', () async {
      // Seed record using collector key
      await http.post(
        Uri.parse('$baseUrl/records'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': collectorKeyA,
        },
        body: jsonEncode(_submission()),
      );

      // Admin GET /records
      final getResponse = await http.get(
        Uri.parse('$baseUrl/records'),
        headers: {'x-local-sync-key': adminKey},
      );
      expect(getResponse.statusCode, HttpStatus.ok);
      final records = jsonDecode(getResponse.body) as List;
      expect(records, hasLength(1));

      // Admin PUT /records/visit-1
      final edited = Map<String, dynamic>.from(records.first as Map)
        ..['stepTwoPlaceholderNote'] = 'Admin inspected and verified';
      final putResponse = await http.put(
        Uri.parse('$baseUrl/records/visit-1'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': adminKey,
        },
        body: jsonEncode(edited),
      );
      expect(putResponse.statusCode, HttpStatus.ok);
      expect(
        jsonDecode(putResponse.body)['stepTwoPlaceholderNote'],
        'Admin inspected and verified',
      );

      // Admin POST /records/visit-1/archive
      final archiveResponse = await http.post(
        Uri.parse('$baseUrl/records/visit-1/archive'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': adminKey,
        },
        body: jsonEncode({'archived': true, 'actor': 'admin-user'}),
      );
      expect(archiveResponse.statusCode, HttpStatus.ok);
      expect(jsonDecode(archiveResponse.body)['archivedBy'], 'admin-user');
    });

    test('GET /health accepts both collector and admin keys', () async {
      final collectorHealth = await http.get(
        Uri.parse('$baseUrl/health'),
        headers: {'x-local-sync-key': collectorKeyA},
      );
      expect(collectorHealth.statusCode, HttpStatus.ok);
      expect(jsonDecode(collectorHealth.body)['status'], 'ok');

      final adminHealth = await http.get(
        Uri.parse('$baseUrl/health'),
        headers: {'x-local-sync-key': adminKey},
      );
      expect(adminHealth.statusCode, HttpStatus.ok);
      expect(jsonDecode(adminHealth.body)['status'], 'ok');
      expect(jsonDecode(adminHealth.body)['recoveredFromBackup'], isFalse);
    });

    test(
      'GET /health exposes degraded recovery after primary corruption',
      () async {
        await store.upsertCollector(_submission());
        await store.upsertCollector(
          _submission(
            id: 'visit-2',
            key: 'upload-visit-2',
            studyId: 'P002',
            phone: '+919000000002',
          ),
        );
        await store.recordsFile.writeAsString('{invalid json', flush: true);
        final recovered = LocalRecordStore(dataDirectory);
        await recovered.load();
        final healthServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        healthServer.listen(
          (request) => handleRequest(
            request,
            recovered,
            const AccessKeys(collectorKeys: {collectorKeyA}, admin: adminKey),
          ),
        );
        try {
          final response = await http.get(
            Uri.parse('http://127.0.0.1:${healthServer.port}/health'),
            headers: {'x-local-sync-key': adminKey},
          );
          expect(response.statusCode, HttpStatus.ok);
          expect(jsonDecode(response.body)['status'], 'degraded');
          expect(jsonDecode(response.body)['recoveredFromBackup'], isTrue);
        } finally {
          await healthServer.close(force: true);
        }
      },
    );

    test('rejects DELETE requests with 405 Method Not Allowed', () async {
      final deleteResponse = await http.delete(
        Uri.parse('$baseUrl/records/visit-1'),
        headers: {'x-local-sync-key': adminKey},
      );
      expect(deleteResponse.statusCode, HttpStatus.methodNotAllowed);
      final body = jsonDecode(deleteResponse.body) as Map<String, dynamic>;
      expect(body['error'], 'DELETE is not supported by this service.');
    });
  });

  group('Enhanced 409 conflict detection with rich JSON payload', () {
    late HttpServer server;
    late String baseUrl;
    const collectorKey = 'collector-key-12345678';
    const adminKey = 'admin-key-1234567890';

    setUp(() async {
      final accessKeys = const AccessKeys(
        collectorKeys: {collectorKey},
        admin: adminKey,
      );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) => handleRequest(request, store, accessKeys));
      baseUrl = 'http://127.0.0.1:${server.port}';

      // Seed initial record
      await store.upsertCollector(_submission());
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('participant_mismatch: same studyId with different phone returns 409 JSON', () async {
      final conflictPayload = _submission(
        id: 'visit-2',
        key: 'upload-visit-2',
        studyId: 'P001',
        phone: '+919000000099',
      );

      // Direct store exception verification
      await _expectConflict(
        store.upsertCollector(conflictPayload),
        conflictType: 'participant_mismatch',
        message: 'Participant number belongs to another phone. Resolve this conflict before syncing.',
      );

      // HTTP endpoint response verification
      final response = await http.post(
        Uri.parse('$baseUrl/records'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': collectorKey,
        },
        body: jsonEncode(conflictPayload),
      );
      expect(response.statusCode, HttpStatus.conflict);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(json['error'], 'conflict');
      expect(
        json['message'],
        'Participant number belongs to another phone. Resolve this conflict before syncing.',
      );
      expect(json['conflictType'], 'participant_mismatch');
      expect(json['conflictId'], startsWith('conflict-'));
    });

    test(
      'participant_mismatch: same studyId with different name returns 409 JSON',
      () async {
        final conflictPayload = _submission(
          id: 'visit-2',
          key: 'upload-visit-2',
          studyId: 'P001',
          phone: '+919000000001',
        );
        (conflictPayload['participant'] as Map<String, dynamic>)['name'] =
            'Completely Different Name';
        (conflictPayload['confirmation'] as Map<String, dynamic>)['name'] =
            'Completely Different Name';

        await _expectConflict(
          store.upsertCollector(conflictPayload),
          conflictType: 'participant_mismatch',
          message: 'Participant number belongs to another name. Resolve this conflict before syncing.',
        );

        final response = await http.post(
          Uri.parse('$baseUrl/records'),
          headers: {
            'content-type': 'application/json',
            'x-local-sync-key': collectorKey,
          },
          body: jsonEncode(conflictPayload),
        );
        expect(response.statusCode, HttpStatus.conflict);
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        expect(json['error'], 'conflict');
        expect(
          json['message'],
          'Participant number belongs to another name. Resolve this conflict before syncing.',
        );
        expect(json['conflictType'], 'participant_mismatch');
        expect(json['conflictId'], startsWith('conflict-'));
      },
    );

    test(
      'shared phone may belong to distinct participants without merging visits',
      () async {
        final secondParticipant = _submission(
          id: 'visit-2',
          key: 'upload-visit-2',
          studyId: 'P002',
          phone: '+919000000001',
        );

        final response = await http.post(
          Uri.parse('$baseUrl/records'),
          headers: {
            'content-type': 'application/json',
            'x-local-sync-key': collectorKey,
          },
          body: jsonEncode(secondParticipant),
        );
        expect(response.statusCode, HttpStatus.ok);
        expect(store.length, 2);
        final lookup = await http.get(
          Uri.parse('$baseUrl/participants/lookup?phone=%2B919000000001'),
          headers: {'x-local-sync-key': collectorKey},
        );
        expect(lookup.statusCode, HttpStatus.ok);
        final result = jsonDecode(lookup.body) as Map<String, dynamic>;
        expect(result['found'], isTrue);
        expect(result['ambiguous'], isTrue);
        expect(result.containsKey('participant'), isFalse);
        expect((result['participants'] as List).map((p) => p['studyId']), [
          'P001',
          'P002',
        ]);
      },
    );

    test(
      'duplicate_visit: duplicate visit number for studyId returns 409 JSON',
      () async {
        final conflictPayload = _submission(
          id: 'visit-2',
          key: 'upload-visit-2',
          studyId: 'P001',
          phone: '+919000000001',
        );

        await _expectConflict(
          store.upsertCollector(conflictPayload),
          conflictType: 'duplicate_visit',
          message: 'Visit number is already recorded for this participant.',
        );

        final response = await http.post(
          Uri.parse('$baseUrl/records'),
          headers: {
            'content-type': 'application/json',
            'x-local-sync-key': collectorKey,
          },
          body: jsonEncode(conflictPayload),
        );
        expect(response.statusCode, HttpStatus.conflict);
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        expect(json['error'], 'conflict');
        expect(
          json['message'],
          'Visit number is already recorded for this participant.',
        );
        expect(json['conflictType'], 'duplicate_visit');
        expect(json['conflictId'], startsWith('conflict-'));
      },
    );

    test('idempotency_collision: upload key reused for different record ID returns 409 JSON', () async {
      final conflictPayload = _submission(
        id: 'visit-2',
        key: 'upload-visit-1',
        studyId: 'P002',
        phone: '+919000000002',
      );

      await _expectConflict(
        store.upsertCollector(conflictPayload),
        conflictType: 'idempotency_collision',
        message: 'Upload key is already used.',
      );

      final response = await http.post(
        Uri.parse('$baseUrl/records'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': collectorKey,
        },
        body: jsonEncode(conflictPayload),
      );
      expect(response.statusCode, HttpStatus.conflict);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(json['error'], 'conflict');
      expect(json['message'], 'Upload key is already used.');
      expect(json['conflictType'], 'idempotency_collision');
      expect(json['conflictId'], startsWith('conflict-'));
    });

    test('idempotency_collision: existing record ID with different idempotency key returns 409 JSON', () async {
      final conflictPayload = _submission(
        id: 'visit-1',
        key: 'different-upload-key',
      );

      await _expectConflict(
        store.upsertCollector(conflictPayload),
        conflictType: 'idempotency_collision',
        message: 'Record ID was already used for a different upload.',
      );

      final response = await http.post(
        Uri.parse('$baseUrl/records'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': collectorKey,
        },
        body: jsonEncode(conflictPayload),
      );
      expect(response.statusCode, HttpStatus.conflict);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(json['error'], 'conflict');
      expect(
        json['message'],
        'Record ID was already used for a different upload.',
      );
      expect(json['conflictType'], 'idempotency_collision');
      expect(json['conflictId'], startsWith('conflict-'));
    });
  });

  group('Collector credentials & identity binding (403 on mismatch)', () {
    late HttpServer server;
    late String baseUrl;
    const collectorKeyA = 'collector-alpha-key-123';
    const collectorKeyB = 'collector-bravo-key-456';
    const adminKey = 'admin-secure-master-key-789';

    setUp(() async {
      final accessKeys = const AccessKeys(
        collectorKeys: {collectorKeyA, collectorKeyB},
        admin: adminKey,
        collectorIdentities: {collectorKeyA: 'C001', collectorKeyB: 'C002'},
      );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) => handleRequest(request, store, accessKeys));
      baseUrl = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('rejects upload with 403 when payload collectorId does not match credential', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/records'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': collectorKeyA,
        },
        body: jsonEncode(_submission(collectorId: 'C002')),
      );

      expect(response.statusCode, HttpStatus.forbidden);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(json, {
        'error': 'collector_identity_mismatch',
        'message': 'Collector identity in payload does not match authenticated credential.',
      });
      expect(store.length, 0);
    });

    test(
      'accepts upload when payload collectorId matches credential',
      () async {
        final response = await http.post(
          Uri.parse('$baseUrl/records'),
          headers: {
            'content-type': 'application/json',
            'x-local-sync-key': collectorKeyA,
          },
          body: jsonEncode(_submission(collectorId: 'C001')),
        );

        expect(response.statusCode, HttpStatus.ok);
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        expect(json['id'], 'visit-1');
        expect(store.length, 1);
      },
    );

    test('parses collector key mappings in multiple valid formats', () {
      final keys1 = AccessKeys.fromEnvironment({
        'LOCAL_SYNC_COLLECTOR_KEYS':
            'C001:collector-key-12345678,C002:collector-key-87654321',
        'LOCAL_SYNC_ADMIN_KEY': 'admin-key-secure-12345',
      });
      expect(keys1, isNotNull);
      expect(keys1!.collectorIdForKey('collector-key-12345678'), 'C001');
      expect(keys1.collectorIdForKey('collector-key-87654321'), 'C002');

      final keys2 = AccessKeys.fromEnvironment({
        'LOCAL_SYNC_COLLECTOR_KEYS': 'collector-key-12345678:C001',
        'LOCAL_SYNC_ADMIN_KEY': 'admin-key-secure-12345',
      });
      expect(keys2, isNotNull);
      expect(keys2!.collectorIdForKey('collector-key-12345678'), 'C001');

      final keys3 = AccessKeys.fromEnvironment({
        'LOCAL_SYNC_COLLECTOR_KEYS': 'C01:collector-key-12345678',
        'LOCAL_SYNC_ADMIN_KEY': 'admin-key-secure-12345',
      });
      expect(keys3, isNotNull);
      expect(keys3!.collectorIdForKey('collector-key-12345678'), 'C01');

      final keys4 = AccessKeys.fromEnvironment({
        'LOCAL_SYNC_COLLECTOR_KEY': 'collector-key-12345678',
        'LOCAL_SYNC_ADMIN_KEY': 'admin-key-secure-12345',
      });
      expect(keys4, isNotNull);
      expect(keys4!.collectorIdForKey('collector-key-12345678'), 'C001');
    });
  });

  group('Online lookup endpoint (GET /participants/lookup)', () {
    late HttpServer server;
    late String baseUrl;
    const collectorKey = 'collector-alpha-key-123';
    const adminKey = 'admin-secure-master-key-789';

    setUp(() async {
      final accessKeys = const AccessKeys(
        collectorKeys: {collectorKey},
        admin: adminKey,
      );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) => handleRequest(request, store, accessKeys));
      baseUrl = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('rejects unauthenticated lookup with 401', () async {
      final response = await http.get(
        Uri.parse('$baseUrl/participants/lookup?phone=9000000001'),
      );
      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('rejects admin access to lookup endpoint with 403', () async {
      final response = await http.get(
        Uri.parse('$baseUrl/participants/lookup?phone=9000000001'),
        headers: {'x-local-sync-key': adminKey},
      );
      expect(response.statusCode, HttpStatus.forbidden);
    });

    test('rejects missing phone query parameter with 400', () async {
      final response = await http.get(
        Uri.parse('$baseUrl/participants/lookup'),
        headers: {'x-local-sync-key': collectorKey},
      );
      expect(response.statusCode, HttpStatus.badRequest);
    });

    test(
      'returns found: false when participant phone does not exist',
      () async {
        final response = await http.get(
          Uri.parse('$baseUrl/participants/lookup?phone=9999999999'),
          headers: {'x-local-sync-key': collectorKey},
        );
        expect(response.statusCode, HttpStatus.ok);
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        expect(json, {'found': false});
      },
    );

    test('returns found: true and participant info with nextVisitNumber 2 after visit 1', () async {
      await store.upsertCollector(
        _submission(
          id: 'visit-1',
          key: 'upload-visit-1',
          studyId: 'C01-000001',
          phone: '+919000000001',
          visitNumber: 1,
        ),
      );

      final response = await http.get(
        Uri.parse('$baseUrl/participants/lookup?phone=%2B919000000001'),
        headers: {'x-local-sync-key': collectorKey},
      );
      expect(response.statusCode, HttpStatus.ok);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(json['found'], isTrue);
      expect(json['participant'], {
        'studyId': 'C01-000001',
        'name': 'Fictional Participant',
        'nextVisitNumber': 2,
      });
      // Verifies only operational info is returned (no health/questionnaire)
      expect(
        (json['participant'] as Map).keys,
        containsAll(['studyId', 'name', 'nextVisitNumber']),
      );
      expect(
        (json['participant'] as Map).containsKey('questionnaire'),
        isFalse,
      );
      expect(
        (json['participant'] as Map).containsKey('stepTwoMeasurement'),
        isFalse,
      );
    });

    test('returns nextVisitNumber 3 when participant already has visit 1 and visit 2', () async {
      await store.upsertCollector(
        _submission(
          id: 'visit-1',
          key: 'upload-visit-1',
          studyId: 'C01-000001',
          phone: '+919000000001',
          visitNumber: 1,
        ),
      );
      await store.upsertCollector(
        _submission(
          id: 'visit-2',
          key: 'upload-visit-2',
          studyId: 'C01-000001',
          phone: '+919000000001',
          visitNumber: 2,
        ),
      );

      final response = await http.get(
        Uri.parse('$baseUrl/participants/lookup?phone=9000000001'),
        headers: {'x-local-sync-key': collectorKey},
      );
      expect(response.statusCode, HttpStatus.ok);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(json['found'], isTrue);
      expect(json['participant']['nextVisitNumber'], 3);
    });
  });

  group('Shared Participant ID & Visit Number Validation', () {
    late HttpServer server;
    late String baseUrl;
    const collectorKeyA = 'collector-alpha-key-123';
    const collectorKeyB = 'collector-bravo-key-456';
    const collectorKey100 = 'collector-hundred-key-789';
    const collectorKey1000 = 'collector-thousand-key-789';
    const adminKey = 'admin-secure-master-key-789';

    setUp(() async {
      final accessKeys = const AccessKeys(
        collectorKeys: {
          collectorKeyA,
          collectorKeyB,
          collectorKey100,
          collectorKey1000,
        },
        admin: adminKey,
        collectorIdentities: {
          collectorKeyA: 'C001',
          collectorKeyB: 'C002',
          collectorKey100: 'C100',
          collectorKey1000: 'C1000',
        },
      );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) => handleRequest(request, store, accessKeys));
      baseUrl = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('rejects invalid studyId formats with 400', () async {
      for (final invalidId in [
        'INVALID',
        'P01',
        'C1-000001',
        'C01-12345',
      ]) {
        final response = await http.post(
          Uri.parse('$baseUrl/records'),
          headers: {
            'content-type': 'application/json',
            'x-local-sync-key': collectorKeyA,
          },
          body: jsonEncode(_submission(studyId: invalidId)),
        );
        expect(
          response.statusCode,
          HttpStatus.badRequest,
          reason: 'Failed for $invalidId',
        );
      }
    });

    test(
      'accepts legacy, padded, and unbounded collector studyId formats',
      () async {
        final response1 = await http.post(
          Uri.parse('$baseUrl/records'),
          headers: {
            'content-type': 'application/json',
            'x-local-sync-key': collectorKeyA,
          },
          body: jsonEncode(
            _submission(
              id: 'v1',
              key: 'k1',
              studyId: 'C01-000001',
              phone: '+919000000001',
            ),
          ),
        );
        expect(response1.statusCode, HttpStatus.ok);

        final response2 = await http.post(
          Uri.parse('$baseUrl/records'),
          headers: {
            'content-type': 'application/json',
            'x-local-sync-key': collectorKeyA,
          },
          body: jsonEncode(
            _submission(
              id: 'v2',
              key: 'k2',
              studyId: 'C001-000002',
              phone: '+919000000002',
            ),
          ),
        );
        expect(response2.statusCode, HttpStatus.ok);

        final response3 = await http.post(
          Uri.parse('$baseUrl/records'),
          headers: {
            'content-type': 'application/json',
            'x-local-sync-key': collectorKeyA,
          },
          body: jsonEncode(
            _submission(
              id: 'v3',
              key: 'k3',
              studyId: 'P001',
              phone: '+919000000003',
            ),
          ),
        );
        expect(response3.statusCode, HttpStatus.ok);

        final response4 = await http.post(
          Uri.parse('$baseUrl/records'),
          headers: {
            'content-type': 'application/json',
            'x-local-sync-key': collectorKey100,
          },
          body: jsonEncode(
            _submission(
              id: 'v4',
              key: 'k4',
              studyId: 'C100-000001',
              collectorId: 'C100',
              phone: '+919000000004',
            ),
          ),
        );
        expect(response4.statusCode, HttpStatus.ok);

        final response5 = await http.post(
          Uri.parse('$baseUrl/records'),
          headers: {
            'content-type': 'application/json',
            'x-local-sync-key': collectorKey1000,
          },
          body: jsonEncode(
            _submission(
              id: 'v5',
              key: 'k5',
              studyId: 'C1000-000001',
              collectorId: 'C1000',
              phone: '+919000000005',
            ),
          ),
        );
        expect(response5.statusCode, HttpStatus.ok);
      },
    );

    test('rejects new participant with collector-scoped ID if prefix mismatches collector', () async {
      // Collector A is C001, trying to create new participant with C02-000001
      final response = await http.post(
        Uri.parse('$baseUrl/records'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': collectorKeyA,
        },
        body: jsonEncode(_submission(studyId: 'C02-000001')),
      );
      expect(response.statusCode, HttpStatus.badRequest);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(
        json['error'],
        'Participant Study ID prefix does not match authenticated collector.',
      );
    });

    test('allows second collector to upload follow-up visit for existing participant created by another collector', () async {
      // Collector A (C001) creates participant C01-000001 visit 1
      await http.post(
        Uri.parse('$baseUrl/records'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': collectorKeyA,
        },
        body: jsonEncode(
          _submission(
            id: 'v1',
            key: 'k1',
            studyId: 'C01-000001',
            phone: '+919000000001',
            visitNumber: 1,
            collectorId: 'C001',
          ),
        ),
      );

      // Collector B (C002) conducts follow-up visit 2 for existing participant C01-000001
      final response = await http.post(
        Uri.parse('$baseUrl/records'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': collectorKeyB,
        },
        body: jsonEncode(
          _submission(
            id: 'v2',
            key: 'k2',
            studyId: 'C01-000001',
            phone: '+919000000001',
            visitNumber: 2,
            collectorId: 'C002',
          ),
        ),
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(store.length, 2);
    });

    test('rejects visitNumber less than 1 with 400', () async {
      final response = await http.post(
        Uri.parse('$baseUrl/records'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': collectorKeyA,
        },
        body: jsonEncode(_submission(visitNumber: 0)),
      );
      expect(response.statusCode, HttpStatus.badRequest);
    });
  });

  group('Server Conflict Inbox, admin review/resolution, and collector idempotent retry', () {
    late HttpServer server;
    late String baseUrl;
    const collectorKey = 'collector-alpha-key-123';
    const adminKey = 'admin-secure-master-key-789';

    setUp(() async {
      final accessKeys = const AccessKeys(
        collectorKeys: {collectorKey},
        admin: adminKey,
      );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) => handleRequest(request, store, accessKeys));
      baseUrl = 'http://127.0.0.1:${server.port}';

      // Seed initial record: Visit 1 for P001
      await store.upsertCollector(
        _submission(
          id: 'visit-1',
          key: 'upload-visit-1',
          studyId: 'P001',
          phone: '+919000000001',
          visitNumber: 1,
        ),
      );
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('stores conflict report on 409, deduplicates on retry, allows admin review and resolve, and retry succeeds idempotently', () async {
      final conflictPayload = _submission(
        id: 'visit-2',
        key: 'upload-visit-2',
        studyId: 'P001',
        phone: '+919000000001',
        visitNumber: 1, // Duplicate visit 1 for P001
      );

      // 1. Collector posts conflicting record -> 409 Conflict
      final response1 = await http.post(
        Uri.parse('$baseUrl/records'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': collectorKey,
        },
        body: jsonEncode(conflictPayload),
      );
      expect(response1.statusCode, HttpStatus.conflict);
      final json1 = jsonDecode(response1.body) as Map<String, dynamic>;
      expect(json1['error'], 'conflict');
      expect(json1['conflictType'], 'duplicate_visit');
      final conflictId = json1['conflictId'] as String;
      expect(conflictId, startsWith('conflict-'));

      // Verify conflict report stored in conflicts.json on disk
      expect(store.conflictsFile.existsSync(), isTrue);
      expect(store.conflictsCount, 1);
      final initialReport = store.getConflict(conflictId)!;
      expect(initialReport['id'], conflictId);
      expect(initialReport['conflictType'], 'duplicate_visit');
      expect(initialReport['collectorId'], 'C001');
      expect(initialReport['idempotencyKey'], 'upload-visit-2');
      expect(initialReport['status'], 'pending');
      expect(initialReport['resolution'], isNull);
      expect(initialReport['conflictingRecordId'], 'visit-1');

      // 2. Collector retries upload -> deduplicated by idempotencyKey
      final retry1 = await http.post(
        Uri.parse('$baseUrl/records'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': collectorKey,
        },
        body: jsonEncode(conflictPayload),
      );
      expect(retry1.statusCode, HttpStatus.conflict);
      final retryJson = jsonDecode(retry1.body) as Map<String, dynamic>;
      expect(retryJson['conflictId'], conflictId); // Same conflictId returned
      expect(store.conflictsCount, 1); // Not duplicated!

      // 3. Collector cannot access admin conflict endpoints
      final collectorGetConflicts = await http.get(
        Uri.parse('$baseUrl/conflicts'),
        headers: {'x-local-sync-key': collectorKey},
      );
      expect(collectorGetConflicts.statusCode, HttpStatus.forbidden);

      // 4. Admin lists conflicts via GET /conflicts
      final adminList = await http.get(
        Uri.parse('$baseUrl/conflicts'),
        headers: {'x-local-sync-key': adminKey},
      );
      expect(adminList.statusCode, HttpStatus.ok);
      final listBody = jsonDecode(adminList.body) as List;
      expect(listBody, hasLength(1));
      expect(listBody.first['id'], conflictId);

      // 5. Admin gets single conflict report via GET /conflicts/:id
      final adminGet = await http.get(
        Uri.parse('$baseUrl/conflicts/$conflictId'),
        headers: {'x-local-sync-key': adminKey},
      );
      expect(adminGet.statusCode, HttpStatus.ok);
      expect(jsonDecode(adminGet.body)['id'], conflictId);

      // 6. Admin marks conflict reviewed via POST /conflicts/:id/review
      final reviewResponse = await http.post(
        Uri.parse('$baseUrl/conflicts/$conflictId/review'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': adminKey,
        },
        body: jsonEncode({
          'status': 'reviewed',
          'notes': 'Verified with field team that this is visit 2',
        }),
      );
      expect(reviewResponse.statusCode, HttpStatus.ok);
      final reviewJson =
          jsonDecode(reviewResponse.body) as Map<String, dynamic>;
      expect(reviewJson['status'], 'reviewed');
      expect(
        reviewJson['notes'],
        'Verified with field team that this is visit 2',
      );

      // 7. Admin resolves conflict via POST /conflicts/:id/resolve
      final resolveResponse = await http.post(
        Uri.parse('$baseUrl/conflicts/$conflictId/resolve'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': adminKey,
        },
        body: jsonEncode({
          'action': 'accept_as_corrected',
          'studyId': 'P001',
          'visitNumber': 2,
        }),
      );
      expect(resolveResponse.statusCode, HttpStatus.ok);
      final resolveJson =
          jsonDecode(resolveResponse.body) as Map<String, dynamic>;
      expect(resolveJson['status'], 'resolved');
      expect(resolveJson['resolution']['action'], 'accept_as_corrected');

      // Verify accepted records in store now contains the resolved record
      expect(store.length, 2);
      final acceptedVisit2 = store.records().firstWhere(
        (r) => r['id'] == 'visit-2',
      );
      expect(acceptedVisit2['visitNumber'], 2);
      expect(acceptedVisit2['syncState'], 'synced');

      // 8. Collector retries upload after resolution -> succeeds idempotently (200 OK)
      final retryAfterResolution = await http.post(
        Uri.parse('$baseUrl/records'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': collectorKey,
        },
        body: jsonEncode(
          conflictPayload,
        ), // Original payload with visitNumber 1
      );
      expect(retryAfterResolution.statusCode, HttpStatus.ok);
      final successJson =
          jsonDecode(retryAfterResolution.body) as Map<String, dynamic>;
      expect(successJson['id'], 'visit-2');
      expect(
        successJson['visitNumber'],
        2,
      ); // Returns the accepted corrected record!
    });

    test('rejects DELETE requests on /conflicts and /records with 405 Method Not Allowed', () async {
      final deleteConflicts = await http.delete(
        Uri.parse('$baseUrl/conflicts'),
        headers: {'x-local-sync-key': adminKey},
      );
      expect(deleteConflicts.statusCode, HttpStatus.methodNotAllowed);

      final deleteSingleConflict = await http.delete(
        Uri.parse('$baseUrl/conflicts/conflict-dummy-123'),
        headers: {'x-local-sync-key': adminKey},
      );
      expect(deleteSingleConflict.statusCode, HttpStatus.methodNotAllowed);

      final deleteRecord = await http.delete(
        Uri.parse('$baseUrl/records/visit-1'),
        headers: {'x-local-sync-key': adminKey},
      );
      expect(deleteRecord.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('Questionnaire preservation during admin edit (replaceAdmin)', () {
    late HttpServer server;
    late String baseUrl;
    const collectorKey = 'collector-alpha-key-123';
    const adminKey = 'admin-secure-master-key-789';

    setUp(() async {
      final accessKeys = const AccessKeys(
        collectorKeys: {collectorKey},
        admin: adminKey,
      );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) => handleRequest(request, store, accessKeys));
      baseUrl = 'http://127.0.0.1:${server.port}';

      // Seed initial record with questionnaire
      await store.upsertCollector(
        _submission(
          id: 'visit-q1',
          key: 'upload-visit-q1',
          studyId: 'P001',
          phone: '+919000000001',
          questionnaire: _validQuestionnaire(age: 30),
        ),
      );
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('preserves existing questionnaire when admin PUT omits questionnaire or passes null', () async {
      final stored = store.records().firstWhere((r) => r['id'] == 'visit-q1');
      expect(stored['questionnaire'], isNotNull);
      expect(stored['questionnaire']['age'], 30);

      // Admin updates only a note, omitting questionnaire
      final adminEdit = Map<String, dynamic>.from(stored)
        ..remove('questionnaire')
        ..['stepTwoPlaceholderNote'] = 'Admin checked blood pressure';

      final response = await http.put(
        Uri.parse('$baseUrl/records/visit-q1'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': adminKey,
        },
        body: jsonEncode(adminEdit),
      );
      expect(response.statusCode, HttpStatus.ok);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(json['stepTwoPlaceholderNote'], 'Admin checked blood pressure');
      expect(json['questionnaire'], isNotNull);
      expect(json['questionnaire']['age'], 30);
      expect(json['questionnaire']['bmi'], stored['questionnaire']['bmi']);

      // Reload store to verify questionnaire was preserved on disk
      final reloaded = LocalRecordStore(dataDirectory);
      await reloaded.load();
      final diskRecord = reloaded.records().firstWhere(
        (r) => r['id'] == 'visit-q1',
      );
      expect(diskRecord['questionnaire'], isNotNull);
      expect(diskRecord['questionnaire']['age'], 30);
    });

    test('updates questionnaire when admin PUT supplies a new non-null questionnaire', () async {
      final stored = store.records().firstWhere((r) => r['id'] == 'visit-q1');
      final adminEdit = Map<String, dynamic>.from(stored)
        ..['questionnaire'] = _validQuestionnaire(age: 35);

      final response = await http.put(
        Uri.parse('$baseUrl/records/visit-q1'),
        headers: {
          'content-type': 'application/json',
          'x-local-sync-key': adminKey,
        },
        body: jsonEncode(adminEdit),
      );
      expect(response.statusCode, HttpStatus.ok);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(json['questionnaire']['age'], 35);
    });
  });
}

Future<void> _expectConflict(
  Future<Object?> operation, {
  String? conflictType,
  String? message,
}) async {
  await expectLater(
    operation,
    throwsA(
      isA<ApiException>()
          .having(
            (exception) => exception.statusCode,
            'statusCode',
            HttpStatus.conflict,
          )
          .having(
            (exception) => exception.conflictType,
            'conflictType',
            conflictType ?? anything,
          )
          .having(
            (exception) => exception.message,
            'message',
            message ?? anything,
          ),
    ),
  );
}

Future<void> _expectBadRequest(Future<Object?> operation) async {
  await expectLater(
    operation,
    throwsA(
      isA<ApiException>().having(
        (exception) => exception.statusCode,
        'statusCode',
        HttpStatus.badRequest,
      ),
    ),
  );
}

Map<String, dynamic> _validQuestionnaire({num age = 30}) => {
  'studySite': 'Site A',
  'sex': 'female',
  'education': 'tertiary',
  'employment': 'employed',
  'fruitFrequency': 'daily',
  'vegetableFrequency': 'daily',
  'sugaryDrinkFrequency': 'rarely',
  'processedFoodFrequency': 'rarely',
  'age': age,
  'activeDaysPerWeek': 5,
  'activeMinutesPerDay': 30,
  'sleepHours': 8,
  'heightCm': 170,
  'weightKg': 68,
  'waistCm': 80,
  'bpOneSystolic': 120,
  'bpOneDiastolic': 80,
  'bpTwoSystolic': 120,
  'bpTwoDiastolic': 80,
  'weeklyActiveMinutes': 150,
  'bmi': 68 / (1.7 * 1.7),
  'averageSystolic': 120,
  'averageDiastolic': 80,
};

Map<String, dynamic> _validQuestionnaireV2({num age = 30}) => {
  ..._validQuestionnaire(age: age),
  'schemaVersion': 2,
  'heightMissingReason': null,
  'weightMissingReason': null,
  'waistMissingReason': null,
  'bpOneMissingReason': null,
  'bpTwoMissingReason': null,
};

Map<String, dynamic> _submission({
  String id = 'visit-1',
  String key = 'upload-visit-1',
  String studyId = 'P001',
  String phone = '+919000000001',
  String collectorId = 'C001',
  int visitNumber = 1,
  Map<String, dynamic>? questionnaire,
}) => {
  'id': id,
  'idempotencyKey': key,
  'participant': {
    'studyId': studyId,
    'name': 'Fictional Participant',
    'indianPhone': phone,
  },
  'visitNumber': visitNumber,
  'collectorId': collectorId,
  'createdAt': '2026-09-13T00:00:00.000Z',
  'updatedAt': '2026-09-13T00:00:00.000Z',
  'status': 'submitted',
  'syncState': 'pending',
  'reviewState': 'pending',
  'revision': 1,
  'confirmation': {
    'name': 'Fictional Participant',
    'indianPhone': phone,
    'visitNumber': visitNumber,
    'confirmedAt': '2026-09-13T00:00:00.000Z',
  },
  'stepTwoMeasurement': null,
  'questionnaire': questionnaire,
  'submittedAt': '2026-09-13T00:00:00.000Z',
};
