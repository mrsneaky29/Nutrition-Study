import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project2/presentation/ncd_questionnaire_screen.dart';

void main() {
  testWidgets('restored measurement status changes update the draft', (
    tester,
  ) async {
    Map<String, Object?>? savedDraft;
    await tester.pumpWidget(
      MaterialApp(
        home: NcdQuestionnaireScreen(
          initialDraft: const {
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
            'height': '',
            'weight': '64',
            'waist': '82',
            'bp1s': '120',
            'bp1d': '80',
            'bp2s': '124',
            'bp2d': '78',
            'heightMissingReason': 'unable',
          },
          onDraftChanged: (value) => savedDraft = value,
        ),
      ),
    );

    expect(find.text('Physical measurements'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Height (cm)'), findsNothing);
    expect(find.text('Unable to measure'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Declined').last);
    await tester.pumpAndSettle();
    expect(savedDraft?['heightMissingReason'], 'declined');
  });
}
