import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'presentation_widgets.dart';
import 'view_models.dart';
import '../domain/ncd_questionnaire.dart';

class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({
    required this.submission,
    this.questionnaire,
    this.onDone,
    this.onViewSubmission,
    super.key,
  });

  final SubmissionSummary submission;
  final NcdQuestionnaire? questionnaire;
  final VoidCallback? onDone;
  final VoidCallback? onViewSubmission;

  @override
  Widget build(BuildContext context) => ResponsivePage(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  AppStrings.receipt,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Visit ${submission.visitNumber} for ${submission.participantName} is saved.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                _ReceiptRow(label: 'Submission ID', value: submission.id),
                _ReceiptRow(label: 'Study ID', value: submission.studyId),
                if (questionnaire case final values?) ...[
                  _ReceiptRow(
                    label: 'BMI',
                    value: values.bmi.toStringAsFixed(1),
                  ),
                  _ReceiptRow(
                    label: 'Average blood pressure',
                    value: '${values.averageSystolic.toStringAsFixed(0)} / ${values.averageDiastolic.toStringAsFixed(0)} mmHg',
                  ),
                ],
                const Divider(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(child: Text('Sync status')),
                    StatusChip(state: submission.syncState),
                  ],
                ),
                if (submission.syncState == SyncState.pending) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'This entry remains safely stored on this device and will sync when available.',
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onDone,
                    child: const Text('Return home'),
                  ),
                ),
                TextButton(
                  onPressed: onViewSubmission,
                  child: const Text('View submission'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      ],
    ),
  );
}
