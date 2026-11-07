import 'dart:math';

/// Estimates newly reported diagnoses between the two historical IHDS waves.
Map<String, Object?> scoreIhdsResearchRisk(Object? questionnaire) {
  final q = questionnaire is Map ? questionnaire : const <String, Object?>{};
  final age = q['age'];
  final sex = q['sex'];
  final education = q['education'];
  final tobacco = q['tobaccoUse'];
  final walking = q['walkingOneKm'];
  final alcohol = q['drinksAlcohol'];
  final worked = q['workedPastYear'];
  const diagnosisFields = {
    'hypertension': 'hypertensionDiagnosis',
    'diabetes': 'diabetesDiagnosis',
    'heart_disease': 'heartDiseaseDiagnosis',
  };
  final history = diagnosisFields.map(
    (outcome, field) => MapEntry(outcome, q[field]),
  );
  final missing = <String>[
    if (age is! num ||
        !age.isFinite ||
        age != age.truncate() ||
        age < 18 ||
        age > 105)
      'age',
    if (sex != 'male' && sex != 'female') 'sex',
    if (!{'none', 'primary', 'secondary', 'higher'}.contains(education))
      'education',
    if (!{'never', 'former', 'current'}.contains(tobacco)) 'tobaccoUse',
  ];
  final expanded =
      {'no_difficulty', 'with_difficulty', 'unable'}.contains(walking) &&
      _isYesNo(alcohol) &&
      _isYesNo(worked) &&
      history.values.every(_isYesNo);
  final modelVersion = expanded
      ? 'ihds-37382-expanded-v1'
      : 'ihds-37382-original-v1';
  final weights = expanded ? _weights : _originalWeights;
  // A negative answer to the older, broader question can rule out a reported
  // heart disease diagnosis. A positive answer may describe another condition.
  final fallbackHeartHistory =
      (q['schemaVersion'] == null ||
              q['schemaVersion'] == 1 ||
              q['schemaVersion'] == 2 ||
              q['schemaVersion'] == 3) &&
          history['heart_disease'] == null &&
          q['cardiovascularDiagnosis'] == 'no'
      ? 'no'
      : history['heart_disease'];
  final outcomes = <String, Object?>{};
  for (final entry in weights.entries) {
    final diagnosis = entry.key == 'heart_disease' && !expanded
        ? fallbackHeartHistory
        : history[entry.key];
    final needed = [
      ...missing,
      if (!_isYesNo(diagnosis)) diagnosisFields[entry.key]!,
    ];
    outcomes[entry.key] = diagnosis == 'yes'
        ? {'status': 'prior_diagnosis'}
        : needed.isNotEmpty
        ? {'status': 'insufficient_information', 'fields': needed}
        : {
            'status': 'estimated',
            'probability': _probability(
              entry.value,
              (age as num).toInt(),
              sex == 'female',
              education,
              tobacco == 'current',
              walking != 'no_difficulty',
              alcohol == 'yes',
              worked == 'yes',
              history,
            ),
          };
  }
  return {
    'modelVersion': modelVersion,
    'researchOnly': true,
    'outcome': 'Newly reported doctor diagnosis by follow-up',
    'baseline': '2004-05',
    'followUp': '2011-12',
    'outcomes': outcomes,
  };
}

bool _isYesNo(Object? value) => value == 'yes' || value == 'no';

double _probability(
  Map<String, double> weights,
  int age,
  bool female,
  Object? education,
  bool tobacco,
  bool walkingDifficulty,
  bool drinks,
  bool worked,
  Map<String, Object?> history,
) {
  final scaledAge = (age - 50) / 20;
  final inputs = <String, num>{
    'intercept': 1,
    'age_centered_scaled': scaledAge,
    'age_centered_scaled_squared': scaledAge * scaledAge,
    if (female) 'female': 1,
    if (education != 'none') education as String: 1,
    if (tobacco) 'current_tobacco': 1,
    if (walkingDifficulty) 'walk_difficulty': 1,
    if (drinks) 'alcohol_use': 1,
    if (worked) 'worked': 1,
    for (final entry in history.entries)
      if (entry.value == 'yes') 'prior_${entry.key}': 1,
  };
  var logit = 0.0;
  for (final entry in weights.entries) {
    logit += entry.value * (inputs[entry.key] ?? 0);
  }
  return 1 / (1 + exp(-logit));
}

// Coefficients from audits/ihds-risk-model/expanded-results.json in Project2.
const _weights = <String, Map<String, double>>{
  'hypertension': {
    'intercept': -2.566382769219719,
    'age_centered_scaled': 0.9217228528246315,
    'age_centered_scaled_squared': -0.6671649220689679,
    'female': 0.45086526625614914,
    'primary': 0.4183048910343817,
    'secondary': 0.6017179537987926,
    'higher': 0.757285816511393,
    'current_tobacco': -0.31777256592827713,
    'walk_difficulty': -0.06214079696154751,
    'alcohol_use': 0.026318103473256922,
    'worked': -0.2917539000515958,
    'prior_diabetes': 0.9800458166255989,
    'prior_heart_disease': 1.036990303906512,
  },
  'diabetes': {
    'intercept': -3.019486054298829,
    'age_centered_scaled': 1.0071466456348683,
    'age_centered_scaled_squared': -0.9591944835733529,
    'female': -0.11342115445959562,
    'primary': 0.6809077828696735,
    'secondary': 1.0104231068751914,
    'higher': 1.0083300375204902,
    'current_tobacco': -0.5388840840480962,
    'walk_difficulty': 0.1945578141681899,
    'alcohol_use': 0.15253535268342786,
    'worked': -0.38584642711964695,
    'prior_hypertension': 0.8451660127964056,
    'prior_heart_disease': 0.8795729011065627,
  },
  'heart_disease': {
    'intercept': -3.5638552987411343,
    'age_centered_scaled': 0.7434615577028233,
    'age_centered_scaled_squared': -0.5566160846319136,
    'female': -0.23729526769726864,
    'primary': 0.2703213286500638,
    'secondary': 0.2887518117807103,
    'higher': 0.279110922221212,
    'current_tobacco': -0.24191720519543608,
    'walk_difficulty': 0.1743820227214874,
    'alcohol_use': -0.09132490174846894,
    'worked': -0.3348085456802617,
    'prior_hypertension': 0.8290545588469215,
    'prior_diabetes': 0.6211009092672143,
  },
};

// Coefficients from audits/ihds-risk-model/results.json.
const _originalWeights = <String, Map<String, double>>{
  'hypertension': {
    'intercept': -2.8310608000282835,
    'age_centered_scaled': 1.002220593866191,
    'age_centered_scaled_squared': -0.6288209513120964,
    'female': 0.5962563979193463,
    'primary': 0.4713480314568989,
    'secondary': 0.6871817221073598,
    'higher': 0.8467461562898123,
    'current_tobacco': -0.3517729071462222,
  },
  'diabetes': {
    'intercept': -3.365801178292736,
    'age_centered_scaled': 1.1389840188962232,
    'age_centered_scaled_squared': -0.8904980368380072,
    'female': 0.1100394029948272,
    'primary': 0.7542734490306184,
    'secondary': 1.112275547438619,
    'higher': 1.1267592851899098,
    'current_tobacco': -0.5553243697394119,
  },
  'heart_disease': {
    'intercept': -3.8608258868729943,
    'age_centered_scaled': 0.8740299357080684,
    'age_centered_scaled_squared': -0.5050058007088354,
    'female': -0.035754297265363805,
    'primary': 0.34391125810779766,
    'secondary': 0.4033674069933089,
    'higher': 0.4113849893586978,
    'current_tobacco': -0.311661899941523,
  },
};
