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
  final history = {
    'hypertension': q['hypertensionDiagnosis'],
    'diabetes': q['diabetesDiagnosis'],
    'heart_disease': q['heartDiseaseDiagnosis'],
  };
  final missing = <String>[
    if (age is! int || age < 18 || age > 105) 'age',
    if (sex != 'male' && sex != 'female') 'sex',
    if (!{'none', 'primary', 'secondary', 'higher'}.contains(education))
      'education',
    if (!{'never', 'former', 'current'}.contains(tobacco)) 'tobaccoUse',
    if (!{'no_difficulty', 'with_difficulty', 'unable'}.contains(walking))
      'walkingOneKm',
    if (!_isYesNo(alcohol)) 'drinksAlcohol',
    if (!_isYesNo(worked)) 'workedPastYear',
    if (!_isYesNo(history['hypertension'])) 'hypertensionDiagnosis',
    if (!_isYesNo(history['diabetes'])) 'diabetesDiagnosis',
    if (!_isYesNo(history['heart_disease'])) 'heartDiseaseDiagnosis',
  ];
  final outcomes = <String, Object?>{};
  for (final entry in _weights.entries) {
    outcomes[entry.key] = history[entry.key] == 'yes'
        ? {'status': 'prior_diagnosis'}
        : missing.isNotEmpty
        ? {'status': 'insufficient_information', 'fields': missing}
        : {
            'status': 'estimated',
            'probability': _probability(
              entry.value,
              (age as int),
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
    'modelVersion': 'ihds-37382-expanded-v1',
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
