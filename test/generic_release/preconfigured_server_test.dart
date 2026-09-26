import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project2/collector_auth/collector_qr_payload.dart';
import 'package:project2/collector_auth/collector_qr_scanner_contract.dart';
import 'package:project2/presentation/sign_in_screen.dart';

void main() {
  testWidgets('public setup scans QR and uses its configured server', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const configuredServer = 'https://api.nutrition.achantalabs.com';
    final scanner = _FakeCollectorQrScanner(
      QrScannerSuccess(
        CollectorQrPayload(
          version: 1,
          collectorNumber: 3,
          collectorKey: 'synthetic-key-only-123456',
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
            initialServerUrl: configuredServer,
            scanner: scanner,
            onSignIn: (value) => submitted = value,
          ),
        ),
      ),
    );

    expect(find.text('Server address'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('Scan sign-in QR'));
    await tester.pumpAndSettle();

    expect(scanner.expectedServerUrl, configuredServer);
    expect(scanner.requireHttps, isTrue);
    expect(submitted?.collectorCode, 'C003');
    expect(submitted?.serverUrl, configuredServer);
  });
}

class _FakeCollectorQrScanner implements CollectorQrScannerContract {
  _FakeCollectorQrScanner(this.result);

  final QrScannerResult result;
  String? expectedServerUrl;
  bool? requireHttps;

  @override
  Future<QrScannerResult> scanCode({
    String? expectedServerUrl,
    bool requireHttps = true,
  }) async {
    this.expectedServerUrl = expectedServerUrl;
    this.requireHttps = requireHttps;
    return result;
  }
}
