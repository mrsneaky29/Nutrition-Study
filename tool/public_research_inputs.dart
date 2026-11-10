/// Public-form validation. No filesystem, account, network or logging access.
library;

const publicSurveyConsentVersion = 'vivayu-web-survey-2026-11-v1';

const publicModelChoices = <String, Set<String>>{
  'sex': {'female', 'male', 'other'},
  'education': {'none', 'primary', 'secondary', 'higher'},
  'tobaccoUse': {'never', 'former', 'current'},
  'walkingOneKm': {'no_difficulty', 'with_difficulty', 'unable', 'dont_know'},
  'drinksAlcohol': {'yes', 'no', 'dont_know'},
  'workedPastYear': {'yes', 'no', 'dont_know'},
  'hypertensionDiagnosis': {'yes', 'no', 'dont_know'},
  'diabetesDiagnosis': {'yes', 'no', 'dont_know'},
  'heartDiseaseDiagnosis': {'yes', 'no', 'dont_know'},
};

Map<String, dynamic> normalizePublicModelAnswers(Object? value) {
  if (value is! Map ||
      value.keys.any((k) => k != 'age' && !publicModelChoices.containsKey(k))) {
    throw const FormatException('Use only the requested model answers.');
  }
  final result = <String, dynamic>{'schemaVersion': 4};
  final age = value['age'];
  if (age != null &&
      (age is! num ||
          !age.isFinite ||
          age != age.roundToDouble() ||
          age < 18 ||
          age > 120)) {
    throw const FormatException(
      'Enter a whole-number adult age from 18 to 120.',
    );
  }
  result['age'] = age;
  for (final entry in publicModelChoices.entries) {
    final answer = value[entry.key];
    if (answer != null && !entry.value.contains(answer)) {
      throw const FormatException('Choose one of the displayed answers.');
    }
    result[entry.key] = answer;
  }
  return result;
}

Map<String, dynamic> normalizePublicSurveyQuestionnaire(Object? value) {
  if (value is! Map) {
    throw const FormatException('Complete the survey before saving.');
  }
  final model = normalizePublicModelAnswers({
    'age': value['age'],
    for (final key in publicModelChoices.keys) key: value[key],
  });
  const requiredChoices = {
    'studySite': {'other_site'},
    'sex': {'female', 'male', 'other'},
    'education': {'none', 'primary', 'secondary', 'higher'},
    'employment': {
      'employed',
      'self_employed',
      'student',
      'homemaker',
      'unemployed',
      'retired',
    },
    'fruitFrequency': {
      'never',
      'one_to_two_days',
      'three_to_four_days',
      'five_to_six_days',
      'daily',
    },
    'vegetableFrequency': {
      'never',
      'one_to_two_days',
      'three_to_four_days',
      'five_to_six_days',
      'daily',
    },
    'sugaryDrinkFrequency': {
      'never',
      'one_to_two_days',
      'three_to_four_days',
      'five_to_six_days',
      'daily',
    },
    'processedFoodFrequency': {
      'never',
      'one_to_two_days',
      'three_to_four_days',
      'five_to_six_days',
      'daily',
    },
  };
  const optionalChoices = {
    'tobaccoType': {'smoked', 'smokeless', 'both'},
    'tobaccoFrequency': {'daily', 'less_than_daily'},
    'alcoholPast30Days': {'yes', 'no'},
    'alcoholFrequency': {
      'less_than_weekly',
      'one_to_three_weekly',
      'four_or_more_weekly',
    },
    'highCholesterolDiagnosis': {'yes', 'no', 'dont_know'},
    'cardiovascularDiagnosis': {'yes', 'no', 'dont_know'},
  };
  for (final entry in requiredChoices.entries) {
    if (!entry.value.contains(value[entry.key])) {
      throw const FormatException('Complete the required survey choices.');
    }
  }
  for (final entry in optionalChoices.entries) {
    if (value[entry.key] != null && !entry.value.contains(value[entry.key])) {
      throw const FormatException('Choose a valid optional survey answer.');
    }
  }
  if (value['tobaccoUse'] == 'current' &&
      (value['tobaccoType'] == null || value['tobaccoFrequency'] == null)) {
    throw const FormatException('Complete tobacco type and frequency.');
  }
  if (value['alcoholPast30Days'] == 'yes' &&
      value['alcoholFrequency'] == null) {
    throw const FormatException('Complete alcohol frequency.');
  }
  num number(String key, num min, num max, {bool whole = false}) {
    final n = value[key];
    if (n is! num ||
        !n.isFinite ||
        n < min ||
        n > max ||
        (whole && n != n.roundToDouble())) {
      throw const FormatException('Check the survey numbers and units.');
    }
    return n;
  }

  number('age', 18, 120, whole: true);
  final days = number('activeDaysPerWeek', 0, 7, whole: true);
  final minutes = number('activeMinutesPerDay', 0, 1440, whole: true);
  number('sleepHours', 0, 24);
  // Reject unsupported fields through the existing questionnaire validator;
  // calculate derived values here instead of trusting submitted calculations.
  final q = Map<String, dynamic>.from(value)
    ..addAll(model)
    ..['schemaVersion'] = 4;
  for (final field in [
    'heightCm',
    'weightKg',
    'waistCm',
    'hipCm',
    'bpOneSystolic',
    'bpOneDiastolic',
    'bpTwoSystolic',
    'bpTwoDiastolic',
  ]) {
    if (q[field] != null &&
        (q[field] is! num ||
            !(q[field] as num).isFinite ||
            (q[field] as num) <= 0)) {
      throw const FormatException(
        'Enter a positive measurement or its missing reason.',
      );
    }
  }
  q['weeklyActiveMinutes'] = days * minutes;
  for (final prefix in ['bpOne', 'bpTwo']) {
    final systolic = q['${prefix}Systolic'];
    final diastolic = q['${prefix}Diastolic'];
    if (systolic is num &&
        diastolic is num &&
        (systolic != systolic.roundToDouble() ||
            diastolic != diastolic.roundToDouble() ||
            systolic <= diastolic ||
            systolic > 400 ||
            diastolic > 300)) {
      throw const FormatException(
        'Check the systolic and diastolic blood pressure readings.',
      );
    }
  }
  q['bmi'] = q['heightCm'] == null || q['weightKg'] == null
      ? null
      : (q['weightKg'] as num) /
            (((q['heightCm'] as num) / 100) * ((q['heightCm'] as num) / 100));
  q['waistHipRatio'] = q['waistCm'] == null || q['hipCm'] == null
      ? null
      : (q['waistCm'] as num) / (q['hipCm'] as num);
  q['averageSystolic'] =
      q['bpOneSystolic'] == null || q['bpTwoSystolic'] == null
      ? null
      : ((q['bpOneSystolic'] as num) + (q['bpTwoSystolic'] as num)) / 2;
  q['averageDiastolic'] =
      q['bpOneDiastolic'] == null || q['bpTwoDiastolic'] == null
      ? null
      : ((q['bpOneDiastolic'] as num) + (q['bpTwoDiastolic'] as num)) / 2;
  return q;
}
