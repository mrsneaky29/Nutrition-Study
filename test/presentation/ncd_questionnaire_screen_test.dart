import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project2/presentation/ncd_questionnaire_screen.dart';

void main() {
  testWidgets('rejects a blood pressure pair when systolic is lower', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NcdQuestionnaireScreen(
          initialDraft: _validMeasurementDraft(bp1s: '80', bp1d: '120'),
        ),
      ),
    );

    await _tapReviewQuestionnaire(tester);

    expect(
      find.text('Systolic must be greater than diastolic.'),
      findsOneWidget,
    );
  });

  testWidgets('rejects a blood pressure pair when systolic equals diastolic', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NcdQuestionnaireScreen(
          initialDraft: _validMeasurementDraft(bp2s: '80', bp2d: '80'),
        ),
      ),
    );

    await _tapReviewQuestionnaire(tester);

    expect(
      find.text('Systolic must be greater than diastolic.'),
      findsOneWidget,
    );
  });

  testWidgets('rejects non-finite decimal measurement input', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NcdQuestionnaireScreen(
          initialDraft: _validMeasurementDraft(height: 'NaN'),
        ),
      ),
    );

    await _tapReviewQuestionnaire(tester);

    expect(find.text('Enter a value from 50 to 250.'), findsOneWidget);
  });

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

Future<void> _tapReviewQuestionnaire(WidgetTester tester) async {
  final button = find.text('Review questionnaire');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Map<String, Object?> _validMeasurementDraft({
  String height = '170',
  String bp1s = '120',
  String bp1d = '80',
  String bp2s = '124',
  String bp2d = '78',
}) => {
  'measurements': true,
  'height': height,
  'weight': '70',
  'waist': '80',
  'bp1s': bp1s,
  'bp1d': bp1d,
  'bp2s': bp2s,
  'bp2d': bp2d,
};
