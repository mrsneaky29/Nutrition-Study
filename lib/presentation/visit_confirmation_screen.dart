import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'presentation_widgets.dart';
import 'view_models.dart';

class VisitConfirmationScreen extends StatelessWidget {
  const VisitConfirmationScreen({
    required this.participant,
    required this.proposedVisitNumber,
    this.onConfirm,
    this.onBack,
    super.key,
  });

  final ParticipantDraft participant;
  final int proposedVisitNumber;
  final VoidCallback? onConfirm;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => ResponsivePage(
    appBar: AppBar(leading: BackButton(onPressed: onBack)),
    child: ListView(
      children: [
        const PageHeading(
          title: 'Confirm visit',
          subtitle:
              'Check the automatically assigned participant and visit numbers.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Detail(
                  label: 'Participant number',
                  value: participant.studyId,
                ),
                _Detail(
                  label: AppStrings.participantName,
                  value: participant.name,
                ),
                _Detail(
                  label: AppStrings.phoneNumber,
                  value: participant.phone,
                ),
                const Divider(height: 32),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                    child: Text('$proposedVisitNumber'),
                  ),
                  title: Text(
                    proposedVisitNumber == 1
                        ? 'First visit'
                        : 'Visit $proposedVisitNumber',
                  ),
                  subtitle: Text(
                    proposedVisitNumber == 1
                        ? 'A new participant number has been assigned.'
                        : 'Updated automatically from this participant’s history.',
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onConfirm,
                  child: const Text('Confirm and continue'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}
