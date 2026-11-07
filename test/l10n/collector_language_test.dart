import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project2/l10n/app_localizations.dart';
import 'package:project2/l10n/collector_copy.dart';
import 'package:project2/l10n/collector_language.dart';
import 'package:project2/presentation/ncd_questionnaire_screen.dart';
import 'package:project2/presentation/participant_lookup_screen.dart';
import 'package:project2/presentation/review_screen.dart';
import 'package:project2/presentation/receipt_screen.dart';
import 'package:project2/presentation/sign_in_screen.dart';
import 'package:project2/presentation/presentation_theme.dart';
import 'package:project2/presentation/view_models.dart';
import 'package:project2/local_storage/local_record_store.dart';
import 'package:project2/local_sync/local_record_sync_gateway.dart';
import 'package:project2/main.dart';
import 'package:project2/collector_auth/collector_qr_scanner_contract.dart';

class _LanguageStore implements CollectorLanguageStore {
  _LanguageStore([this.value]);
  String? value;
  bool failRead = false;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('unavailable');
    return value;
  }

  @override
  Future<void> write(String language) async {
    value = language;
  }
}

Widget _host(
  CollectorLanguageController language,
  Widget home, {
  double scale = 1,
}) => CollectorLanguageScope(
  controller: language,
  child: AnimatedBuilder(
    animation: language,
    builder: (context, _) => MaterialApp(
      locale: language.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: PresentationTheme.materialTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(
          key: const Key('telugu-preview'),
          child: Column(
            children: [
              const CollectorLanguageBar(),
              Expanded(child: child!),
            ],
          ),
        ),
      ),
      home: home,
    ),
  ),
);

Future<void> _switch(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_TELUGU_PREVIEWS')) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('telugu-preview')),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/telugu-preview')
      ..createSync(recursive: true);
    File('${directory.path}/$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  setUpAll(() async {
    final loader = FontLoader('NotoSansTelugu')
      ..addFont(rootBundle.load('assets/fonts/NotoSansTelugu.ttf'));
    await loader.load();
    // Optional local visual captures need real Latin/icons rather than Ahem.
    // These are tooling-only fonts, not runtime or distribution dependencies.
    if (const bool.fromEnvironment('CAPTURE_TELUGU_PREVIEWS')) {
      const sdk = String.fromEnvironment('PREVIEW_FLUTTER_SDK');
      for (final entry in {
        'Roboto':
            '$sdk/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts/Roboto/Roboto-Regular.ttf',
        'MaterialIcons':
            '$sdk/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts/MaterialIcons-Regular.otf',
      }.entries) {
        final file = File(entry.value);
        if (file.existsSync()) {
          final font = FontLoader(entry.key)
            ..addFont(
              file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            );
          await font.load();
        }
      }
    }
  });

  test('defaults to English and restores a supported language only', () async {
    for (final initial in [null, 'invalid', 'en', 'te']) {
      final controller = CollectorLanguageController(
        store: _LanguageStore(initial),
      );
      await controller.load();
      expect(controller.locale.languageCode, initial == 'te' ? 'te' : 'en');
      controller.dispose();
    }
  });

  test(
    'preference read failures fall back without blocking collection',
    () async {
      final store = _LanguageStore()..failRead = true;
      final controller = CollectorLanguageController(store: store);
      await controller.load();
      expect(controller.locale.languageCode, 'en');
      await controller.select('te');
      expect(store.value, 'te');
      controller.dispose();
    },
  );

  test(
    'language preference survives credential clearing and restart',
    () async {
      final controller = CollectorLanguageController();
      await controller.select('te');
      await const FlutterSecureStorage().write(
        key: 'local_session_token',
        value: 'synthetic',
      );
      await const FlutterSecureStorage().delete(key: 'local_session_token');
      controller.dispose();
      final restarted = CollectorLanguageController();
      await restarted.load();
      expect(restarted.locale.languageCode, 'te');
      restarted.dispose();
    },
  );

  test('late preference reads cannot override a new selection', () async {
    final store = _DelayedLanguageStore();
    final controller = CollectorLanguageController(store: store);
    final loading = controller.load();
    final saving = controller.select('te');
    store.readResult.complete('en');
    await loading;
    await saving;
    expect(controller.locale.languageCode, 'te');
    expect(store.value, 'te');
    controller.dispose();
  });

  test('rapid language toggles persist the final selection', () async {
    final store = _LanguageStore();
    final controller = CollectorLanguageController(store: store);
    await Future.wait([
      controller.select('te'),
      controller.select('en'),
      controller.select('te'),
    ]);
    expect(store.value, 'te');
    expect(controller.locale.languageCode, 'te');
    controller.dispose();
  });

  test('every translation and interpolated message uses its Telugu bundle', () {
    final en =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map;
    final te =
        jsonDecode(File('lib/l10n/app_te.arb').readAsStringSync()) as Map;
    final localization = lookupAppLocalizations(const Locale('te'));
    final english = lookupAppLocalizations(const Locale('en'));
    for (final entry in en.entries.where(
      (e) => !(e.key as String).startsWith('@'),
    )) {
      final source = (entry.value as String).replaceAll(
        RegExp(r'\{\w+\}'),
        'synthetic',
      );
      final expected = (te[entry.key] as String).replaceAll(
        RegExp(r'\{\w+\}'),
        'synthetic',
      );
      expect(
        translateCollectorCopy(localization, source),
        expected,
        reason: '${entry.key}',
      );
      expect(translateCollectorCopy(english, source), source);
    }
    expect(
      translateCollectorCopy(localization, 'Reading 1 status'),
      'మొదటి కొలత స్థితి',
    );
    expect(
      translateCollectorCopy(localization, 'Visit 2 for Synced is saved.'),
      'Synced కోసం సందర్శన 2 సేవ్ అయింది.',
    );
  });

  testWidgets(
    'switching after validation preserves text and immediately translates errors',
    (tester) async {
      final language = CollectorLanguageController(store: _LanguageStore());
      await tester.pumpWidget(_host(language, const ParticipantLookupScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Synced');
      await tester.tap(find.text('Find participant'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a phone number.'), findsOneWidget);
      await _switch(tester, 'తెలుగు');
      expect(find.text('ఫోన్ నంబర్‌ను నమోదు చేయండి.'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Synced',
      );
      await _switch(tester, 'English');
      expect(find.text('Enter a phone number.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      language.dispose();
    },
  );

  testWidgets(
    'narrow Telugu measurements keep values and schema when toggled',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final language = CollectorLanguageController(store: _LanguageStore());
      Map<String, Object?>? draft;
      dynamic completed;
      await tester.pumpWidget(
        _host(
          language,
          NcdQuestionnaireScreen(
            initialDraft: _measurements,
            onDraftChanged: (value) => draft = value,
            onComplete: (value) => completed = value,
          ),
          scale: 1.4,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '171');
      expect(
        tester.widget<TextField>(find.byType(TextField).first).keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );
      await _switch(tester, 'తెలుగు');
      expect(find.text('శారీరక కొలతలు'), findsOneWidget);
      await _capture(tester, 'measurements');
      expect(draft?['height'], '171');
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('నిరాకరించారు').last);
      await tester.pumpAndSettle();
      expect(draft?['heightMissingReason'], 'declined');
      final submit = find.text('ప్రశ్నావళిని సమీక్షించండి');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(completed?.sex, 'female');
      expect(completed?.version, 4);
      expect(completed?.heightMissingReason, 'declined');
      expect(completed?.waistHipRatio, .8);
      expect(tester.takeException(), isNull);
      language.dispose();
    },
  );

  testWidgets(
    'review translates answers but never participant names or notes',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final language = CollectorLanguageController(store: _LanguageStore());
      await language.select('te');
      await tester.pumpWidget(
        _host(
          language,
          const ReviewScreen(
            participant: ParticipantDraft(
              studyId: 'C01-9999999999999999',
              name: 'Synced',
              phone: '9000000000',
            ),
            visitNumber: 1,
            optionalNote: 'Yes',
          ),
          scale: 1.5,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synced'), findsOneWidget);
      expect(find.text('C01-9999999999999999'), findsOneWidget);
      await _capture(tester, 'review');
      await tester.scrollUntilVisible(
        find.text('Yes'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Yes'), findsOneWidget);
      expect(tester.takeException(), isNull);
      language.dispose();
    },
  );

  testWidgets('production QR-only screen translates sign-in errors', (
    tester,
  ) async {
    final language = CollectorLanguageController(store: _LanguageStore());
    await language.select('te');
    await tester.pumpWidget(
      _host(
        language,
        const SignInScreen(showLocalSetup: true, requireHttps: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('సైన్ ఇన్ QR స్కాన్ చేయండి'));
    await tester.pumpAndSettle();
    expect(
      find.text('సైన్ ఇన్ ఏర్పాటు కాలేదు. మీ నిర్వాహకుడిని సంప్రదించండి.'),
      findsOneWidget,
    );
    await _capture(tester, 'sign-in-error');
    await _switch(tester, 'English');
    expect(
      find.text('Sign-in is not configured. Contact your administrator.'),
      findsOneWidget,
    );
    language.dispose();
  });

  testWidgets('receipt preserves identifiers even when they resemble UI copy', (
    tester,
  ) async {
    final language = CollectorLanguageController(store: _LanguageStore());
    await language.select('te');
    await tester.pumpWidget(
      _host(
        language,
        ReceiptScreen(
          submission: SubmissionSummary(
            id: 'Synced',
            studyId: 'Not calculated',
            participantName: 'Yes',
            visitNumber: 2,
            submittedAt: DateTime(2026),
            syncState: SyncState.synced,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Synced'), findsOneWidget);
    expect(find.text('Not calculated'), findsOneWidget);
    expect(find.text('Yes కోసం సందర్శన 2 సేవ్ అయింది.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    language.dispose();
  });

  for (final result in <QrScannerResult>[
    const QrScannerCancelled(),
    const QrScannerPermissionDenied(message: 'private diagnostic'),
    const QrScannerInvalid(reason: 'private diagnostic'),
    const QrScannerError(error: 'private diagnostic'),
  ]) {
    testWidgets(
      'Telugu QR error ${result.runtimeType} wraps on narrow enlarged screens',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final language = CollectorLanguageController(store: _LanguageStore());
        await language.select('te');
        await tester.pumpWidget(
          _host(
            language,
            SignInScreen(
              showLocalSetup: true,
              requireHttps: true,
              initialServerUrl: 'https://api.nutrition.achantalabs.com',
              scanner: _Scanner(result),
            ),
            scale: 1.5,
          ),
        );
        await tester.pumpAndSettle();
        final scan = find.text('సైన్ ఇన్ QR స్కాన్ చేయండి');
        await tester.ensureVisible(scan);
        await tester.tap(scan);
        await tester.pumpAndSettle();
        final message = tester.widget<CollectorText>(
          find.byKey(const Key('qr-sign-in-message')),
        );
        final localized = translateCollectorCopy(
          lookupAppLocalizations(const Locale('te')),
          message.data,
        );
        expect(localized, isNot(message.data));
        expect(find.textContaining('private diagnostic'), findsNothing);
        expect(tester.takeException(), isNull);
        await _capture(tester, 'qr-${result.runtimeType}');
        language.dispose();
      },
    );
  }

  testWidgets('Telugu collection keeps retry and sign-out semantics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preference = _LanguageStore('te');
    final language = CollectorLanguageController(store: preference);
    final records = _Records();
    final gateway = _Gateway();
    await tester.pumpWidget(
      MyApp(
        languageController: language,
        recordStore: records,
        syncGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '1');
    await tester.tap(find.text('కొనసాగించండి'));
    await tester.pumpAndSettle();
    expect(gateway.attempts, 1);
    expect(records.records.single['syncState'], 'pending');
    gateway.online = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(records.records.single['syncState'], 'synced');
    expect(find.text('సింక్ అయింది'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collector-language-toggle')), findsOneWidget);
    expect(find.text('కొనసాగించండి'), findsOneWidget);
    expect(language.locale.languageCode, 'te');
    expect(tester.takeException(), isNull);
    language.dispose();
  });
}

class _DelayedLanguageStore extends _LanguageStore {
  final readResult = Completer<String?>();
  @override
  Future<String?> read() => readResult.future;
}

class _Scanner implements CollectorQrScannerContract {
  _Scanner(this.result);
  final QrScannerResult result;
  @override
  Future<QrScannerResult> scanCode({
    String? expectedServerUrl,
    bool requireHttps = true,
  }) async => result;
}

const _measurements = <String, Object?>{
  'measurements': true,
  'site': 'community_clinic',
  'age': '34',
  'sex': 'female',
  'education': 'secondary',
  'employment': 'employed',
  'fruit': 'daily',
  'vegetables': 'daily',
  'sugaryDrinks': 'never',
  'processedFood': 'never',
  'activeDays': '3',
  'activeMinutes': '30',
  'sleep': '7',
  'height': '170',
  'weight': '70',
  'waist': '80',
  'hip': '100',
  'bp1s': '120',
  'bp1d': '80',
  'bp2s': '124',
  'bp2d': '78',
};

class _Records implements LocalRecordStore {
  List<Map<String, Object?>> records = [
    {
      'id': 'SYNTHETIC-TE-1',
      'participant': {
        'studyId': 'C01-9999999999999999',
        'name': 'Synced',
        'indianPhone': '9000000000',
      },
      'visitNumber': 1,
      'collectorId': 'C001',
      'submittedAt': '2026-10-04T00:00:00Z',
      'syncState': 'pending',
      'idempotencyKey': 'upload_SYNTHETIC-TE-1',
    },
  ];
  @override
  Future<List<Map<String, Object?>>> readAll() async => records;
  @override
  Future<void> writeAll(List<Map<String, Object?>> value) async {
    records = value;
  }
}

class _Gateway implements LocalRecordSyncGateway {
  bool online = false;
  int attempts = 0;
  @override
  Future<LocalRecordSyncResult> sendRecord(Map<String, Object?> record) async {
    attempts++;
    expect(record['id'], 'SYNTHETIC-TE-1');
    expect(record['idempotencyKey'], 'upload_SYNTHETIC-TE-1');
    expect(record['participant'], {
      'studyId': 'C01-9999999999999999',
      'name': 'Synced',
      'indianPhone': '9000000000',
    });
    return online
        ? LocalRecordSyncResult.synced
        : LocalRecordSyncResult.pending;
  }

  @override
  Future<ParticipantLookupResult> lookupParticipant(String phone) async =>
      const ParticipantLookupResult.offline();
}
