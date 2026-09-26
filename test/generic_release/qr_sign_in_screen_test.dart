import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project2/collector_auth/collector_qr_payload.dart';
import 'package:project2/collector_auth/collector_qr_scanner_contract.dart';
import 'package:project2/presentation/sign_in_screen.dart';

void main() {
  const serverUrl = 'https://api.nutrition.achantalabs.com';

  testWidgets('production setup is QR only and submits validated credentials', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final scanner = FakeCollectorQrScanner(
      QrScannerSuccess(
        CollectorQrPayload(
          version: 1,
          collectorNumber: 3,
          collectorKey: 'synthetic-access-key-123',
        ),
      ),
    );
    CollectorAccessInput? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignInScreen(
            showLocalSetup: true,
            requireHttps: true,
            initialServerUrl: serverUrl,
            scanner: scanner,
            onSignIn: (value) => submitted = value,
          ),
        ),
      ),
    );

    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Continue'), findsNothing);
    await tester.tap(find.text('Scan sign-in QR'));
    await tester.pumpAndSettle();

    expect(scanner.calls, 1);
    expect(scanner.expectedServerUrl, serverUrl);
    expect(scanner.requireHttps, isTrue);
    expect(submitted?.collectorCode, 'C003');
    expect(submitted?.serverUrl, serverUrl);
    expect(submitted?.accessKey, 'synthetic-access-key-123');
    expect(find.text('synthetic-access-key-123'), findsNothing);
  });

  testWidgets('invalid configured server is rejected before opening camera', (
    tester,
  ) async {
    final scanner = FakeCollectorQrScanner(const QrScannerCancelled());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignInScreen(
            showLocalSetup: true,
            requireHttps: true,
            initialServerUrl: 'http://untrusted.example.com',
            scanner: scanner,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Scan sign-in QR'));
    await tester.pump();

    expect(scanner.calls, 0);
    expect(find.textContaining('not configured'), findsOneWidget);
  });

  testWidgets('QR cannot override the configured server', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final scanner = FakeCollectorQrScanner(
      QrScannerSuccess(
        CollectorQrPayload(
          version: 1,
          collectorNumber: 3,
          collectorKey: 'synthetic-access-key-123',
          serverUrl: 'https://attacker.example.com',
        ),
      ),
    );
    CollectorAccessInput? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignInScreen(
            showLocalSetup: true,
            requireHttps: true,
            initialServerUrl: serverUrl,
            scanner: scanner,
            onSignIn: (value) => submitted = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Scan sign-in QR'));
    await tester.pumpAndSettle();

    expect(submitted, isNull);
    expect(find.textContaining('attacker.example.com'), findsNothing);
    expect(find.byKey(const Key('qr-sign-in-message')), findsOneWidget);
  });

  final outcomes = <String, QrScannerResult>{
    'cancelled': const QrScannerCancelled(),
    'permission denied': const QrScannerPermissionDenied(
      message: 'secret or platform detail must never appear',
    ),
    'invalid': const QrScannerInvalid(reason: 'private raw payload detail'),
    'camera unavailable': const QrScannerError(error: 'private camera detail'),
  };
  for (final entry in outcomes.entries) {
    testWidgets('shows safe ${entry.key} message', (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SignInScreen(
              showLocalSetup: true,
              requireHttps: true,
              initialServerUrl: serverUrl,
              scanner: FakeCollectorQrScanner(entry.value),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Scan sign-in QR'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('qr-sign-in-message')), findsOneWidget);
      expect(find.textContaining('secret or platform detail'), findsNothing);
      expect(find.textContaining('private raw payload detail'), findsNothing);
      expect(find.textContaining('private camera detail'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Continue'), findsNothing);
    });
  }
}

class FakeCollectorQrScanner implements CollectorQrScannerContract {
  FakeCollectorQrScanner(this.result);

  final QrScannerResult result;
  int calls = 0;
  String? expectedServerUrl;
  bool? requireHttps;

  @override
  Future<QrScannerResult> scanCode({
    String? expectedServerUrl,
    bool requireHttps = true,
  }) async {
    calls++;
    this.expectedServerUrl = expectedServerUrl;
    this.requireHttps = requireHttps;
    return result;
  }
}
