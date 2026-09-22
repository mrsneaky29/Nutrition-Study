import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/ncd_questionnaire.dart';
import 'presentation_widgets.dart';

/// The custom study form intentionally records observations without scoring or
/// clinical interpretation. Empty sensitive fields are preserved as missing.
class NcdQuestionnaireScreen extends StatefulWidget {
  const NcdQuestionnaireScreen({this.onComplete, this.onBack, super.key});

  final ValueChanged<NcdQuestionnaire>? onComplete;
  final VoidCallback? onBack;

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
    setState(() => _measurements = true);
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
        heightCm: double.parse(_height.text),
        weightKg: double.parse(_weight.text),
        waistCm: double.parse(_waist.text),
        bpOneSystolic: int.parse(_bp1s.text),
        bpOneDiastolic: int.parse(_bp1d.text),
        bpTwoSystolic: int.parse(_bp2s.text),
        bpTwoDiastolic: int.parse(_bp2d.text),
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
            ? () => setState(() => _measurements = false)
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
          }, (v) => setState(() => _site = v)),
          _numberField(_age, 'Age (years)', min: 18, max: 120),
          _select('Sex', _sex, const {
            'female': 'Female',
            'male': 'Male',
            'other': 'Other',
          }, (v) => setState(() => _sex = v)),
          _select('Education level', _education, const {
            'none': 'No formal schooling',
            'primary': 'Primary',
            'secondary': 'Secondary',
            'higher': 'Higher education',
          }, (v) => setState(() => _education = v)),
          _select('Employment/work category', _employment, const {
            'employed': 'Employed',
            'self_employed': 'Self-employed',
            'student': 'Student',
            'homemaker': 'Homemaker/care work',
            'unemployed': 'Not currently employed',
            'retired': 'Retired',
          }, (v) => setState(() => _employment = v)),
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
            (v) => setState(() {
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
            }, (v) => setState(() => _tobaccoType = v)),
            _select('Tobacco frequency', _tobaccoFrequency, const {
              'daily': 'Daily',
              'less_than_daily': 'Less than daily',
            }, (v) => setState(() => _tobaccoFrequency = v)),
          ],
          _optionalSelect(
            'Alcohol use in the past 30 days',
            _alcohol,
            const {'no': 'No', 'yes': 'Yes'},
            (v) => setState(() {
              _alcohol = v;
              if (v != 'yes') _alcoholFrequency = null;
            }),
          ),
          if (_alcohol == 'yes')
            _select('Alcohol frequency', _alcoholFrequency, const {
              'less_than_weekly': 'Less than weekly',
              'one_to_three_weekly': '1–3 days/week',
              'four_or_more_weekly': '4+ days/week',
            }, (v) => setState(() => _alcoholFrequency = v)),
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
            (v) => setState(() => _fruit = v),
          ),
          _select(
            'Vegetables',
            _vegetables,
            _frequencyOptions,
            (v) => setState(() => _vegetables = v),
          ),
          _select(
            'Sugary drinks',
            _sugaryDrinks,
            _frequencyOptions,
            (v) => setState(() => _sugaryDrinks = v),
          ),
          _select(
            'Processed or packaged foods',
            _processedFood,
            _frequencyOptions,
            (v) => setState(() => _processedFood = v),
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
            (v) => setState(() => _hypertension = v),
          ),
          _optionalSelect(
            'Diabetes',
            _diabetes,
            _diagnosisOptions,
            (v) => setState(() => _diabetes = v),
          ),
          _optionalSelect(
            'High cholesterol',
            _cholesterol,
            _diagnosisOptions,
            (v) => setState(() => _cholesterol = v),
          ),
          _optionalSelect(
            'Cardiovascular disease',
            _cardiovascular,
            _diagnosisOptions,
            (v) => setState(() => _cardiovascular = v),
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
          _decimalField(_height, 'Height (cm)', min: 50, max: 250),
          _decimalField(_weight, 'Weight (kg)', min: 10, max: 350),
          _decimalField(_waist, 'Waist circumference (cm)', min: 30, max: 250),
        ]),
        _section(context, 'Blood pressure', [
          const Text('Record two seated readings in mmHg.'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _numberField(
                  _bp1s,
                  'Reading 1 systolic',
                  min: 50,
                  max: 300,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _numberField(
                  _bp1d,
                  'Reading 1 diastolic',
                  min: 30,
                  max: 200,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _numberField(
                  _bp2s,
                  'Reading 2 systolic',
                  min: 50,
                  max: 300,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _numberField(
                  _bp2d,
                  'Reading 2 diastolic',
                  min: 30,
                  max: 200,
                ),
              ),
            ],
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
