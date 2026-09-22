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
            _ReviewLine('Study site', questionnaire?.studySite ?? 'Not recorded'),
            _ReviewLine('Height', questionnaire == null ? 'Not recorded' : '${questionnaire!.heightCm} cm'),
            _ReviewLine('Weight', questionnaire == null ? 'Not recorded' : '${questionnaire!.weightKg} kg'),
            _ReviewLine('Waist', questionnaire == null ? 'Not recorded' : '${questionnaire!.waistCm} cm'),
            _ReviewLine('BMI', questionnaire == null ? 'Not recorded' : questionnaire!.bmi.toStringAsFixed(1)),
            _ReviewLine('BP reading 1', questionnaire == null ? 'Not recorded' : '${questionnaire!.bpOneSystolic} / ${questionnaire!.bpOneDiastolic} mmHg'),
            _ReviewLine('BP reading 2', questionnaire == null ? 'Not recorded' : '${questionnaire!.bpTwoSystolic} / ${questionnaire!.bpTwoDiastolic} mmHg'),
            _ReviewLine('Average blood pressure', questionnaire == null ? 'Not recorded' : '${questionnaire!.averageSystolic.toStringAsFixed(0)} / ${questionnaire!.averageDiastolic.toStringAsFixed(0)} mmHg'),
            _ReviewLine('Weekly active minutes', questionnaire?.weeklyActiveMinutes.toString() ?? 'Not recorded'),
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
