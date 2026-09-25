import 'package:flutter_test/flutter_test.dart';
import 'package:project2/domain/ncd_questionnaire.dart';

void main() {
  const questionnaire = NcdQuestionnaire(
    studySite: 'community_clinic',
    age: 34,
    sex: 'female',
    education: 'secondary',
    employment: 'employed',
    fruitFrequency: 'daily',
    vegetableFrequency: 'daily',
    sugaryDrinkFrequency: 'one_to_two_days',
    processedFoodFrequency: 'never',
    activeDaysPerWeek: 5,
    activeMinutesPerDay: 30,
    sleepHours: 7.5,
    heightCm: 160,
    weightKg: 64,
    waistCm: 82,
    bpOneSystolic: 120,
    bpOneDiastolic: 80,
    bpTwoSystolic: 124,
    bpTwoDiastolic: 78,
  );

  test(
    'calculates values from raw measurements and round-trips coded values',
    () {
      expect(questionnaire.weeklyActiveMinutes, 150);
      expect(questionnaire.bmi, closeTo(25, 0.001));
      expect(questionnaire.averageSystolic, 122);
      expect(questionnaire.averageDiastolic, 79);
      final restored = NcdQuestionnaire.fromMap(questionnaire.toMap());
      expect(restored?.studySite, 'community_clinic');
      expect(restored?.tobaccoUse, isNull);
      expect(restored?.toCsvRow()['ncd_weekly_active_minutes'], '150');
      expect(restored?.toCsvRow()['ncd_schema_version'], '2');
    },
  );

  test(
    'accepts pre-versioned records but rejects an unknown future schema',
    () {
      final original = questionnaire.toMap();
      expect(original['schemaVersion'], NcdQuestionnaire.schemaVersion);
      final legacy = Map<String, Object?>.from(original)
        ..remove('schemaVersion');
      expect(NcdQuestionnaire.fromMap(legacy), isNotNull);
      expect(
        NcdQuestionnaire.fromMap({...original, 'schemaVersion': 3}),
        isNull,
      );
    },
  );

  test('missing measurements carry reasons and leave derived values blank', () {
    final map = {
      ...questionnaire.toMap(),
      'heightCm': null,
      'heightMissingReason': 'unable',
      'bpOneSystolic': null,
      'bpOneDiastolic': null,
      'bpOneMissingReason': 'declined',
    };
    final restored = NcdQuestionnaire.fromMap(map);
    expect(restored, isNotNull);
    expect(restored?.bmi, isNull);
    expect(restored?.averageSystolic, isNull);
    expect(restored?.averageDiastolic, isNull);
    expect(restored?.toCsvRow()['ncd_bmi'], '');
    expect(restored?.toCsvRow()['ncd_height_missing_reason'], 'unable');
    expect(restored?.toCsvRow()['ncd_bp_one_missing_reason'], 'declined');
    expect(
      NcdQuestionnaire.fromMap({...map, 'heightMissingReason': null}),
      isNull,
    );
    expect(NcdQuestionnaire.fromMap({...map, 'bpOneDiastolic': 80}), isNull);
  });

  test(
    'rejects measured blood pressure with diastolic at or above systolic',
    () {
      final original = questionnaire.toMap();
      expect(
        NcdQuestionnaire.fromMap({...original, 'bpOneSystolic': 80}),
        isNull,
      );
      expect(
        NcdQuestionnaire.fromMap({...original, 'bpTwoDiastolic': 130}),
        isNull,
      );

      final legacy = Map<String, Object?>.from(original)
        ..remove('schemaVersion');
      expect(NcdQuestionnaire.fromMap(legacy), isNotNull);
    },
  );

  test('rejects non-finite and fractional integer values', () {
    final original = questionnaire.toMap();
    for (final value in [double.nan, double.infinity, 120.5]) {
      expect(
        NcdQuestionnaire.fromMap({...original, 'bpOneSystolic': value}),
        isNull,
      );
    }
    expect(
      NcdQuestionnaire.fromMap({...original, 'bpOneSystolic': 120.0}),
      isNotNull,
    );
    expect(
      NcdQuestionnaire.fromMap({...original, 'age': 34.5}),
      isNull,
    );
  });

  test(
    'rejects non-finite decimal values when parsing stored questionnaires',
    () {
      final original = questionnaire.toMap();
      expect(
        NcdQuestionnaire.fromMap({...original, 'sleepHours': double.nan}),
        isNull,
      );
      expect(
        NcdQuestionnaire.fromMap({...original, 'heightCm': double.infinity}),
        isNull,
      );
      expect(
        NcdQuestionnaire.fromMap({...original, 'sleepHours': 'NaN'}),
        isNull,
      );
    },
  );

  test('does not treat incomplete legacy values as a questionnaire', () {
    expect(NcdQuestionnaire.fromMap({'studySite': 'community_clinic'}), isNull);
  });
}
