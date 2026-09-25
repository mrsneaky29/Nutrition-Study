/// A compact, interviewer-entered NCD risk questionnaire.
///
/// Values are deliberately raw or coded rather than interpreted. Optional
/// interview answers may be null; a missing measurement carries an explicit
/// `unable` or `declined` reason.
class NcdQuestionnaire {
  /// Persisted with each response so later questionnaire revisions remain
  /// distinguishable in operational records and analysis exports.
  static const int schemaVersion = 2;

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
    this.heightMissingReason,
    this.weightMissingReason,
    this.waistMissingReason,
    this.bpOneMissingReason,
    this.bpTwoMissingReason,
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
       assert(heightCm == null || heightCm > 0),
       assert(weightKg == null || weightKg > 0),
       assert(waistCm == null || waistCm > 0),
       assert((bpOneSystolic == null) == (bpOneDiastolic == null)),
       assert((bpTwoSystolic == null) == (bpTwoDiastolic == null)),
       assert(heightCm != null
           ? heightMissingReason == null
           : heightMissingReason == 'unable' || heightMissingReason == 'declined'),
       assert(weightKg != null
           ? weightMissingReason == null
           : weightMissingReason == 'unable' || weightMissingReason == 'declined'),
       assert(waistCm != null
           ? waistMissingReason == null
           : waistMissingReason == 'unable' || waistMissingReason == 'declined'),
       assert(bpOneSystolic != null
           ? bpOneMissingReason == null
           : bpOneMissingReason == 'unable' || bpOneMissingReason == 'declined'),
       assert(bpTwoSystolic != null
           ? bpTwoMissingReason == null
           : bpTwoMissingReason == 'unable' || bpTwoMissingReason == 'declined');

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
  final double? heightCm;
  final double? weightKg;
  final double? waistCm;
  final int? bpOneSystolic;
  final int? bpOneDiastolic;
  final int? bpTwoSystolic;
  final int? bpTwoDiastolic;

  /// `declined` or `unable` when a measurement could not be recorded.
  final String? heightMissingReason;
  final String? weightMissingReason;
  final String? waistMissingReason;
  final String? bpOneMissingReason;
  final String? bpTwoMissingReason;
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
  double? get bmi => heightCm == null || weightKg == null
      ? null
      : weightKg! / ((heightCm! / 100) * (heightCm! / 100));
  double? get averageSystolic => bpOneSystolic == null || bpTwoSystolic == null
      ? null
      : (bpOneSystolic! + bpTwoSystolic!) / 2;
  double? get averageDiastolic =>
      bpOneDiastolic == null || bpTwoDiastolic == null
      ? null
      : (bpOneDiastolic! + bpTwoDiastolic!) / 2;

  Map<String, Object?> toMap() => {
    'schemaVersion': schemaVersion,
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
    'heightMissingReason': heightMissingReason,
    'weightMissingReason': weightMissingReason,
    'waistMissingReason': waistMissingReason,
    'bmi': bmi,
    'bpOneSystolic': bpOneSystolic,
    'bpOneDiastolic': bpOneDiastolic,
    'bpTwoSystolic': bpTwoSystolic,
    'bpTwoDiastolic': bpTwoDiastolic,
    'bpOneMissingReason': bpOneMissingReason,
    'bpTwoMissingReason': bpTwoMissingReason,
    'averageSystolic': averageSystolic,
    'averageDiastolic': averageDiastolic,
  };

  Map<String, String> toCsvRow() => toMap().map(
    (key, value) => MapEntry('ncd_${_snakeCase(key)}', value?.toString() ?? ''),
  );

  static NcdQuestionnaire? fromMap(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, Object?>.from(value);
    // Unversioned and v1 records always had numeric measurements.
    final version = json['schemaVersion'] ?? 1;
    if (version != 1 && version != schemaVersion) return null;
    try {
      final height = _measurementNumber(
        json,
        'heightCm',
        'heightMissingReason',
        version == schemaVersion,
      );
      final weight = _measurementNumber(
        json,
        'weightKg',
        'weightMissingReason',
        version == schemaVersion,
      );
      final waist = _measurementNumber(
        json,
        'waistCm',
        'waistMissingReason',
        version == schemaVersion,
      );
      final bpOne = _bpPair(
        json,
        'bpOneSystolic',
        'bpOneDiastolic',
        'bpOneMissingReason',
        version == schemaVersion,
      );
      final bpTwo = _bpPair(
        json,
        'bpTwoSystolic',
        'bpTwoDiastolic',
        'bpTwoMissingReason',
        version == schemaVersion,
      );
      final age = _integer(json, 'age');
      if (age < 18 ||
          height != null && height <= 0 ||
          weight != null && weight <= 0 ||
          waist != null && waist <= 0) {
        throw const FormatException('Invalid questionnaire measurement.');
      }
      return NcdQuestionnaire(
        studySite: _text(json, 'studySite'),
        age: age,
        sex: _text(json, 'sex'),
        education: _text(json, 'education'),
        employment: _text(json, 'employment'),
        fruitFrequency: _text(json, 'fruitFrequency'),
        vegetableFrequency: _text(json, 'vegetableFrequency'),
        sugaryDrinkFrequency: _text(json, 'sugaryDrinkFrequency'),
        processedFoodFrequency: _text(json, 'processedFoodFrequency'),
        activeDaysPerWeek: _integer(json, 'activeDaysPerWeek'),
        activeMinutesPerDay: _integer(json, 'activeMinutesPerDay'),
        sleepHours: _number(json, 'sleepHours'),
        heightCm: height,
        weightKg: weight,
        waistCm: waist,
        heightMissingReason: _optional(json, 'heightMissingReason'),
        weightMissingReason: _optional(json, 'weightMissingReason'),
        waistMissingReason: _optional(json, 'waistMissingReason'),
        bpOneSystolic: bpOne.$1,
        bpOneDiastolic: bpOne.$2,
        bpTwoSystolic: bpTwo.$1,
        bpTwoDiastolic: bpTwo.$2,
        bpOneMissingReason: _optional(json, 'bpOneMissingReason'),
        bpTwoMissingReason: _optional(json, 'bpTwoMissingReason'),
        tobaccoUse: _optional(json, 'tobaccoUse'),
        tobaccoType: _optional(json, 'tobaccoType'),
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
  static int _integer(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! num) return int.parse('$value');
    if (!value.isFinite || value != value.truncateToDouble()) {
      throw FormatException('Invalid $key.');
    }
    return value.toInt();
  }
  static double _number(Map<String, Object?> json, String key) =>
      _finiteNumber(
        json[key] is num
            ? (json[key] as num).toDouble()
            : double.parse('${json[key]}'),
        key,
      );
  static double _finiteNumber(double value, String key) => value.isFinite
      ? value
      : throw FormatException('Invalid $key.');
  static bool _validMissingReason(String? value) =>
      value == 'declined' || value == 'unable';
  static double? _measurementNumber(
    Map<String, Object?> json,
    String key,
    String reasonKey,
    bool allowMissing,
  ) {
    final reason = _optional(json, reasonKey);
    if (json[key] == null) {
      if (!allowMissing || !_validMissingReason(reason)) {
        throw FormatException('Missing $key without a valid reason.');
      }
      return null;
    }
    if (reason != null) throw FormatException('$key has a missing reason.');
    final number = _number(json, key);
    if (!number.isFinite || number <= 0) throw FormatException('Invalid $key.');
    return number;
  }

  static (int?, int?) _bpPair(
    Map<String, Object?> json,
    String systolicKey,
    String diastolicKey,
    String reasonKey,
    bool allowMissing,
  ) {
    final reason = _optional(json, reasonKey);
    if (json[systolicKey] == null || json[diastolicKey] == null) {
      if (!allowMissing ||
          !_validMissingReason(reason) ||
          json[systolicKey] != null ||
          json[diastolicKey] != null) {
        throw FormatException('Incomplete $systolicKey/$diastolicKey.');
      }
      return (null, null);
    }
    if (reason != null) {
      throw FormatException('$systolicKey has a missing reason.');
    }
    final systolic = _integer(json, systolicKey);
    final diastolic = _integer(json, diastolicKey);
    if (systolic <= 0 || diastolic <= 0 || systolic <= diastolic) {
      throw FormatException('Invalid $systolicKey/$diastolicKey.');
    }
    return (systolic, diastolic);
  }

  static String _snakeCase(String value) => value.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (match) => '_${match.group(0)!.toLowerCase()}',
  );
}
