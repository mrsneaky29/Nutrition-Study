import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/ncd_questionnaire.dart';
import 'presentation_widgets.dart';

/// The custom study form intentionally records observations without scoring or
/// clinical interpretation. Empty sensitive fields are preserved as missing.
class NcdQuestionnaireScreen extends StatefulWidget {
  const NcdQuestionnaireScreen({
    this.onComplete,
    this.onBack,
    this.initialDraft,
    this.onDraftChanged,
    super.key,
  });

  final ValueChanged<NcdQuestionnaire>? onComplete;
  final VoidCallback? onBack;
  final Map<String, Object?>? initialDraft;
  final ValueChanged<Map<String, Object?>>? onDraftChanged;

  @override
  State<NcdQuestionnaireScreen> createState() => _NcdQuestionnaireScreenState();
}

class _NcdQuestionnaireScreenState extends State<NcdQuestionnaireScreen> {
  final _interviewKey = GlobalKey<FormState>();
  final _measurementsKey = GlobalKey<FormState>();
  final _activeDays = TextEditingController();
  final _age = TextEditingController();
  final _activeMinutes = TextEditingController();
  final _sleep = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _waist = TextEditingController();
  final _bp1s = TextEditingController();
  final _bp1d = TextEditingController();
  final _bp2s = TextEditingController();
  final _bp2d = TextEditingController();
  var _measurements = false;
  String? _site;
  String? _sex;
  String? _education;
  String? _employment;
  String? _fruit;
  String? _vegetables;
  String? _sugaryDrinks;
  String? _processedFood;
  String? _tobacco;
  String? _tobaccoType;
  String? _tobaccoFrequency;
  String? _alcohol;
  String? _alcoholFrequency;
  String? _hypertension;
  String? _diabetes;
  String? _cholesterol;
  String? _cardiovascular;
  String? _heightMissingReason;
  String? _weightMissingReason;
  String? _waistMissingReason;
  String? _bpOneMissingReason;
  String? _bpTwoMissingReason;

  @override
  void initState() {
    super.initState();
    final draft = widget.initialDraft ?? const <String, Object?>{};
    String? choice(String key) =>
        draft[key] is String ? draft[key] as String : null;
    String entry(String key) => choice(key) ?? '';
    _site = choice('site');
    _sex = choice('sex');
    _education = choice('education');
    _employment = choice('employment');
    _fruit = choice('fruit');
    _vegetables = choice('vegetables');
    _sugaryDrinks = choice('sugaryDrinks');
    _processedFood = choice('processedFood');
    _tobacco = choice('tobacco');
    _tobaccoType = choice('tobaccoType');
    _tobaccoFrequency = choice('tobaccoFrequency');
    _alcohol = choice('alcohol');
    _alcoholFrequency = choice('alcoholFrequency');
    _hypertension = choice('hypertension');
    _diabetes = choice('diabetes');
    _cholesterol = choice('cholesterol');
    _cardiovascular = choice('cardiovascular');
    _heightMissingReason = choice('heightMissingReason');
    _weightMissingReason = choice('weightMissingReason');
    _waistMissingReason = choice('waistMissingReason');
    _bpOneMissingReason = choice('bpOneMissingReason');
    _bpTwoMissingReason = choice('bpTwoMissingReason');
    _measurements = draft['measurements'] == true;
    final entries = <TextEditingController, String>{
      _age: 'age',
      _activeDays: 'activeDays',
      _activeMinutes: 'activeMinutes',
      _sleep: 'sleep',
      _height: 'height',
      _weight: 'weight',
      _waist: 'waist',
      _bp1s: 'bp1s',
      _bp1d: 'bp1d',
      _bp2s: 'bp2s',
      _bp2d: 'bp2d',
    };
    for (final entryItem in entries.entries) {
      entryItem.key.text = entry(entryItem.value);
      entryItem.key.addListener(_emitDraft);
    }
  }

  void _setDraft(VoidCallback change) {
    setState(change);
    _emitDraft();
  }

  void _emitDraft() => widget.onDraftChanged?.call({
    'measurements': _measurements,
    'site': _site,
    'age': _age.text,
    'sex': _sex,
    'education': _education,
    'employment': _employment,
    'fruit': _fruit,
    'vegetables': _vegetables,
    'sugaryDrinks': _sugaryDrinks,
    'processedFood': _processedFood,
    'tobacco': _tobacco,
    'tobaccoType': _tobaccoType,
    'tobaccoFrequency': _tobaccoFrequency,
    'alcohol': _alcohol,
    'alcoholFrequency': _alcoholFrequency,
    'activeDays': _activeDays.text,
    'activeMinutes': _activeMinutes.text,
    'sleep': _sleep.text,
    'hypertension': _hypertension,
    'diabetes': _diabetes,
    'cholesterol': _cholesterol,
    'cardiovascular': _cardiovascular,
    'height': _height.text,
    'weight': _weight.text,
    'waist': _waist.text,
    'bp1s': _bp1s.text,
    'bp1d': _bp1d.text,
    'bp2s': _bp2s.text,
    'bp2d': _bp2d.text,
    'heightMissingReason': _heightMissingReason,
    'weightMissingReason': _weightMissingReason,
    'waistMissingReason': _waistMissingReason,
    'bpOneMissingReason': _bpOneMissingReason,
    'bpTwoMissingReason': _bpTwoMissingReason,
  });

  @override
  void dispose() {
    for (final controller in [
      _age,
      _activeDays,
      _activeMinutes,
      _sleep,
      _height,
      _weight,
      _waist,
      _bp1s,
      _bp1d,
      _bp2s,
      _bp2d,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _next() {
    if (!(_interviewKey.currentState?.validate() ?? false)) return;
    _setDraft(() => _measurements = true);
  }

  void _complete() {
    if (!(_measurementsKey.currentState?.validate() ?? false)) return;
    widget.onComplete?.call(
      NcdQuestionnaire(
        studySite: _site!,
        age: int.parse(_age.text),
        sex: _sex!,
        education: _education!,
        employment: _employment!,
        fruitFrequency: _fruit!,
        vegetableFrequency: _vegetables!,
        sugaryDrinkFrequency: _sugaryDrinks!,
        processedFoodFrequency: _processedFood!,
        activeDaysPerWeek: int.parse(_activeDays.text),
        activeMinutesPerDay: int.parse(_activeMinutes.text),
        sleepHours: double.parse(_sleep.text),
        heightCm: _heightMissingReason == null
            ? double.parse(_height.text)
            : null,
        weightKg: _weightMissingReason == null
            ? double.parse(_weight.text)
            : null,
        waistCm: _waistMissingReason == null ? double.parse(_waist.text) : null,
        bpOneSystolic: _bpOneMissingReason == null
            ? int.parse(_bp1s.text)
            : null,
        bpOneDiastolic: _bpOneMissingReason == null
            ? int.parse(_bp1d.text)
            : null,
        bpTwoSystolic: _bpTwoMissingReason == null
            ? int.parse(_bp2s.text)
            : null,
        bpTwoDiastolic: _bpTwoMissingReason == null
            ? int.parse(_bp2d.text)
            : null,
        heightMissingReason: _heightMissingReason,
        weightMissingReason: _weightMissingReason,
        waistMissingReason: _waistMissingReason,
        bpOneMissingReason: _bpOneMissingReason,
        bpTwoMissingReason: _bpTwoMissingReason,
        tobaccoUse: _tobacco,
        tobaccoType: _tobacco == 'current' ? _tobaccoType : null,
        tobaccoFrequency: _tobacco == 'current' ? _tobaccoFrequency : null,
        alcoholPast30Days: _alcohol,
        alcoholFrequency: _alcohol == 'yes' ? _alcoholFrequency : null,
        hypertensionDiagnosis: _hypertension,
        diabetesDiagnosis: _diabetes,
        highCholesterolDiagnosis: _cholesterol,
        cardiovascularDiagnosis: _cardiovascular,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ResponsivePage(
    appBar: AppBar(
      leading: BackButton(
        onPressed: _measurements
            ? () => _setDraft(() => _measurements = false)
            : widget.onBack,
      ),
    ),
    child: _measurements
        ? _buildMeasurements(context)
        : _buildInterview(context),
  );

  Widget _buildInterview(BuildContext context) => Form(
    key: _interviewKey,
    child: ListView(
      children: [
        const PageHeading(
          title: 'NCD risk questionnaire',
          subtitle: 'Interview questions · 1 of 2. Leave sensitive answers blank if the participant declines.',
        ),
        _section(context, 'Study and profile', [
          _select('Study site', _site, const {
            'community_clinic': 'Community clinic',
            'community_outreach': 'Community outreach',
            'other_site': 'Other study site',
          }, (v) => _setDraft(() => _site = v)),
          _numberField(_age, 'Age (years)', min: 18, max: 120),
          _select('Sex', _sex, const {
            'female': 'Female',
            'male': 'Male',
            'other': 'Other',
          }, (v) => _setDraft(() => _sex = v)),
          _select('Education level', _education, const {
            'none': 'No formal schooling',
            'primary': 'Primary',
            'secondary': 'Secondary',
            'higher': 'Higher education',
          }, (v) => _setDraft(() => _education = v)),
          _select('Employment/work category', _employment, const {
            'employed': 'Employed',
            'self_employed': 'Self-employed',
            'student': 'Student',
            'homemaker': 'Homemaker/care work',
            'unemployed': 'Not currently employed',
            'retired': 'Retired',
          }, (v) => _setDraft(() => _employment = v)),
        ]),
        _section(context, 'Tobacco and alcohol', [
          _optionalSelect(
            'Tobacco use',
            _tobacco,
            const {
              'never': 'Never used',
              'former': 'Former user',
              'current': 'Current user',
            },
            (v) => _setDraft(() {
              _tobacco = v;
              if (v != 'current') {
                _tobaccoType = null;
                _tobaccoFrequency = null;
              }
            }),
          ),
          if (_tobacco == 'current') ...[
            _select('Type of tobacco', _tobaccoType, const {
              'smoked': 'Smoked',
              'smokeless': 'Smokeless',
              'both': 'Both',
            }, (v) => _setDraft(() => _tobaccoType = v)),
            _select('Tobacco frequency', _tobaccoFrequency, const {
              'daily': 'Daily',
              'less_than_daily': 'Less than daily',
            }, (v) => _setDraft(() => _tobaccoFrequency = v)),
          ],
          _optionalSelect(
            'Alcohol use in the past 30 days',
            _alcohol,
            const {'no': 'No', 'yes': 'Yes'},
            (v) => _setDraft(() {
              _alcohol = v;
              if (v != 'yes') _alcoholFrequency = null;
            }),
          ),
          if (_alcohol == 'yes')
            _select('Alcohol frequency', _alcoholFrequency, const {
              'less_than_weekly': 'Less than weekly',
              'one_to_three_weekly': '1–3 days/week',
              'four_or_more_weekly': '4+ days/week',
            }, (v) => _setDraft(() => _alcoholFrequency = v)),
        ]),
        _section(context, 'Diet, activity and sleep', [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'In the past 7 days, how often did the participant have:',
            ),
          ),
          _select(
            'Fruit',
            _fruit,
            _frequencyOptions,
            (v) => _setDraft(() => _fruit = v),
          ),
          _select(
            'Vegetables',
            _vegetables,
            _frequencyOptions,
            (v) => _setDraft(() => _vegetables = v),
          ),
          _select(
            'Sugary drinks',
            _sugaryDrinks,
            _frequencyOptions,
            (v) => _setDraft(() => _sugaryDrinks = v),
          ),
          _select(
            'Processed or packaged foods',
            _processedFood,
            _frequencyOptions,
            (v) => _setDraft(() => _processedFood = v),
          ),
          _numberField(
            _activeDays,
            'Active days per week',
            max: 7,
            helper: 'Moderate-or-higher activity',
          ),
          _numberField(
            _activeMinutes,
            'Usual active minutes per day',
            max: 1440,
          ),
          _decimalField(_sleep, 'Usual sleep hours per night', max: 24),
        ]),
        _section(context, 'Known diagnosis', [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Has a doctor or health professional ever told the participant they have:',
            ),
          ),
          _optionalSelect(
            'Hypertension',
            _hypertension,
            _diagnosisOptions,
            (v) => _setDraft(() => _hypertension = v),
          ),
          _optionalSelect(
            'Diabetes',
            _diabetes,
            _diagnosisOptions,
            (v) => _setDraft(() => _diabetes = v),
          ),
          _optionalSelect(
            'High cholesterol',
            _cholesterol,
            _diagnosisOptions,
            (v) => _setDraft(() => _cholesterol = v),
          ),
          _optionalSelect(
            'Cardiovascular disease',
            _cardiovascular,
            _diagnosisOptions,
            (v) => _setDraft(() => _cardiovascular = v),
          ),
        ]),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _next,
          child: const Text('Continue to measurements'),
        ),
        const SizedBox(height: 32),
      ],
    ),
  );

  Widget _buildMeasurements(BuildContext context) => Form(
    key: _measurementsKey,
    child: ListView(
      children: [
        const PageHeading(
          title: 'Physical measurements',
          subtitle:
              'Measurements · 2 of 2. Record both blood-pressure readings.',
        ),
        _section(context, 'Body measurements', [
          _measurementDecimal(
            'Height (cm)',
            _height,
            _heightMissingReason,
            (v) => _setDraft(() => _heightMissingReason = v),
            min: 50,
            max: 250,
          ),
          _measurementDecimal(
            'Weight (kg)',
            _weight,
            _weightMissingReason,
            (v) => _setDraft(() => _weightMissingReason = v),
            min: 10,
            max: 350,
          ),
          _measurementDecimal(
            'Waist circumference (cm)',
            _waist,
            _waistMissingReason,
            (v) => _setDraft(() => _waistMissingReason = v),
            min: 30,
            max: 250,
          ),
        ]),
        _section(context, 'Blood pressure', [
          const Text('Record two seated readings in mmHg.'),
          const SizedBox(height: 12),
          _bloodPressureMeasurement(
            'Reading 1',
            _bp1s,
            _bp1d,
            _bpOneMissingReason,
            (v) => _setDraft(() => _bpOneMissingReason = v),
          ),
          _bloodPressureMeasurement(
            'Reading 2',
            _bp2s,
            _bp2d,
            _bpTwoMissingReason,
            (v) => _setDraft(() => _bpTwoMissingReason = v),
          ),
        ]),
        FilledButton(
          onPressed: _complete,
          child: const Text('Review questionnaire'),
        ),
        const SizedBox(height: 32),
      ],
    ),
  );

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      );

  Widget _measurementStatus(
    String label,
    String? reason,
    ValueChanged<String?> changed,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      initialValue: reason ?? 'recorded',
      decoration: InputDecoration(labelText: '$label status'),
      items: const [
        DropdownMenuItem(value: 'recorded', child: Text('Measured')),
        DropdownMenuItem(value: 'unable', child: Text('Unable to measure')),
        DropdownMenuItem(value: 'declined', child: Text('Declined')),
      ],
      onChanged: (value) => changed(value == 'recorded' ? null : value),
    ),
  );

  Widget _measurementDecimal(
    String label,
    TextEditingController controller,
    String? reason,
    ValueChanged<String?> changed, {
    required double min,
    required double max,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _measurementStatus(label, reason, changed),
      if (reason == null) _decimalField(controller, label, min: min, max: max),
    ],
  );

  Widget _bloodPressureMeasurement(
    String label,
    TextEditingController systolic,
    TextEditingController diastolic,
    String? reason,
    ValueChanged<String?> changed,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _measurementStatus(label, reason, changed),
      if (reason == null)
        Row(
          children: [
            Expanded(
              child: _numberField(
                systolic,
                '$label systolic',
                min: 50,
                max: 300,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numberField(
                diastolic,
                '$label diastolic',
                min: 30,
                max: 200,
              ),
            ),
          ],
        ),
    ],
  );

  Widget _select(
    String label,
    String? value,
    Map<String, String> options,
    ValueChanged<String?> changed,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: options.entries
          .map(
            (item) => DropdownMenuItem(
              value: item.key,
              child: Text(item.value, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: changed,
      validator: (v) => v == null ? 'Select an answer.' : null,
    ),
  );
  Widget _optionalSelect(
    String label,
    String? value,
    Map<String, String> options,
    ValueChanged<String?> changed,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        helperText: 'Optional — leave blank if declined.',
      ),
      items: [
        const DropdownMenuItem<String>(
          value: null,
          child: Text('Not answered', overflow: TextOverflow.ellipsis),
        ),
        ...options.entries.map(
          (item) => DropdownMenuItem(
            value: item.key,
            child: Text(item.value, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: changed,
    ),
  );
  Widget _numberField(
    TextEditingController controller,
    String label, {
    int min = 0,
    int? max,
    String? helper,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, helperText: helper),
      validator: (v) {
        final n = int.tryParse(v ?? '');
        return n == null || n < min || (max != null && n > max)
            ? 'Enter a value${max == null ? '' : ' from $min to $max'}.'
            : null;
      },
    ),
  );
  Widget _decimalField(
    TextEditingController controller,
    String label, {
    double min = 0,
    double? max,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      validator: (v) {
        final n = double.tryParse(v ?? '');
        return n == null || n < min || (max != null && n > max)
            ? 'Enter a value${max == null ? '' : ' from $min to $max'}.'
            : null;
      },
    ),
  );
}

const _frequencyOptions = {
  'never': 'Never',
  'one_to_two_days': '1–2 days',
  'three_to_four_days': '3–4 days',
  'five_to_six_days': '5–6 days',
  'daily': 'Every day',
};
const _diagnosisOptions = {'yes': 'Yes', 'no': 'No', 'dont_know': 'Don’t know'};
