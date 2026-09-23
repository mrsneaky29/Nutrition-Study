import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project2/presentation/sign_in_screen.dart';

void main() {
  testWidgets(
    'shared APK accepts collector number and runtime server details',
    (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      CollectorAccessInput? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SignInScreen(
              showLocalSetup: true,
              onSignIn: (value) => submitted = value,
            ),
          ),
        ),
      );
      expect(
        find.textContaining('sync any pending visits on the old phone'),
        findsOneWidget,
      );
      expect(find.text('Home server address'), findsOneWidget);
      expect(find.text('Collector access key'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), '7');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'http://192.168.1.5:8787',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'synthetic-collector-key',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pump();

      expect(submitted?.collectorCode, 'C007');
      expect(submitted?.serverUrl, 'http://192.168.1.5:8787');
      expect(submitted?.accessKey, 'synthetic-collector-key');
    },
  );
}
