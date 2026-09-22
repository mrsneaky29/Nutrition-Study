import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'presentation_widgets.dart';
import 'view_models.dart';

class CollectorHomeScreen extends StatelessWidget {
  const CollectorHomeScreen({
    required this.collectorName,
    this.pendingCount = 0,
    this.recentSubmissions = const [],
    this.onStartEntry,
    this.onOpenSubmissions,
    this.onOpenSubmission,
    this.onRetryPending,
    this.isRetrying = false,
    this.onSignOut,
    super.key,
  });

  final String collectorName;
  final int pendingCount;
  final List<SubmissionSummary> recentSubmissions;
  final VoidCallback? onStartEntry;
  final VoidCallback? onOpenSubmissions;
  final ValueChanged<SubmissionSummary>? onOpenSubmission;
  final Future<void> Function()? onRetryPending;
  final bool isRetrying;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) => ResponsivePage(
    appBar: AppBar(
      title: const Text(AppStrings.appName),
      actions: [
        IconButton(
          tooltip: 'Retry pending sync',
          onPressed: pendingCount == 0 || isRetrying
              ? null
              : () => onRetryPending?.call(),
          icon: isRetrying
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
        ),
        IconButton(
          tooltip: AppStrings.signOut,
          onPressed: onSignOut,
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    floatingActionButton: SizedBox(
      height: 64,
      child: FloatingActionButton.extended(
        onPressed: onStartEntry,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 26),
        icon: const Icon(Icons.person_add_alt_1, size: 26),
        label: const Text(
          'New participant',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    child: ListView(
      children: [
        PageHeading(
          title: 'Hello, $collectorName',
          subtitle: 'Start a visit or return to one of your saved submissions.',
        ),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.cloud_queue_outlined,
                label: 'Awaiting sync',
                value: '$pendingCount',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                icon: Icons.assignment_turned_in_outlined,
                label: 'Recent submissions',
                value: '${recentSubmissions.length}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Recent activity',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(
              onPressed: onOpenSubmissions,
              child: const Text('View all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (recentSubmissions.isEmpty)
          EmptyState(
            icon: Icons.folder_open_outlined,
            title: 'No submissions yet',
            message: 'Your completed and saved visits will appear here.',
          )
        else
          ...recentSubmissions.map(
            (submission) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => onOpenSubmission?.call(submission),
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(submission.participantName),
                subtitle: Text(
                  '${submission.studyId} · Visit ${submission.visitNumber}',
                ),
                trailing: StatusChip(state: submission.syncState),
              ),
            ),
          ),
        const SizedBox(height: 72),
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Row(
        children: [
          Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: Theme.of(context).textTheme.headlineSmall),
                Text(label),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
