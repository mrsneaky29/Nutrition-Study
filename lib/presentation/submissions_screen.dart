import 'package:flutter/material.dart';

import 'presentation_widgets.dart';
import 'view_models.dart';

class MySubmissionsScreen extends StatefulWidget {
  const MySubmissionsScreen({
    required this.submissions,
    this.onOpen,
    this.onBack,
    super.key,
  });

  final List<SubmissionSummary> submissions;
  final ValueChanged<SubmissionSummary>? onOpen;
  final VoidCallback? onBack;

  @override
  State<MySubmissionsScreen> createState() => _MySubmissionsScreenState();
}

class _MySubmissionsScreenState extends State<MySubmissionsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final visible = widget.submissions.where((item) {
      final query = _query.toLowerCase();
      return item.participantName.toLowerCase().contains(query) ||
          item.studyId.toLowerCase().contains(query);
    }).toList();
    return ResponsivePage(
      appBar: AppBar(leading: BackButton(onPressed: widget.onBack)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeading(
            title: 'My submissions',
            subtitle: 'Entries created by your account.',
          ),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by name or Study ID',
            ),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: visible.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off_outlined,
                    title: 'No matching submissions',
                    message: 'Try a different search or create a new participant entry.',
                  )
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      return Card(
                        child: ListTile(
                          onTap: () => widget.onOpen?.call(item),
                          title: Text(item.participantName),
                          subtitle: Text(
                            '${item.studyId} · Visit ${item.visitNumber}',
                          ),
                          trailing: StatusChip(state: item.syncState),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class SubmissionDetailScreen extends StatelessWidget {
  const SubmissionDetailScreen({
    required this.submission,
    this.onEdit,
    this.onBack,
    super.key,
  });

  final SubmissionSummary submission;
  final VoidCallback? onEdit;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => ResponsivePage(
    appBar: AppBar(
      leading: BackButton(onPressed: onBack),
      actions: [
        TextButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit'),
        ),
      ],
    ),
    child: ListView(
      children: [
        PageHeading(
          title: submission.participantName,
          subtitle: '${submission.studyId} · Visit ${submission.visitNumber}',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Submission details',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _DetailLine('Submission ID', submission.id),
                _DetailLine('Recorded', '${submission.submittedAt.toLocal()}'),
                const Divider(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Sync status'),
                    StatusChip(state: submission.syncState),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit submission'),
        ),
      ],
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
