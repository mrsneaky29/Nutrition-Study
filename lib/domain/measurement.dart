/// Optional, un-interpreted data from Step 2 of a visit.
class StepTwoMeasurement {
  const StepTwoMeasurement({
    required this.value,
    required this.unit,
    this.recordedAt,
    this.note,
  }) : assert(value >= 0),
       assert(unit != '');

  final num value;
  final String unit;
  final DateTime? recordedAt;
  final String? note;

  Map<String, Object?> toFirestoreMap() => {
    'value': value,
    'unit': unit,
    'recordedAt': recordedAt?.toUtc().toIso8601String(),
    'note': note,
  };

  Map<String, String> toCsvRow() => {
    'step_2_value': value.toString(),
    'step_2_unit': unit,
    'step_2_recorded_at': recordedAt?.toUtc().toIso8601String() ?? '',
    'step_2_note': note ?? '',
  };
}
