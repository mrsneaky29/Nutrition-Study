import 'package:flutter_test/flutter_test.dart';
import 'package:project2/domain/ncd_questionnaire.dart';

void main() {
  const questionnaire = NcdQuestionnaire(
    studySite: 'community_clinic', age: 34, sex: 'female',
    education: 'secondary', employment: 'employed',
    fruitFrequency: 'daily', vegetableFrequency: 'daily',
    sugaryDrinkFrequency: 'one_to_two_days',
    processedFoodFrequency: 'never', activeDaysPerWeek: 5,
    activeMinutesPerDay: 30, sleepHours: 7.5, heightCm: 160,
    weightKg: 64, waistCm: 82, bpOneSystolic: 120,
    bpOneDiastolic: 80, bpTwoSystolic: 124, bpTwoDiastolic: 78,
  );

  test('calculates values from raw measurements and round-trips coded values', () {
    expect(questionnaire.weeklyActiveMinutes, 150);
    expect(questionnaire.bmi, closeTo(25, 0.001));
    expect(questionnaire.averageSystolic, 122);
    expect(questionnaire.averageDiastolic, 79);
    final restored = NcdQuestionnaire.fromMap(questionnaire.toMap());
    expect(restored?.studySite, 'community_clinic');
    expect(restored?.tobaccoUse, isNull);
    expect(restored?.toCsvRow()['ncd_weekly_active_minutes'], '150');
  });

  test('does not treat incomplete legacy values as a questionnaire', () {
    expect(NcdQuestionnaire.fromMap({'studySite': 'community_clinic'}), isNull);
  });
}
