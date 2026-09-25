import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:project2/domain/ncd_questionnaire.dart';
import 'package:project2/local_demo_app.dart';
import 'package:project2/local_storage/local_record_store.dart';
import 'package:project2/local_storage/local_visit_draft_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('generic app sessions', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    testWidgets('sign out clears credentials and restart stays signed out', (
      tester,
    ) async {
      final server = _TestCollectorServer();
      final storage = const FlutterSecureStorage();
      final recordStore = _MemoryRecordStore([]);

      await _mountApp(tester, storage, recordStore, server);
      await _signIn(tester, server.baseUrl);
      expect(find.text('Hello, Collector 7'), findsOneWidget);
      expect(await storage.read(key: 'local_session_token'), 'session-1');
      expect(await storage.read(key: 'local_collector_key'), _accessKey);

      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(await storage.read(key: 'local_session_token'), isNull);
      expect(await storage.read(key: 'local_collector_key'), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _mountApp(tester, storage, recordStore, server);
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(find.text('Hello, Collector 7'), findsNothing);
      expect(server.sessionStarts, 1);
    });

    testWidgets(
      'restart retries pending local record and 401 signs out safely',
      (tester) async {
        final server = _TestCollectorServer();
        final storage = const FlutterSecureStorage();
        final recordStore = _MemoryRecordStore([_pendingVisit()]);

        await _mountApp(tester, storage, recordStore, server);
        await _signIn(tester, server.baseUrl);
        expect(server.recordSessionTokens, ['session-1']);
        expect(recordStore.records.single['syncState'], 'synced');

        recordStore.records = [_pendingVisit()];
        await recordStore.writeAll(recordStore.records);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        server.activeSession = 'session-from-another-phone';
        await _mountApp(tester, storage, recordStore, server);
        await tester.pumpAndSettle();

        expect(server.sessionStarts, 1);
        expect(server.recordSessionTokens, ['session-1', 'session-1']);
        expect(find.byType(TextFormField), findsNWidgets(3));
        expect(find.text('Hello, Collector 7'), findsNothing);
        expect(recordStore.records.single['id'], 'LOCAL-PENDING-1');
        expect(recordStore.records.single['syncState'], 'failed');
        expect(await storage.read(key: 'local_session_token'), isNull);
        expect(await storage.read(key: 'local_collector_key'), isNull);
      },
    );

    testWidgets(
      'physical Study ID resumes the highest saved visit while offline',
      (tester) async {
        final server = _TestCollectorServer();
        final storage = const FlutterSecureStorage();
        final recordStore = _MemoryRecordStore([
          _savedVisit(visitNumber: 4),
          _savedVisit(visitNumber: 2),
        ]);

        await _mountApp(tester, storage, recordStore, server);
        await _signIn(tester, server.baseUrl);
        await tester.tap(find.text('New participant'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Repeat visit using Study ID'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).first,
          ' c07-1234567890123456 ',
        );
        await tester.tap(
          find.widgetWithText(FilledButton, 'Find saved participant'),
        );
        await tester.pumpAndSettle();

        expect(find.text('Confirm visit'), findsOneWidget);
        expect(find.text('C07-1234567890123456'), findsOneWidget);
        expect(find.text('Saved Participant'), findsOneWidget);
        expect(find.text('Visit 5'), findsOneWidget);
        expect(server.lookupRequests, 0);
      },
    );

    testWidgets(
      'unknown physical Study ID fails closed with offline guidance',
      (tester) async {
        final server = _TestCollectorServer();
        final storage = const FlutterSecureStorage();
        final recordStore = _MemoryRecordStore([]);

        await _mountApp(tester, storage, recordStore, server);
        await _signIn(tester, server.baseUrl);
        await tester.tap(find.text('New participant'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Repeat visit using Study ID'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).first, 'C07-000123');
        await tester.tap(
          find.widgetWithText(FilledButton, 'Find saved participant'),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('No saved visit for this Study ID'),
          findsOneWidget,
        );
        expect(find.text('Confirm visit'), findsNothing);
        expect(server.lookupRequests, 0);
      },
    );

    testWidgets('force-stop restores participant, step, and entered answers', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final server = _TestCollectorServer();
      final storage = const FlutterSecureStorage();
      final recordStore = _MemoryRecordStore([]);

      await _mountApp(tester, storage, recordStore, server);
      await _signIn(tester, server.baseUrl);
      await tester.tap(find.text('New participant'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Resume Person');
      await tester.enterText(find.byType(TextFormField).at(1), '9000000002');
      await tester.tap(find.widgetWithText(FilledButton, 'Find participant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm and continue'));
      await tester.pumpAndSettle();
      expect(find.text('NCD risk questionnaire'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '42');
      await tester.pumpAndSettle();

      // Dispose the whole app to model an OS force-stop and relaunch.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _mountApp(tester, storage, recordStore, server);
      expect(find.text('In-progress visit saved'), findsOneWidget);
      await tester.tap(find.text('In-progress visit saved'));
      await tester.pumpAndSettle();

      expect(find.text('NCD risk questionnaire'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextFormField && widget.controller?.text == '42',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Resume Person'), findsOneWidget);
      expect(find.text('First visit'), findsOneWidget);
    });

    testWidgets(
      'invalid restored questionnaire returns to required questions',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({
          'collector_visit_drafts_v1': jsonEncode([
            {
              'id': 'DRAFT-INVALID-QUESTIONNAIRE',
              'recordId': 'LOCAL-INVALID-QUESTIONNAIRE',
              'participant': {
                'studyId': 'C07-1234567890123456',
                'name': 'Resume Person',
                'phone': '+919000000002',
              },
              'visitNumber': 1,
              'collector': 'C007',
              'step': 3,
              'questionnaireDraft': {'measurements': false},
              'questionnaire': {'schemaVersion': 999},
            },
          ]),
        });
        final server = _TestCollectorServer();

        await _mountApp(
          tester,
          const FlutterSecureStorage(),
          _MemoryRecordStore([]),
          server,
        );
        await _signIn(tester, server.baseUrl);
        await tester.tap(find.text('In-progress visit saved'));
        await tester.pumpAndSettle();

        expect(find.text('NCD risk questionnaire'), findsOneWidget);
        expect(find.text('Review submission'), findsNothing);
        expect(find.text('Submit visit'), findsNothing);
      },
    );

    testWidgets('malformed draft entry does not hide valid saved visits', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({
        'collector_visit_drafts_v1': jsonEncode([
          42,
          {
            'id': 'DRAFT-VALID-ALONGSIDE-BAD',
            'recordId': 'LOCAL-VALID-ALONGSIDE-BAD',
            'participant': {
              'studyId': 'C07-1234567890123456',
              'name': 'Resume Person',
              'phone': '+919000000002',
            },
            'visitNumber': 1,
            'collector': 'C007',
            'step': 0,
          },
        ]),
      });
      final server = _TestCollectorServer();

      await _mountApp(
        tester,
        const FlutterSecureStorage(),
        _MemoryRecordStore([]),
        server,
      );
      await _signIn(tester, server.baseUrl);

      expect(find.text('Some saved visits need attention'), findsOneWidget);
      expect(find.text('In-progress visit saved'), findsOneWidget);
      await tester.tap(find.text('In-progress visit saved'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm visit'), findsOneWidget);
    });

    testWidgets('repeat lookup offers the existing unfinished visit', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({
        'collector_visit_drafts_v1': jsonEncode([
          {
            'id': 'DRAFT-EXISTING-REPEAT',
            'recordId': 'LOCAL-EXISTING-REPEAT',
            'participant': {
              'studyId': 'C07-1234567890123456',
              'name': 'Saved Participant',
              'phone': '+919000000001',
            },
            'visitNumber': 3,
            'collector': 'C007',
            'step': 0,
          },
        ]),
      });
      final server = _TestCollectorServer();

      await _mountApp(
        tester,
        const FlutterSecureStorage(),
        _MemoryRecordStore([_savedVisit(visitNumber: 2)]),
        server,
      );
      await _signIn(tester, server.baseUrl);
      await tester.tap(find.text('New participant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Repeat visit using Study ID'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'C07-1234567890123456',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Find saved participant'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Visit already in progress'), findsOneWidget);
      expect(find.textContaining('Visit 3'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Participant'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Find saved participant'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resume visit'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm visit'), findsOneWidget);
      expect(find.text('Visit 3'), findsOneWidget);
    });

    testWidgets(
      'injected test storage keeps a paused draft across app restart',
      (tester) async {
        tester.view.physicalSize = const Size(430, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final server = _TestCollectorServer();
        final recordStore = _MemoryRecordStore([]);

        await _mountApp(tester, null, recordStore, server);
        await _signIn(tester, server.baseUrl);
        await tester.tap(find.text('New participant'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).at(0),
          'Resume Person',
        );
        await tester.enterText(find.byType(TextFormField).at(1), '9000000002');
        await tester.tap(find.widgetWithText(FilledButton, 'Find participant'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm and continue'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).first, '42');
        await tester.pumpAndSettle();

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await _mountApp(tester, null, recordStore, server);

        expect(find.text('In-progress visit saved'), findsOneWidget);
        await tester.tap(find.text('In-progress visit saved'));
        await tester.pumpAndSettle();
        expect(find.text('NCD risk questionnaire'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextFormField && widget.controller?.text == '42',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('completed questionnaire remains filled after stepping back', (
      tester,
    ) async {
      const questionnaire = NcdQuestionnaire(
        studySite: 'community_clinic',
        age: 42,
        sex: 'female',
        education: 'secondary',
        employment: 'employed',
        fruitFrequency: 'daily',
        vegetableFrequency: 'daily',
        sugaryDrinkFrequency: 'one_to_two_days',
        processedFoodFrequency: 'never',
        activeDaysPerWeek: 5,
        activeMinutesPerDay: 30,
        sleepHours: 7.5,
        heightCm: 160,
        weightKg: 64,
        waistCm: 82,
        bpOneSystolic: 120,
        bpOneDiastolic: 80,
        bpTwoSystolic: 124,
        bpTwoDiastolic: 78,
      );
      FlutterSecureStorage.setMockInitialValues({
        'collector_visit_drafts_v1': jsonEncode([
          {
            'id': 'DRAFT-RESUME-1',
            'recordId': 'LOCAL-RESUME-1',
            'participant': {
              'studyId': 'C07-1234567890123456',
              'name': 'Resume Person',
              'phone': '+919000000002',
            },
            'visitNumber': 2,
            'collector': 'C007',
            'step': 2,
            'questionnaireDraft': {
              'measurements': false,
              'site': 'community_clinic',
              'age': '42',
            },
            'questionnaire': questionnaire.toMap(),
            'stepTwoNote': 'saved optional note',
          },
        ]),
      });
      final testerServer = _TestCollectorServer();
      final storage = const FlutterSecureStorage();

      await _mountApp(tester, storage, _MemoryRecordStore([]), testerServer);
      await _signIn(tester, testerServer.baseUrl);
      await tester.tap(find.text('In-progress visit saved'));
      await tester.pumpAndSettle();

      expect(find.text('Optional Step 2'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.controller?.text == 'saved optional note',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('NCD risk questionnaire'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextFormField && widget.controller?.text == '42',
        ),
        findsOneWidget,
      );
    });

    testWidgets('saved submission suppresses its stale matching draft', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({
        'collector_visit_drafts_v1': jsonEncode([
          {
            'id': 'DRAFT-SUBMITTED-4',
            'recordId': 'LOCAL-SAVED-4',
            'participant': {
              'studyId': 'C07-1234567890123456',
              'name': 'Saved Participant',
              'phone': '+919000000001',
            },
            'visitNumber': 4,
            'collector': 'C007',
            'step': 3,
          },
        ]),
      });
      final testerServer = _TestCollectorServer();
      await _mountApp(
        tester,
        const FlutterSecureStorage(),
        _MemoryRecordStore([_savedVisit(visitNumber: 4)]),
        testerServer,
      );
      await _signIn(tester, testerServer.baseUrl);

      expect(find.text('In-progress visit saved'), findsNothing);
      expect(find.text('Saved Participant'), findsOneWidget);
    });
  }, skip: !const bool.fromEnvironment('LOCAL_GENERIC_RELEASE'));
}

const _accessKey = 'synthetic-collector-access-key';

Future<void> _mountApp(
  WidgetTester tester,
  FlutterSecureStorage? storage,
  LocalRecordStore recordStore,
  _TestCollectorServer server, {
  LocalVisitDraftStore? draftStore,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      home: LocalDemoApp(
        recordStore: recordStore,
        secureStorage: storage,
        visitDraftStore: draftStore,
        localHttpClient: server.client,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _signIn(WidgetTester tester, String serverUrl) async {
  await tester.enterText(find.byType(TextFormField).at(0), '7');
  await tester.enterText(find.byType(TextFormField).at(1), serverUrl);
  await tester.enterText(find.byType(TextFormField).at(2), _accessKey);
  await tester.ensureVisible(find.widgetWithText(FilledButton, 'Continue'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
  await tester.pumpAndSettle();
}

Map<String, Object?> _pendingVisit() => {
  'id': 'LOCAL-PENDING-1',
  'participant': {
    'studyId': 'C07-1234567890123456',
    'name': 'Synthetic Participant',
    'indianPhone': '+919000000001',
  },
  'visitNumber': 1,
  'collectorId': 'C007',
  'submittedAt': '2026-09-13T00:00:00.000Z',
  'syncState': 'pending',
  'idempotencyKey': 'upload_LOCAL-PENDING-1',
};

Map<String, Object?> _savedVisit({required int visitNumber}) => {
  'id': 'LOCAL-SAVED-$visitNumber',
  'participant': {
    'studyId': 'C07-1234567890123456',
    'name': 'Saved Participant',
    'indianPhone': '+919000000001',
  },
  'visitNumber': visitNumber,
  'collectorId': 'C007',
  'submittedAt': '2026-09-13T00:00:00.000Z',
  'syncState': 'synced',
  'idempotencyKey': 'upload_LOCAL-SAVED-$visitNumber',
};

class _MemoryRecordStore implements LocalRecordStore {
  _MemoryRecordStore(this.records);

  List<Map<String, Object?>> records;

  @override
  Future<List<Map<String, Object?>>> readAll() async => records
      .map(
        (record) => (jsonDecode(jsonEncode(record)) as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      )
      .toList();

  @override
  Future<void> writeAll(List<Map<String, Object?>> newRecords) async {
    records = newRecords
        .map(
          (record) => (jsonDecode(jsonEncode(record)) as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList();
  }
}

class _TestCollectorServer {
  _TestCollectorServer() {
    client = MockClient(_handleRequest);
  }

  late final MockClient client;
  String? activeSession;
  int sessionStarts = 0;
  int lookupRequests = 0;
  final List<String?> recordSessionTokens = [];

  String get baseUrl => 'http://study.test:8787';

  Future<http.Response> _handleRequest(http.Request request) async {
    if (request.url.path == '/participants/lookup') {
      lookupRequests++;
      return http.Response('{"found":false}', 200);
    }
    if (request.method == 'POST' && request.url.path == '/collector/session') {
      final payload = jsonDecode(request.body) as Map;
      sessionStarts++;
      activeSession = 'session-$sessionStarts';
      return http.Response(
        jsonEncode({
          'collectorId': payload['collectorId'],
          'sessionToken': activeSession,
        }),
        200,
      );
    }
    if (request.method == 'POST' && request.url.path == '/records') {
      recordSessionTokens.add(request.headers['x-local-session']);
      if (request.headers['x-local-session'] != activeSession) {
        return http.Response('{"error":"collector_session_expired"}', 401);
      }
      return http.Response('{"stored":true}', 201);
    }
    return http.Response('{"error":"not_found"}', 404);
  }
}
