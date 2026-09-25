import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'presentation_widgets.dart';
import 'view_models.dart';
import '../domain/ncd_questionnaire.dart';

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
  Widget build(BuildContext context) => ResponsivePage(
    appBar: AppBar(leading: BackButton(onPressed: onBack)),
    child: ListView(
      children: [
        const PageHeading(
          title: 'Review submission',
          subtitle: 'Confirm the administrative details before submitting.',
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
        const SizedBox(height: 16),
        _ReviewCard(
          title: 'Questionnaire',
          children: [
            _ReviewLine('Visit number', '$visitNumber'),
            _ReviewLine(
              'Study site',
              questionnaire?.studySite ?? 'Not recorded',
            ),
            _ReviewLine(
              'Height',
              _measurementText(
                questionnaire?.heightCm,
                questionnaire?.heightMissingReason,
                'cm',
              ),
            ),
            _ReviewLine(
              'Weight',
              _measurementText(
                questionnaire?.weightKg,
                questionnaire?.weightMissingReason,
                'kg',
              ),
            ),
            _ReviewLine(
              'Waist',
              _measurementText(
                questionnaire?.waistCm,
                questionnaire?.waistMissingReason,
                'cm',
              ),
            ),
            _ReviewLine(
              'BMI',
              questionnaire?.bmi?.toStringAsFixed(1) ?? 'Not calculated',
            ),
            _ReviewLine(
              'BP reading 1',
              _bpText(
                questionnaire?.bpOneSystolic,
                questionnaire?.bpOneDiastolic,
                questionnaire?.bpOneMissingReason,
              ),
            ),
            _ReviewLine(
              'BP reading 2',
              _bpText(
                questionnaire?.bpTwoSystolic,
                questionnaire?.bpTwoDiastolic,
                questionnaire?.bpTwoMissingReason,
              ),
            ),
            _ReviewLine(
              'Average blood pressure',
              questionnaire?.averageSystolic == null ||
                      questionnaire?.averageDiastolic == null
                  ? 'Not calculated'
                  : '${questionnaire!.averageSystolic!.toStringAsFixed(0)} / ${questionnaire!.averageDiastolic!.toStringAsFixed(0)} mmHg',
            ),
            _ReviewLine(
              'Weekly active minutes',
              questionnaire?.weeklyActiveMinutes.toString() ?? 'Not recorded',
            ),
            _ReviewLine('Optional Step 2', optionalNote ?? 'Not provided'),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: isSubmitting ? null : onSubmit,
          icon: const Icon(Icons.check_circle_outline),
          label: Text(isSubmitting ? 'Saving...' : AppStrings.reviewAndSubmit),
        ),
      ],
    ),
  );
}

String _measurementText(num? value, String? reason, String unit) =>
    value == null ? _missingText(reason) : '$value $unit';

String _bpText(int? systolic, int? diastolic, String? reason) =>
    systolic == null || diastolic == null
    ? _missingText(reason)
    : '$systolic / $diastolic mmHg';

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
