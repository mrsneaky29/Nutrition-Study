import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:project2/local_sync/local_record_sync_gateway.dart';
import 'package:project2/local_storage/local_record_store.dart';
import 'package:project2/main.dart';

void main() {
  testWidgets('collector reaches the compact NCD questionnaire', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MyApp(syncGateway: _SyncGateway(), recordStore: _MemoryRecordStore()),
    );
    await tester.pumpAndSettle();

    final signIn = find.byType(TextFormField);
    await tester.enterText(signIn.first, '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New participant'));
    await tester.pumpAndSettle();

    final participant = find.byType(TextFormField);
    await tester.enterText(participant.at(0), 'Test Participant');
    await tester.enterText(participant.at(1), '9000000001');
    await tester.tap(find.widgetWithText(FilledButton, 'Find participant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm and continue'));
    await tester.pumpAndSettle();

    expect(find.text('NCD risk questionnaire'), findsOneWidget);
    expect(find.text('Study and profile'), findsOneWidget);
    expect(find.text('Physical measurements'), findsNothing);
  });
}

class _SyncGateway implements LocalRecordSyncGateway {
  @override
  Future<LocalRecordSyncResult> sendRecord(Map<String, Object?> value) async =>
      LocalRecordSyncResult.synced;

  @override
  Future<ParticipantLookupResult> lookupParticipant(String phone) async =>
      const ParticipantLookupResult.notFound();
}

class _MemoryRecordStore implements LocalRecordStore {
  @override
  Future<List<Map<String, Object?>>> readAll() async => const [];

  @override
  Future<void> writeAll(List<Map<String, Object?>> records) async {}
}
