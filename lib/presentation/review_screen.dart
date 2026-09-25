import 'package:flutter/material.dart';

import '../domain/ncd_questionnaire.dart';
import 'app_strings.dart';
import 'presentation_widgets.dart';
import 'view_models.dart';

class ReviewScreen extends StatelessWidget {
  const ReviewScreen({
    required this.participant,
    required this.visitNumber,
    this.questionnaire,
    this.optionalNote,
    this.onSubmit,
    this.isSubmitting = false,
    this.onEditParticipant,
    this.onBack,
    super.key,
  });

  final ParticipantDraft participant;
  final int visitNumber;
  final NcdQuestionnaire? questionnaire;
  final String? optionalNote;
  final VoidCallback? onSubmit;
  final bool isSubmitting;
  final VoidCallback? onEditParticipant;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final q = questionnaire;
    return ResponsivePage(
      appBar: AppBar(leading: BackButton(onPressed: onBack)),
      child: ListView(
        children: [
          const PageHeading(
            title: 'Review submission',
            subtitle: 'Check every answer before submitting.',
          ),
          _ReviewCard(
            title: 'Participant',
            onEdit: onEditParticipant,
            children: [
              _ReviewLine('Study ID', participant.studyId),
              _ReviewLine('Name', participant.name),
              _ReviewLine('Phone', participant.phone),
            ],
          ),
          const SizedBox(height: 12),
          _ReviewCard(
            title: 'Study and profile',
            children: [
              _ReviewLine('Visit number', '$visitNumber'),
              _ReviewLine('Study site', _answer(q, q?.studySite, _siteLabels)),
              _ReviewLine('Age', q == null ? _notCompleted : '${q.age} years'),
              _ReviewLine('Sex', _answer(q, q?.sex, _sexLabels)),
              _ReviewLine(
                'Education level',
                _answer(q, q?.education, _educationLabels),
              ),
              _ReviewLine(
                'Work category',
                _answer(q, q?.employment, _employmentLabels),
              ),
            ],
          ),
          _ReviewCard(
            title: 'Tobacco and alcohol',
            children: [
              _ReviewLine(
                'Tobacco use',
                _answer(q, q?.tobaccoUse, _tobaccoLabels),
              ),
              _ReviewLine(
                'Tobacco type',
                _conditionalAnswer(
                  q,
                  q?.tobaccoUse,
                  q?.tobaccoType,
                  _tobaccoTypeLabels,
                  activeWhen: 'current',
                ),
              ),
              _ReviewLine(
                'Tobacco frequency',
                _conditionalAnswer(
                  q,
                  q?.tobaccoUse,
                  q?.tobaccoFrequency,
                  _tobaccoFrequencyLabels,
                  activeWhen: 'current',
                ),
              ),
              _ReviewLine(
                'Alcohol in past 30 days',
                _answer(q, q?.alcoholPast30Days, _yesNoLabels),
              ),
              _ReviewLine(
                'Alcohol frequency',
                _conditionalAnswer(
                  q,
                  q?.alcoholPast30Days,
                  q?.alcoholFrequency,
                  _alcoholFrequencyLabels,
                  activeWhen: 'yes',
                ),
              ),
            ],
          ),
          _ReviewCard(
            title: 'Diet, activity and sleep',
            children: [
              _ReviewLine(
                'Fruit (past 7 days)',
                _answer(q, q?.fruitFrequency, _frequencyLabels),
              ),
              _ReviewLine(
                'Vegetables (past 7 days)',
                _answer(q, q?.vegetableFrequency, _frequencyLabels),
              ),
              _ReviewLine(
                'Sugary drinks (past 7 days)',
                _answer(q, q?.sugaryDrinkFrequency, _frequencyLabels),
              ),
              _ReviewLine(
                'Processed foods (past 7 days)',
                _answer(q, q?.processedFoodFrequency, _frequencyLabels),
              ),
              _ReviewLine(
                'Active days per week',
                q == null ? _notCompleted : '${q.activeDaysPerWeek} days',
              ),
              _ReviewLine(
                'Active minutes per day',
                q == null ? _notCompleted : '${q.activeMinutesPerDay} minutes',
              ),
              _ReviewLine(
                'Weekly active minutes',
                q == null ? _notCompleted : '${q.weeklyActiveMinutes} minutes',
              ),
              _ReviewLine(
                'Sleep per night',
                q == null ? _notCompleted : '${_number(q.sleepHours)} hours',
              ),
            ],
          ),
          _ReviewCard(
            title: 'Known diagnoses',
            children: [
              _ReviewLine(
                'Hypertension',
                _answer(q, q?.hypertensionDiagnosis, _diagnosisLabels),
              ),
              _ReviewLine(
                'Diabetes',
                _answer(q, q?.diabetesDiagnosis, _diagnosisLabels),
              ),
              _ReviewLine(
                'High cholesterol',
                _answer(q, q?.highCholesterolDiagnosis, _diagnosisLabels),
              ),
              _ReviewLine(
                'Cardiovascular disease',
                _answer(q, q?.cardiovascularDiagnosis, _diagnosisLabels),
              ),
            ],
          ),
          _ReviewCard(
            title: 'Physical measurements',
            children: [
              _ReviewLine(
                'Height',
                q == null
                    ? _notCompleted
                    : _measurementText(q.heightCm, q.heightMissingReason, 'cm'),
              ),
              _ReviewLine(
                'Weight',
                q == null
                    ? _notCompleted
                    : _measurementText(q.weightKg, q.weightMissingReason, 'kg'),
              ),
              _ReviewLine(
                'Waist circumference',
                q == null
                    ? _notCompleted
                    : _measurementText(q.waistCm, q.waistMissingReason, 'cm'),
              ),
              _ReviewLine(
                'BMI',
                q == null
                    ? _notCompleted
                    : q.bmi?.toStringAsFixed(1) ?? 'Not calculated',
              ),
              _ReviewLine(
                'Blood pressure reading 1',
                q == null
                    ? _notCompleted
                    : _bpText(
                        q.bpOneSystolic,
                        q.bpOneDiastolic,
                        q.bpOneMissingReason,
                      ),
              ),
              _ReviewLine(
                'Blood pressure reading 2',
                q == null
                    ? _notCompleted
                    : _bpText(
                        q.bpTwoSystolic,
                        q.bpTwoDiastolic,
                        q.bpTwoMissingReason,
                      ),
              ),
              _ReviewLine(
                'Average blood pressure',
                q == null
                    ? _notCompleted
                    : _averageBloodPressure(q),
              ),
            ],
          ),
          _ReviewCard(
            title: 'Optional Step 2',
            children: [
              _ReviewLine(
                'Optional note',
                optionalNote?.trim().isNotEmpty == true
                    ? optionalNote!.trim()
                    : 'Not provided',
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: isSubmitting ? null : onSubmit,
            icon: const Icon(Icons.check_circle_outline),
            label: Text(
              isSubmitting ? 'Saving...' : AppStrings.reviewAndSubmit,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

const _notCompleted = 'Not completed';
const _notAnswered = 'Not answered';

const _siteLabels = {
  'community_clinic': 'Community clinic',
  'community_outreach': 'Community outreach',
  'other_site': 'Other study site',
};
const _sexLabels = {'female': 'Female', 'male': 'Male', 'other': 'Other'};
const _educationLabels = {
  'none': 'No formal schooling',
  'primary': 'Primary',
  'secondary': 'Secondary',
  'higher': 'Higher education',
};
const _employmentLabels = {
  'employed': 'Employed',
  'self_employed': 'Self-employed',
  'student': 'Student',
  'homemaker': 'Homemaker/care work',
  'unemployed': 'Not currently employed',
  'retired': 'Retired',
};
const _tobaccoLabels = {
  'never': 'Never used',
  'former': 'Former user',
  'current': 'Current user',
};
const _tobaccoTypeLabels = {
  'smoked': 'Smoked',
  'smokeless': 'Smokeless',
  'both': 'Both',
};
const _tobaccoFrequencyLabels = {
  'daily': 'Daily',
  'less_than_daily': 'Less than daily',
};
const _alcoholFrequencyLabels = {
  'less_than_weekly': 'Less than weekly',
  'one_to_three_weekly': '1–3 days/week',
  'four_or_more_weekly': '4+ days/week',
};
const _yesNoLabels = {'yes': 'Yes', 'no': 'No'};
const _frequencyLabels = {
  'never': 'Never',
  'one_to_two_days': '1–2 days',
  'three_to_four_days': '3–4 days',
  'five_to_six_days': '5–6 days',
  'daily': 'Every day',
};
const _diagnosisLabels = {
  'yes': 'Yes',
  'no': 'No',
  'dont_know': 'Don’t know',
};

String _answer(
  NcdQuestionnaire? questionnaire,
  String? value,
  Map<String, String> labels,
) {
  if (questionnaire == null) return _notCompleted;
  if (value == null || value.isEmpty) return _notAnswered;
  return labels[value] ?? value;
}

String _conditionalAnswer(
  NcdQuestionnaire? questionnaire,
  String? controllingAnswer,
  String? value,
  Map<String, String> labels, {
  required String activeWhen,
}) {
  if (questionnaire == null) return _notCompleted;
  if (controllingAnswer == null || controllingAnswer.isEmpty) {
    return _notAnswered;
  }
  if (controllingAnswer != activeWhen) return 'Not applicable';
  if (value == null || value.isEmpty) return _notAnswered;
  return labels[value] ?? value;
}

String _number(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

String _measurementText(num? value, String? reason, String unit) =>
    value == null ? _missingText(reason) : '${_number(value.toDouble())} $unit';

String _bpText(int? systolic, int? diastolic, String? reason) =>
    systolic == null || diastolic == null
    ? _missingText(reason)
    : '$systolic / $diastolic mmHg';

String _averageBloodPressure(NcdQuestionnaire questionnaire) {
  final systolic = questionnaire.averageSystolic;
  final diastolic = questionnaire.averageDiastolic;
  if (systolic == null || diastolic == null) return 'Not calculated';
  return '${systolic.toStringAsFixed(0)} / '
      '${diastolic.toStringAsFixed(0)} mmHg';
}

String _missingText(String? reason) => switch (reason) {
  'declined' => 'Declined',
  'unable' => 'Unable to measure',
  _ => 'Not recorded',
};

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.title, required this.children, this.onEdit});

  final String title;
  final List<Widget> children;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (onEdit != null)
                TextButton(onPressed: onEdit, child: const Text('Edit')),
            ],
          ),
          const Divider(),
          ...children,
        ],
      ),
    ),
  );
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 130, child: Text(label)),
        Expanded(
          child: Text(value, style: Theme.of(context).textTheme.titleSmall),
        ),
      ],
    ),
  );
}
