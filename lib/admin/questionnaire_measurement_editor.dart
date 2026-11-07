import 'package:flutter/material.dart';

import '../domain/ncd_questionnaire.dart';

class QuestionnaireMeasurementEditor extends StatefulWidget {
  const QuestionnaireMeasurementEditor(this.questionnaire, {super.key});

  final NcdQuestionnaire questionnaire;

  @override
  State<QuestionnaireMeasurementEditor> createState() =>
      QuestionnaireMeasurementEditorState();
}

class QuestionnaireMeasurementEditorState
    extends State<QuestionnaireMeasurementEditor> {
  static const _bodyFields = {
    'heightCm': ('Height (cm)', 'heightMissingReason'),
    'weightKg': ('Weight (kg)', 'weightMissingReason'),
    'waistCm': ('Waist circumference (cm)', 'waistMissingReason'),
    'hipCm': ('Hip circumference (cm)', 'hipMissingReason'),
  };
  static const _pressureFields = [
    ('BP1', 'bpOneSystolic', 'bpOneDiastolic', 'bpOneMissingReason'),
    ('BP2', 'bpTwoSystolic', 'bpTwoDiastolic', 'bpTwoMissingReason'),
  ];
  static const _reportedFields = {
    'activeDaysPerWeek': ('Active days per week', 7, true),
    'activeMinutesPerDay': ('Active minutes per day', 1440, true),
    'sleepHours': ('Sleep hours per night', 24, false),
  };

  final _inputs = <String, TextEditingController>{};
  final _statuses = <String, String>{};

  @override
  void initState() {
    super.initState();
    final original = widget.questionnaire.toMap();
    for (final field in [
      ..._bodyFields.keys,
      ..._reportedFields.keys,
      for (final (_, systolic, diastolic, _) in _pressureFields) ...[
        systolic,
        diastolic,
      ],
    ]) {
      _inputs[field] = TextEditingController(
        text: original[field]?.toString() ?? '',
      );
    }
    for (final reason in [
      for (final (_, reason) in _bodyFields.values) reason,
      for (final (_, _, _, reason) in _pressureFields) reason,
    ]) {
      _statuses[reason] = original[reason] as String? ?? 'measured';
    }
    if (widget.questionnaire.version < 3) {
      _statuses['hipMissingReason'] = 'not_collected';
    }
  }

  @override
  void dispose() {
    for (final input in _inputs.values) {
      input.dispose();
    }
    super.dispose();
  }

  /// Call after the surrounding form validates.
  NcdQuestionnaire editedQuestionnaire() {
    final values = widget.questionnaire.toMap();
    var version = widget.questionnaire.version;

    void applyMeasurement(String reason, List<String> fields, bool integer) {
      final status = _statuses[reason]!;
      if (status == 'not_collected') return;
      final measured = status == 'measured';
      for (final field in fields) {
        final text = _inputs[field]!.text.trim();
        values[field] = !measured
            ? null
            : integer
            ? int.parse(text)
            : double.parse(text);
      }
      values[reason] = measured ? null : status;
      if (!measured && version == 1) version = 2;
    }

    for (final entry in _bodyFields.entries) {
      applyMeasurement(entry.value.$2, [entry.key], false);
    }
    for (final (_, systolic, diastolic, reason) in _pressureFields) {
      applyMeasurement(reason, [systolic, diastolic], true);
    }
    for (final entry in _reportedFields.entries) {
      final text = _inputs[entry.key]!.text.trim();
      values[entry.key] = entry.value.$3 ? int.parse(text) : double.parse(text);
    }
    if (_statuses['hipMissingReason'] != 'not_collected' && version < 3) {
      version = 3;
    }
    values['schemaVersion'] = version;
    if (version >= 3) {
      final waist = values['waistCm'] as num?;
      final hip = values['hipCm'] as num?;
      values['waistHipRatio'] = waist == null || hip == null
          ? null
          : waist / hip;
    }
    final result = NcdQuestionnaire.fromMap(values);
    if (result == null)
      throw ArgumentError('Check the questionnaire measurements.');
    return result;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Questionnaire measurements',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      const Text('BMI, waist-to-hip ratio and averages recalculate on save.'),
      for (final entry in _bodyFields.entries) ...[
        _statusField(
          entry.value.$1,
          entry.value.$2,
          allowNotCollected:
              entry.key == 'hipCm' && widget.questionnaire.version < 3,
        ),
        if (_statuses[entry.value.$2] == 'measured')
          _numberField(entry.key, entry.value.$1),
      ],
      for (final (label, systolic, diastolic, reason) in _pressureFields) ...[
        _statusField(label, reason),
        if (_statuses[reason] == 'measured') ...[
          _numberField(systolic, '$label systolic (mmHg)', integer: true),
          _numberField(
            diastolic,
            '$label diastolic (mmHg)',
            integer: true,
            systolicField: systolic,
          ),
        ],
      ],
      for (final entry in _reportedFields.entries)
        _numberField(
          entry.key,
          entry.value.$1,
          max: entry.value.$2,
          integer: entry.value.$3,
        ),
    ],
  );

  Widget _statusField(
    String label,
    String reason, {
    bool allowNotCollected = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: DropdownButtonFormField<String>(
      initialValue: _statuses[reason],
      isExpanded: true,
      decoration: InputDecoration(labelText: '$label status'),
      items: [
        if (allowNotCollected)
          const DropdownMenuItem(
            value: 'not_collected',
            child: Text('Not collected'),
          ),
        const DropdownMenuItem(value: 'measured', child: Text('Measured')),
        const DropdownMenuItem(
          value: 'unable',
          child: Text('Unable to measure'),
        ),
        const DropdownMenuItem(value: 'declined', child: Text('Declined')),
      ],
      onChanged: (value) => setState(() => _statuses[reason] = value!),
    ),
  );

  Widget _numberField(
    String field,
    String label, {
    bool integer = false,
    int? max,
    String? systolicField,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      controller: _inputs[field],
      keyboardType: TextInputType.numberWithOptions(decimal: !integer),
      decoration: InputDecoration(labelText: label),
      validator: (input) {
        final value = integer
            ? int.tryParse(input?.trim() ?? '')
            : double.tryParse(input?.trim() ?? '');
        if (value == null ||
            !value.isFinite ||
            (max == null ? value <= 0 : value < 0 || value > max)) {
          return max == null
              ? 'Enter a positive ${integer ? 'whole ' : ''}number.'
              : 'Enter a value from 0 to $max.';
        }
        if (systolicField != null) {
          final systolic = int.tryParse(_inputs[systolicField]!.text.trim());
          if (systolic != null && systolic <= value) {
            return 'Systolic must be greater than diastolic.';
          }
        }
        return null;
      },
    ),
  );
}
