import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project2/local_storage/local_record_store.dart';
import 'package:project2/local_sync/local_record_sync_gateway.dart';
import 'package:project2/main.dart';

void main() {
  testWidgets('pending visit retries after the app resumes', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = _MemoryRecordStore([_storedPendingVisit()]);
    final gateway = _RecoveringGateway();
    await tester.pumpWidget(MyApp(syncGateway: gateway, recordStore: store));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(gateway.attempts, 1);
    expect(store.records.single['syncState'], 'pending');

    gateway.isReachable = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(gateway.attempts, 2);
    expect(store.records.single['syncState'], 'synced');
    expect(gateway.sentIds, ['LOCAL-1', 'LOCAL-1']);
    expect(gateway.idempotencyKeys.toSet(), {'upload_LOCAL-1'});
  });

  testWidgets('server conflict stays local and needs manual review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = _MemoryRecordStore([_storedPendingVisit()]);
    final gateway = _ConflictingGateway();
    await tester.pumpWidget(MyApp(syncGateway: gateway, recordStore: store));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(gateway.attempts, 1);
    expect(store.records.single['id'], 'LOCAL-1');
    expect(store.records.single['syncState'], 'failed');
    expect(store.records.single['syncConflict'], isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(gateway.attempts, 1);
  });

  testWidgets('collector provisioning locks phone to collector number offline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = _MemoryRecordStore([]);
    final gateway = _RecoveringGateway();
    await tester.pumpWidget(MyApp(syncGateway: gateway, recordStore: store));
    await tester.pumpAndSettle();

    // First sign in provisions phone to Collector 1
    await tester.enterText(find.byType(TextFormField).first, '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Hello, Collector 1'), findsOneWidget);

    // Sign out
    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    // Attempt to switch to Collector 2 offline
    await tester.enterText(find.byType(TextFormField).first, '2');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    // Rejected because locked to Collector 1
    expect(find.textContaining('locked to Collector 1'), findsOneWidget);
    expect(find.text('Hello, Collector 2'), findsNothing);

    // Sign in as Collector 1 succeeds
    await tester.enterText(find.byType(TextFormField).first, '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Hello, Collector 1'), findsOneWidget);
  });

  testWidgets('201st participant created by one collector (C01-000201) without any 200 limit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Seed with 200th participant for collector 1
    final store = _MemoryRecordStore([
      {
        'id': 'LOCAL-200',
        'participant': {
          'studyId': 'C01-000200',
          'name': 'Participant 200',
          'indianPhone': '+919000000200',
        },
        'visitNumber': 1,
        'collectorId': 'C001',
        'submittedAt': '2026-09-13T00:00:00.000Z',
        'syncState': 'synced',
        'idempotencyKey': 'upload_LOCAL-200',
      },
    ]);
    final gateway = _RecoveringGateway();
    await tester.pumpWidget(MyApp(syncGateway: gateway, recordStore: store));
    await tester.pumpAndSettle();

    // Sign in as collector 1
    await tester.enterText(find.byType(TextFormField).first, '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Hello, Collector 1'), findsOneWidget);

    // Start entry for 201st participant
    await tester.tap(find.widgetWithText(FloatingActionButton, 'New participant'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Participant 201');
    await tester.enterText(find.byType(TextFormField).at(1), '9000000201');
    await tester.tap(find.widgetWithText(FilledButton, 'Find participant'));
    await tester.pumpAndSettle();

    // Verify collector 1's allocated ID is C01-000201 (no 200 limit)
    expect(find.text('C01-000201'), findsOneWidget);
    expect(find.text('First visit'), findsOneWidget);
  });

  testWidgets('multiple collectors generating IDs offline without collisions (C01-000001 vs C02-000001)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Collector 1 generates first participant
    final store1 = _MemoryRecordStore([]);
    final gateway1 = _RecoveringGateway();
    await tester.pumpWidget(MyApp(key: const ValueKey('phone1'), syncGateway: gateway1, recordStore: store1));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, 'New participant'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Collector 1 Participant');
    await tester.enterText(find.byType(TextFormField).at(1), '9111111111');
    await tester.tap(find.widgetWithText(FilledButton, 'Find participant'));
    await tester.pumpAndSettle();

    expect(find.text('C01-000001'), findsOneWidget);
    expect(find.text('First visit'), findsOneWidget);

    // Collector 2 on another phone generates their first participant
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    final store2 = _MemoryRecordStore([]);
    final gateway2 = _RecoveringGateway();
    await tester.pumpWidget(MyApp(key: const ValueKey('phone2'), syncGateway: gateway2, recordStore: store2));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '2');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, 'New participant'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Collector 2 Participant');
    await tester.enterText(find.byType(TextFormField).at(1), '9222222222');
    await tester.tap(find.widgetWithText(FilledButton, 'Find participant'));
    await tester.pumpAndSettle();

    expect(find.text('C02-000001'), findsOneWidget);
    expect(find.text('First visit'), findsOneWidget);
  });

  testWidgets('online lookup finding existing participant from another collector', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = _MemoryRecordStore([]);
    final gateway = _OnlineLookupGateway(
      lookupHandler: (phone) async {
        if (phone == '+919876543210') {
          return const ParticipantLookupResult.found(
            studyId: 'C01-000042',
            name: 'Original Enrolled Name',
            nextVisitNumber: 3,
          );
        }
        return const ParticipantLookupResult.notFound();
      },
    );

    await tester.pumpWidget(MyApp(syncGateway: gateway, recordStore: store));
    await tester.pumpAndSettle();

    // Sign in as Collector 2
    await tester.enterText(find.byType(TextFormField).first, '2');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    // Start entry with the participant's phone number
    await tester.tap(find.widgetWithText(FloatingActionButton, 'New participant'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Different Name Entered');
    await tester.enterText(find.byType(TextFormField).at(1), '9876543210');
    await tester.tap(find.widgetWithText(FilledButton, 'Find participant'));
    await tester.pumpAndSettle();

    expect(find.text('Choose participant'), findsOneWidget);
    await tester.tap(find.text('Original Enrolled Name · C01-000042'));
    await tester.pumpAndSettle();

    // Confirmation screen uses canonical Study ID, canonical name, and next visit number from online lookup
    expect(find.text('C01-000042'), findsOneWidget);
    expect(find.text('Original Enrolled Name'), findsOneWidget);
    expect(find.text('Visit 3'), findsOneWidget);
  });

  testWidgets('shared phone on this device requires explicit Study ID choice',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = _storedPendingVisit();
    final second = _storedPendingVisit();
    second['id'] = 'LOCAL-2';
    second['participant'] = {
      'studyId': 'C01-000002',
      'name': 'Second Household Member',
      'indianPhone': '+919000000001',
    };
    second['visitNumber'] = 3;
    final store = _MemoryRecordStore([first, second]);
    await tester.pumpWidget(MyApp(
      syncGateway: _RecoveringGateway(), recordStore: store,
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FloatingActionButton, 'New participant'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Second Household Member');
    await tester.enterText(find.byType(TextFormField).at(1), '9000000001');
    await tester.tap(find.widgetWithText(FilledButton, 'Find participant'));
    await tester.pumpAndSettle();
    expect(find.text('Choose participant'), findsOneWidget);
    expect(find.text('Second Household Member · C01-000002'), findsOneWidget);
    await tester.tap(find.text('Second Household Member · C01-000002'));
    await tester.pumpAndSettle();
    expect(find.text('C01-000002'), findsOneWidget);
    expect(find.text('Visit 4'), findsOneWidget);
  });

  testWidgets('ambiguous server lookup requires explicit Study ID choice',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _OnlineLookupGateway(lookupHandler: (_) async =>
      const ParticipantLookupResult.ambiguous([
        ParticipantLookupCandidate(studyId: 'C01-000001', name: 'Asha', nextVisitNumber: 2),
        ParticipantLookupCandidate(studyId: 'C02-000001', name: 'Ravi', nextVisitNumber: 3),
      ]));
    await tester.pumpWidget(MyApp(
      syncGateway: gateway, recordStore: _MemoryRecordStore([]),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FloatingActionButton, 'New participant'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Ravi');
    await tester.enterText(find.byType(TextFormField).at(1), '9000000001');
    await tester.tap(find.widgetWithText(FilledButton, 'Find participant'));
    await tester.pumpAndSettle();
    expect(find.text('Choose participant'), findsOneWidget);
    await tester.tap(find.text('Ravi · C02-000001'));
    await tester.pumpAndSettle();
    expect(find.text('C02-000001'), findsOneWidget);
    expect(find.text('Visit 3'), findsOneWidget);
  });

  testWidgets('local match does not hide a different server Study ID',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _MemoryRecordStore([_storedPendingVisit()]);
    final gateway = _OnlineLookupGateway(lookupHandler: (_) async =>
      const ParticipantLookupResult.found(
        studyId: 'C02-000001', name: 'Ravi', nextVisitNumber: 2,
      ));
    await tester.pumpWidget(MyApp(syncGateway: gateway, recordStore: store));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FloatingActionButton, 'New participant'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Test Participant');
    await tester.enterText(find.byType(TextFormField).at(1), '9000000001');
    await tester.tap(find.widgetWithText(FilledButton, 'Find participant'));
    await tester.pumpAndSettle();
    expect(find.text('Choose participant'), findsOneWidget);
    expect(find.text('Test Participant · P001'), findsOneWidget);
    expect(find.text('Ravi · C02-000001'), findsOneWidget);
  });

  testWidgets('offline verified study card entry with validation rejecting malformed ID and invalid visit number', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = _MemoryRecordStore([]);
    final gateway = _RecoveringGateway(); // offline / not found
    await tester.pumpWidget(MyApp(syncGateway: gateway, recordStore: store));
    await tester.pumpAndSettle();

    // Sign in as collector 1
    await tester.enterText(find.byType(TextFormField).first, '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, 'New participant'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Card Participant');
    await tester.enterText(find.byType(TextFormField).at(1), '9123456789');
    await tester.tap(find.widgetWithText(FilledButton, 'Find participant'));
    await tester.pumpAndSettle();

    // Default proposed ID is C01-000001, First visit
    expect(find.text('C01-000001'), findsOneWidget);
    expect(find.text('First visit'), findsOneWidget);

    // Tap specify existing Study ID dialog
    await tester.tap(find.text('Specify existing Study ID (from card/logbook)'));
    await tester.pumpAndSettle();

    // Case 1: Malformed Study ID
    await tester.enterText(find.widgetWithText(TextFormField, 'e.g. P001'), 'INVALID-ID');
    await tester.enterText(find.widgetWithText(TextFormField, '2'), '2');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm Study ID'));
    await tester.pumpAndSettle();

    // Dialog remains open with error
    expect(find.text('Specify Study ID from card/logbook'), findsOneWidget);
    expect(find.textContaining('Invalid Study ID'), findsOneWidget);

    // Case 2: Invalid visit number (0, 1, negative, decimal)
    await tester.enterText(find.widgetWithText(TextFormField, 'e.g. P001'), 'C02-000005');
    await tester.enterText(find.widgetWithText(TextFormField, '2'), '1'); // visit < 2
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm Study ID'));
    await tester.pumpAndSettle();

    expect(find.text('Specify Study ID from card/logbook'), findsOneWidget);
    expect(find.textContaining('Visit number must be an integer of 2 or greater'), findsOneWidget);

    // Decimal visit number
    await tester.enterText(find.widgetWithText(TextFormField, '2'), '2.5');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm Study ID'));
    await tester.pumpAndSettle();

    expect(find.text('Specify Study ID from card/logbook'), findsOneWidget);
    expect(find.textContaining('Visit number must be an integer of 2 or greater'), findsOneWidget);

    // Case 3: Valid Study ID (C02-000005) and valid visit number (2)
    await tester.enterText(find.widgetWithText(TextFormField, '2'), '2');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm Study ID'));
    await tester.pumpAndSettle();

    // Dialog closed, confirmation screen updated
    expect(find.text('Specify Study ID from card/logbook'), findsNothing);
    expect(find.text('C02-000005'), findsOneWidget);
    expect(find.text('Visit 2'), findsOneWidget);

    // Also verify legacy format (e.g. P005) is accepted
    await tester.tap(find.text('Specify existing Study ID (from card/logbook)'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'e.g. P001'), 'P005');
    await tester.enterText(find.widgetWithText(TextFormField, '2'), '3');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm Study ID'));
    await tester.pumpAndSettle();

    expect(find.text('P005'), findsOneWidget);
    expect(find.text('Visit 3'), findsOneWidget);
  });

  testWidgets('conflicted records store conflictId and message, are badged, kept local, not auto-retried, and manual retry after review works', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = _MemoryRecordStore([_storedPendingVisit()]);
    final gateway = _ConfigurableGateway();
    gateway.shouldConflict = true;

    await tester.pumpWidget(MyApp(syncGateway: gateway, recordStore: store));
    await tester.pumpAndSettle();

    // Sign in with collector 1
    await tester.enterText(find.byType(TextFormField).first, '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    // Record encounters 409 conflict
    expect(gateway.attempts, 1);
    expect(store.records.single['id'], 'LOCAL-1');
    expect(store.records.single['syncState'], 'failed');
    expect(store.records.single['syncConflict'], isTrue);
    expect(store.records.single['conflictId'], 'CONF-409-TEST');
    expect(store.records.single['conflictMessage'], 'Server detected participant conflict');

    // App resumes -> verify conflict record is NOT auto-retried
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(gateway.attempts, 1);

    // Open submissions list
    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();

    // Conflicted submission should show "Sync Conflict - Review Required" badge in submissions list
    expect(find.text('Sync Conflict - Review Required'), findsOneWidget);

    // Tap submission to view submission detail screen
    await tester.tap(find.text('Test Participant'));
    await tester.pumpAndSettle();

    // Submission detail screen shows badge, conflict warning, explanation, and action buttons
    expect(find.text('Sync Conflict - Review Required'), findsWidgets);
    expect(find.textContaining('HTTP 409'), findsOneWidget);
    expect(find.textContaining('CONF-409-TEST'), findsWidgets);
    expect(find.text('Review Conflict'), findsOneWidget);
    expect(find.text('Retry Upload'), findsOneWidget);

    // Conflict resolved on server: configure gateway to succeed
    gateway.shouldConflict = false;

    // Review conflict dialog
    await tester.tap(find.text('Review Conflict'));
    await tester.pumpAndSettle();
    expect(find.text('Conflict Review'), findsOneWidget);
    expect(find.textContaining('LOCAL-1'), findsWidgets);
    expect(find.textContaining('CONF-409-TEST'), findsWidgets);

    // Manually retry from review dialog
    await tester.tap(find.widgetWithText(FilledButton, 'Retry Upload').last);
    await tester.pumpAndSettle();

    // Verify manual retry succeeded
    expect(gateway.attempts, 2);
    expect(store.records.single['syncState'], 'synced');
    expect(store.records.single['syncConflict'], isFalse);
    expect(find.text('Synced'), findsOneWidget);
    expect(find.text('Sync Conflict - Review Required'), findsNothing);
  });
}

Map<String, Object?> _storedPendingVisit() => {
  'id': 'LOCAL-1',
  'participant': {
    'studyId': 'P001',
    'name': 'Test Participant',
    'indianPhone': '+919000000001',
  },
  'visitNumber': 1,
  'collectorId': 'C001',
  'submittedAt': '2026-09-13T00:00:00.000Z',
  'syncState': 'pending',
  'idempotencyKey': 'upload_LOCAL-1',
};

class _MemoryRecordStore implements LocalRecordStore {
  _MemoryRecordStore(this.records);

  List<Map<String, Object?>> records;

  @override
  Future<List<Map<String, Object?>>> readAll() async => records;

  @override
  Future<void> writeAll(List<Map<String, Object?>> newRecords) async {
    records = newRecords;
  }
}

class _RecoveringGateway implements LocalRecordSyncGateway {
  bool isReachable = false;
  int attempts = 0;
  final List<String> sentIds = [];
  final List<String> idempotencyKeys = [];

  @override
  Future<LocalRecordSyncResult> sendRecord(Map<String, Object?> record) async {
    attempts++;
    sentIds.add(record['id']! as String);
    idempotencyKeys.add(record['idempotencyKey']! as String);
    return isReachable
        ? LocalRecordSyncResult.synced
        : LocalRecordSyncResult.pending;
  }

  @override
  Future<ParticipantLookupResult> lookupParticipant(String phone) async {
    return isReachable
        ? const ParticipantLookupResult.notFound()
        : const ParticipantLookupResult.offline();
  }
}

class _ConflictingGateway implements LocalRecordSyncGateway {
  int attempts = 0;

  @override
  Future<LocalRecordSyncResult> sendRecord(Map<String, Object?> record) async {
    attempts++;
    // This flag is local-only and must not be sent to the server.
    expect(record.containsKey('syncConflict'), isFalse);
    return LocalRecordSyncResult.conflict;
  }

  @override
  Future<ParticipantLookupResult> lookupParticipant(String phone) async {
    return const ParticipantLookupResult.offline();
  }
}

class _ConfigurableGateway implements LocalRecordSyncGateway {
  bool shouldConflict = true;
  int attempts = 0;
  final List<String> sentIds = [];
  String? conflictId = 'CONF-409-TEST';
  String? conflictMessage = 'Server detected participant conflict';

  @override
  Future<LocalRecordSyncResult> sendRecord(Map<String, Object?> record) async {
    attempts++;
    // This flag is local-only and must not be sent to the server.
    expect(record.containsKey('syncConflict'), isFalse);
    sentIds.add(record['id']! as String);
    if (shouldConflict) {
      return LocalRecordSyncResult.conflict;
    }
    return LocalRecordSyncResult.synced;
  }

  Future<SyncResponse> sendRecordDetailed(Map<String, Object?> record) async {
    attempts++;
    expect(record.containsKey('syncConflict'), isFalse);
    sentIds.add(record['id']! as String);
    if (shouldConflict) {
      return SyncResponse.conflict(
        conflictId: conflictId,
        message: conflictMessage,
      );
    }
    return const SyncResponse.synced();
  }

  @override
  Future<ParticipantLookupResult> lookupParticipant(String phone) async {
    return const ParticipantLookupResult.notFound();
  }
}

class _OnlineLookupGateway implements LocalRecordSyncGateway {
  _OnlineLookupGateway({required this.lookupHandler});

  final Future<ParticipantLookupResult> Function(String phone) lookupHandler;
  int attempts = 0;

  @override
  Future<LocalRecordSyncResult> sendRecord(Map<String, Object?> record) async {
    attempts++;
    return LocalRecordSyncResult.synced;
  }

  @override
  Future<ParticipantLookupResult> lookupParticipant(String phone) =>
      lookupHandler(phone);
}
