import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project2/domain/ncd_questionnaire.dart';
import 'package:project2/presentation/review_screen.dart';
import 'package:project2/presentation/view_models.dart';

void main() {
  testWidgets('review displays questionnaire answers and keeps actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var editTapped = false;
    var submitTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          participant: const ParticipantDraft(
            studyId: 'STUDY-123',
            name: 'Sample Person',
            phone: '+919000000001',
          ),
          visitNumber: 2,
          questionnaire: _questionnaire,
          optionalNote: 'Follow up next month',
          onEditParticipant: () => editTapped = true,
          onSubmit: () => submitTapped = true,
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review submission'), findsOneWidget);
    expect(find.text('Community outreach'), findsOneWidget);
    expect(find.text('34 years'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('Secondary'), findsOneWidget);
    expect(find.text('Self-employed'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pump();
    expect(editTapped, isTrue);

    await _scrollTo(tester, 'Tobacco and alcohol');
    expect(find.text('Current user'), findsOneWidget);
    expect(find.text('Smokeless'), findsOneWidget);
    expect(find.text('Less than daily'), findsOneWidget);
    expect(find.text('Yes'), findsWidgets);
    expect(find.text('1–3 days/week'), findsOneWidget);

    await _scrollTo(tester, 'Diet, activity and sleep');
    expect(find.text('1–2 days'), findsOneWidget);
    expect(find.text('Every day'), findsWidgets);
    expect(find.text('3 days'), findsOneWidget);
    expect(find.text('30 minutes'), findsOneWidget);
    expect(find.text('90 minutes'), findsOneWidget);
    expect(find.text('7.5 hours'), findsOneWidget);

    await _scrollTo(tester, 'Known diagnoses');
    expect(find.text('Don’t know'), findsOneWidget);
    expect(find.text('No'), findsWidgets);
    expect(find.text('Not answered'), findsOneWidget);

    await _scrollTo(tester, 'Physical measurements');
    expect(find.text('Unable to measure'), findsOneWidget);
    expect(find.text('Declined'), findsOneWidget);
    expect(find.text('64 kg'), findsOneWidget);
    expect(find.text('120 / 80 mmHg'), findsOneWidget);
    expect(find.text('122 / 79 mmHg'), findsOneWidget);

    await _scrollTo(tester, 'Optional Step 2');
    expect(find.text('Follow up next month'), findsOneWidget);

    await tester.ensureVisible(find.text('Review and submit'));
    await tester.tap(find.text('Review and submit'));
    await tester.pump();
    expect(submitTapped, isTrue);
  });

  testWidgets('unanswered and conditional questionnaire values are explicit', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReviewScreen(
          participant: ParticipantDraft(
            studyId: 'STUDY-123',
            name: 'Sample Person',
            phone: '+919000000001',
          ),
          visitNumber: 1,
          questionnaire: _mostlyUnansweredQuestionnaire,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollTo(tester, 'Tobacco and alcohol');
    expect(find.text('Not applicable'), findsWidgets);
    await _scrollTo(tester, 'Known diagnoses');
    expect(find.text('Not answered'), findsWidgets);
  });
}

Future<void> _scrollTo(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.scrollUntilVisible(
    target,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  expect(target, findsOneWidget);
}

const _questionnaire = NcdQuestionnaire(
  studySite: 'community_outreach',
  age: 34,
  sex: 'female',
  education: 'secondary',
  employment: 'self_employed',
  tobaccoUse: 'current',
  tobaccoType: 'smokeless',
  tobaccoFrequency: 'less_than_daily',
  alcoholPast30Days: 'yes',
  alcoholFrequency: 'one_to_three_weekly',
  fruitFrequency: 'one_to_two_days',
  vegetableFrequency: 'daily',
  sugaryDrinkFrequency: 'never',
  processedFoodFrequency: 'three_to_four_days',
  activeDaysPerWeek: 3,
  activeMinutesPerDay: 30,
  sleepHours: 7.5,
  hypertensionDiagnosis: 'yes',
  diabetesDiagnosis: 'no',
  highCholesterolDiagnosis: 'dont_know',
  cardiovascularDiagnosis: null,
  heightCm: null,
  heightMissingReason: 'unable',
  weightKg: 64,
  waistCm: null,
  waistMissingReason: 'declined',
  bpOneSystolic: 120,
  bpOneDiastolic: 80,
  bpTwoSystolic: 124,
  bpTwoDiastolic: 78,
);

const _mostlyUnansweredQuestionnaire = NcdQuestionnaire(
  studySite: 'community_clinic',
  age: 40,
  sex: 'other',
  education: 'primary',
  employment: 'employed',
  fruitFrequency: 'never',
  vegetableFrequency: 'never',
  sugaryDrinkFrequency: 'never',
  processedFoodFrequency: 'never',
  activeDaysPerWeek: 0,
  activeMinutesPerDay: 0,
  sleepHours: 8,
  heightCm: null,
  heightMissingReason: 'declined',
  weightKg: null,
  weightMissingReason: 'declined',
  waistCm: null,
  waistMissingReason: 'declined',
  bpOneSystolic: null,
  bpOneDiastolic: null,
  bpOneMissingReason: 'declined',
  bpTwoSystolic: null,
  bpTwoDiastolic: null,
  bpTwoMissingReason: 'declined',
  tobaccoUse: 'never',
  tobaccoType: null,
  tobaccoFrequency: null,
  alcoholPast30Days: 'no',
  alcoholFrequency: null,
  hypertensionDiagnosis: null,
  diabetesDiagnosis: null,
  highCholesterolDiagnosis: null,
  cardiovascularDiagnosis: null,
);
