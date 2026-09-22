/// A compact, interviewer-entered NCD risk questionnaire.
///
/// Values are deliberately raw or coded rather than interpreted. A null value
/// means the participant chose not to answer (or the item was not applicable).
class NcdQuestionnaire {
  const NcdQuestionnaire({
    required this.studySite,
    required this.age,
    required this.sex,
    required this.education,
    required this.employment,
    required this.fruitFrequency,
    required this.vegetableFrequency,
    required this.sugaryDrinkFrequency,
    required this.processedFoodFrequency,
    required this.activeDaysPerWeek,
    required this.activeMinutesPerDay,
    required this.sleepHours,
    required this.heightCm,
    required this.weightKg,
    required this.waistCm,
    required this.bpOneSystolic,
    required this.bpOneDiastolic,
    required this.bpTwoSystolic,
    required this.bpTwoDiastolic,
    this.tobaccoUse,
    this.tobaccoType,
    this.tobaccoFrequency,
    this.alcoholPast30Days,
    this.alcoholFrequency,
    this.hypertensionDiagnosis,
    this.diabetesDiagnosis,
    this.highCholesterolDiagnosis,
    this.cardiovascularDiagnosis,
  }) : assert(age >= 18),
       assert(heightCm > 0),
       assert(weightKg > 0),
       assert(waistCm > 0),
       assert(bpOneSystolic > 0 && bpOneDiastolic > 0),
       assert(bpTwoSystolic > 0 && bpTwoDiastolic > 0);

  final String studySite;
  final int age;
  final String sex;
  final String education;
  final String employment;
  final String fruitFrequency;
  final String vegetableFrequency;
  final String sugaryDrinkFrequency;
  final String processedFoodFrequency;
  final int activeDaysPerWeek;
  final int activeMinutesPerDay;
  final double sleepHours;
  final double heightCm;
  final double weightKg;
  final double waistCm;
  final int bpOneSystolic;
  final int bpOneDiastolic;
  final int bpTwoSystolic;
  final int bpTwoDiastolic;
  final String? tobaccoUse;
  final String? tobaccoType;
  final String? tobaccoFrequency;
  final String? alcoholPast30Days;
  final String? alcoholFrequency;
  final String? hypertensionDiagnosis;
  final String? diabetesDiagnosis;
  final String? highCholesterolDiagnosis;
  final String? cardiovascularDiagnosis;

  int get weeklyActiveMinutes => activeDaysPerWeek * activeMinutesPerDay;
  double get bmi => weightKg / ((heightCm / 100) * (heightCm / 100));
  double get averageSystolic => (bpOneSystolic + bpTwoSystolic) / 2;
  double get averageDiastolic => (bpOneDiastolic + bpTwoDiastolic) / 2;

  Map<String, Object?> toMap() => {
    'studySite': studySite,
    'age': age,
    'sex': sex,
    'education': education,
    'employment': employment,
    'tobaccoUse': tobaccoUse,
    'tobaccoType': tobaccoType,
    'tobaccoFrequency': tobaccoFrequency,
    'alcoholPast30Days': alcoholPast30Days,
    'alcoholFrequency': alcoholFrequency,
    'fruitFrequency': fruitFrequency,
    'vegetableFrequency': vegetableFrequency,
    'sugaryDrinkFrequency': sugaryDrinkFrequency,
    'processedFoodFrequency': processedFoodFrequency,
    'activeDaysPerWeek': activeDaysPerWeek,
    'activeMinutesPerDay': activeMinutesPerDay,
    'weeklyActiveMinutes': weeklyActiveMinutes,
    'sleepHours': sleepHours,
    'hypertensionDiagnosis': hypertensionDiagnosis,
    'diabetesDiagnosis': diabetesDiagnosis,
    'highCholesterolDiagnosis': highCholesterolDiagnosis,
    'cardiovascularDiagnosis': cardiovascularDiagnosis,
    'heightCm': heightCm,
    'weightKg': weightKg,
    'waistCm': waistCm,
    'bmi': bmi,
    'bpOneSystolic': bpOneSystolic,
    'bpOneDiastolic': bpOneDiastolic,
    'bpTwoSystolic': bpTwoSystolic,
    'bpTwoDiastolic': bpTwoDiastolic,
    'averageSystolic': averageSystolic,
    'averageDiastolic': averageDiastolic,
  };

  Map<String, String> toCsvRow() => toMap().map(
    (key, value) => MapEntry('ncd_${_snakeCase(key)}', value?.toString() ?? ''),
  );

  static NcdQuestionnaire? fromMap(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, Object?>.from(value);
    try {
      return NcdQuestionnaire(
        studySite: _text(json, 'studySite'), age: _integer(json, 'age'),
        sex: _text(json, 'sex'), education: _text(json, 'education'),
        employment: _text(json, 'employment'),
        fruitFrequency: _text(json, 'fruitFrequency'),
        vegetableFrequency: _text(json, 'vegetableFrequency'),
        sugaryDrinkFrequency: _text(json, 'sugaryDrinkFrequency'),
        processedFoodFrequency: _text(json, 'processedFoodFrequency'),
        activeDaysPerWeek: _integer(json, 'activeDaysPerWeek'),
        activeMinutesPerDay: _integer(json, 'activeMinutesPerDay'),
        sleepHours: _number(json, 'sleepHours'), heightCm: _number(json, 'heightCm'),
        weightKg: _number(json, 'weightKg'), waistCm: _number(json, 'waistCm'),
        bpOneSystolic: _integer(json, 'bpOneSystolic'),
        bpOneDiastolic: _integer(json, 'bpOneDiastolic'),
        bpTwoSystolic: _integer(json, 'bpTwoSystolic'),
        bpTwoDiastolic: _integer(json, 'bpTwoDiastolic'),
        tobaccoUse: _optional(json, 'tobaccoUse'), tobaccoType: _optional(json, 'tobaccoType'),
        tobaccoFrequency: _optional(json, 'tobaccoFrequency'),
        alcoholPast30Days: _optional(json, 'alcoholPast30Days'),
        alcoholFrequency: _optional(json, 'alcoholFrequency'),
        hypertensionDiagnosis: _optional(json, 'hypertensionDiagnosis'),
        diabetesDiagnosis: _optional(json, 'diabetesDiagnosis'),
        highCholesterolDiagnosis: _optional(json, 'highCholesterolDiagnosis'),
        cardiovascularDiagnosis: _optional(json, 'cardiovascularDiagnosis'),
      );
    } on FormatException {
      return null;
    }
  }

  static String _text(Map<String, Object?> json, String key) =>
      _optional(json, key) ?? (throw FormatException('Missing $key'));
  static String? _optional(Map<String, Object?> json, String key) =>
      json[key] is String && (json[key] as String).isNotEmpty
      ? json[key] as String
      : null;
  static int _integer(Map<String, Object?> json, String key) => json[key] is num
      ? (json[key] as num).toInt()
      : int.parse('${json[key]}');
  static double _number(Map<String, Object?> json, String key) =>
      json[key] is num ? (json[key] as num).toDouble() : double.parse('${json[key]}');
  static String _snakeCase(String value) => value.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (match) => '_${match.group(0)!.toLowerCase()}',
  );
}
