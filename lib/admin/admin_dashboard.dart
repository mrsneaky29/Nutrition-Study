import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/visit_repository.dart';
import '../domain/authenticated_user.dart';
import '../domain/measurement.dart';
import '../domain/participant_id.dart';
import '../domain/participant_profile.dart';
import '../domain/study_configuration.dart';
import '../domain/visit_record.dart';
import 'local_api_visit_repository.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({
    required this.repository,
    required this.admin,
    this.conflictRepository,
    super.key,
  });

  final VisitRepository repository;
  final AuthenticatedUser admin;
  final ServerConflictRepository? conflictRepository;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  List<VisitRecord>? _records;
  String? _recordsSignature;
  Object? _initialLoadError;
  Object? _connectionError;
  DateTime? _lastSuccessfulLoad;
  bool _isRefreshing = false;
  Timer? _poller;
  String _query = '';
  _RecordFilter _filter = _RecordFilter.all;

  List<Map<String, dynamic>> _serverConflicts = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _poller = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<List<VisitRecord>> _loadRecords() =>
      widget.repository.listVisibleTo(widget.admin);

  ServerConflictRepository? get _conflictRepo {
    if (widget.conflictRepository != null) return widget.conflictRepository;
    if (widget.repository is ServerConflictRepository) {
      return widget.repository as ServerConflictRepository;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _loadServerConflicts() async {
    final repo = _conflictRepo;
    if (repo != null) {
      try {
        return await repo.listConflicts();
      } catch (_) {
        return const [];
      }
    }
    try {
      final dynamic dynamicRepo = widget.repository;
      final result = await dynamicRepo.listConflicts();
      if (result is List) {
        return result
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final records = await _loadRecords();
      final conflicts = await _loadServerConflicts();
      if (!mounted) return;
      final signature = _signatureFor(records);
      _lastSuccessfulLoad = DateTime.now();
      if (_recordsSignature != signature ||
          _initialLoadError != null ||
          _connectionError != null ||
          _serverConflicts.length != conflicts.length ||
          _serverConflicts.toString() != conflicts.toString()) {
        setState(() {
          _records = records;
          _recordsSignature = signature;
          _serverConflicts = conflicts;
          _initialLoadError = null;
          _connectionError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        if (_records == null) {
          setState(() => _initialLoadError = error);
        } else if (_connectionError == null) {
          setState(() => _connectionError = error);
        }
      }
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _reviewConflict(String conflictId, {String? notes}) async {
    final repo = _conflictRepo;
    try {
      if (repo != null) {
        await repo.reviewConflict(conflictId, notes: notes);
      } else {
        final dynamic dynamicRepo = widget.repository;
        await dynamicRepo.reviewConflict(conflictId, notes: notes);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conflict marked as reviewed.')),
        );
        await _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to review conflict: $e')),
        );
      }
    }
  }

  Future<void> _resolveConflict(
    String conflictId,
    Map<String, dynamic> resolution,
  ) async {
    final repo = _conflictRepo;
    try {
      if (repo != null) {
        await repo.resolveConflict(conflictId, resolution);
      } else {
        final dynamic dynamicRepo = widget.repository;
        await dynamicRepo.resolveConflict(conflictId, resolution);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conflict resolved successfully.')),
        );
        await _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resolve conflict: $e')),
        );
      }
    }
  }

  String _signatureFor(List<VisitRecord> records) => records
      .map(
        (record) =>
            '${record.id}:${record.revision}:'
            '${record.updatedAt.microsecondsSinceEpoch}:${record.isArchived}',
      )
      .join('|');

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    return Scaffold(
      body: records == null
          ? _initialLoadError == null
                ? const Center(child: CircularProgressIndicator())
                : _LoadFailure(
                    message: _initialLoadError.toString(),
                    onRetry: _refresh,
                  )
          : _DashboardContent(
              records: records,
              serverConflicts: _serverConflicts,
              connectionError: _connectionError,
              lastSuccessfulLoad: _lastSuccessfulLoad,
              query: _query,
              filter: _filter,
              onQueryChanged: (value) => setState(() => _query = value.trim()),
              onFilterChanged: (value) => setState(() => _filter = value),
              onRefresh: _refresh,
              onReviewConflict: _reviewConflict,
              onResolveConflict: _resolveConflict,
              onArchivePolicy: () => _showArchivePolicy(context),
              onRecordSelected: (record) => _showRecord(
                context,
                record,
                readOnly: _connectionError != null,
              ),
              onExport: _connectionError == null
                  ? () => _copyCsv(context, records)
                  : null,
            ),
    );
  }

  void _showArchivePolicy(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.inventory_2_outlined),
        title: const Text('Archive-safe records'),
        content: const Text(
          'Archiving removes a visit from the active operational queue but '
          'never deletes it. Administrators can restore archived visits here; '
          'every archive change stays with the retained record.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  void _showRecord(
    BuildContext context,
    VisitRecord record, {
    required bool readOnly,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _RecordDetails(
        record: record,
        readOnly: readOnly,
        onEdit: () {
          Navigator.of(sheetContext).pop();
          _editRecord(context, record);
        },
        onArchiveToggle: () => _toggleArchive(sheetContext, record),
      ),
    );
  }

  Future<void> _editRecord(BuildContext context, VisitRecord record) async {
    final amended = await showModalBottomSheet<VisitRecord>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _RecordEditSheet(record: record),
    );
    if (amended == null) return;
    try {
      await widget.repository.saveAdminRecord(
        actor: widget.admin,
        record: amended,
      );
      if (!mounted || !context.mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Visit ${record.participant.studyId} updated.')),
      );
    } catch (_) {
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The edit could not be saved. The original record is unchanged.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleArchive(
    BuildContext sheetContext,
    VisitRecord record,
  ) async {
    final action = record.isArchived ? 'restore' : 'archive';
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          record.isArchived
              ? Icons.unarchive_outlined
              : Icons.inventory_2_outlined,
        ),
        title: Text('${record.isArchived ? 'Restore' : 'Archive'} visit?'),
        content: Text(
          record.isArchived
              ? 'This restores the visit to the active operational queue. The original record remains intact.'
              : 'This removes the visit from the active operational queue but retains it for administrators. Nothing is permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(record.isArchived ? 'Restore visit' : 'Archive visit'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.setArchived(
        actor: widget.admin,
        visitId: record.id,
        archived: !record.isArchived,
      );
      if (!mounted || !sheetContext.mounted) return;
      Navigator.of(sheetContext).pop();
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Visit ${record.participant.studyId} ${action}d.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The archive change could not be saved. No record was deleted.',
          ),
        ),
      );
    }
  }

  Future<void> _copyCsv(BuildContext context, List<VisitRecord> records) async {
    String quote(String value) => '"${value.replaceAll('"', '""')}"';
    const baseHeaders = [
      'visit_id',
      'study_id',
      'collector_id',
      'visit_number',
      'visit_status',
      'sync_state',
      'updated_at',
    ];
    final questionnaireHeaders =
        records
            .expand(
              (record) =>
                  record.questionnaire?.toCsvRow().keys ?? const <String>[],
            )
            .toSet()
            .toList()
          ..sort();
    final headers = [...baseHeaders, ...questionnaireHeaders];
    final csv = <String>[
      headers.join(','),
      ...records.map((record) {
        final row = <String, String>{
          'visit_id': record.id,
          'study_id': record.participant.studyId,
          'collector_id': record.collectorId,
          'visit_number': '${record.visitNumber}',
          'visit_status': record.status.name,
          'sync_state': record.syncState.name,
          'updated_at': record.updatedAt.toUtc().toIso8601String(),
          ...?record.questionnaire?.toCsvRow(),
        };
        return headers.map((header) => quote(row[header] ?? '')).join(',');
      }),
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: csv));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Current record view copied as CSV.')),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.records,
    required this.serverConflicts,
    required this.connectionError,
    required this.lastSuccessfulLoad,
    required this.query,
    required this.filter,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.onReviewConflict,
    required this.onResolveConflict,
    required this.onArchivePolicy,
    required this.onRecordSelected,
    required this.onExport,
  });

  final List<VisitRecord> records;
  final List<Map<String, dynamic>> serverConflicts;
  final Object? connectionError;
  final DateTime? lastSuccessfulLoad;
  final String query;
  final _RecordFilter filter;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_RecordFilter> onFilterChanged;
  final VoidCallback onRefresh;
  final ValueChanged<String>? onReviewConflict;
  final void Function(String id, Map<String, dynamic> resolution)?
  onResolveConflict;
  final VoidCallback onArchivePolicy;
  final ValueChanged<VisitRecord> onRecordSelected;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final filtered = records.where((record) {
      final haystack = [
        record.id,
        record.participant.studyId,
        record.participant.name,
        record.participant.indianPhone,
        record.collectorId,
      ].join(' ').toLowerCase();
      return haystack.contains(query.toLowerCase()) && filter.matches(record);
    }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final stats = _RecordStats(records);
    final compact = MediaQuery.sizeOf(context).width < 900;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              compact ? 20 : 42,
              28,
              compact ? 20 : 42,
              40,
            ),
            sliver: SliverList.list(
              children: [
                _TopBar(onRefresh: onRefresh, onArchivePolicy: onArchivePolicy),
                if (connectionError != null) ...[
                  const SizedBox(height: 18),
                  _OfflineSnapshotNotice(
                    error: connectionError!,
                    lastSuccessfulLoad: lastSuccessfulLoad,
                    onRetry: onRefresh,
                  ),
                ],
                if (stats.conflicts > 0 || serverConflicts.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _ConflictNotice(
                    conflictCount: serverConflicts.isNotEmpty
                        ? serverConflicts.length
                        : stats.conflicts,
                    onFilterConflicts: () =>
                        onFilterChanged(_RecordFilter.conflicts),
                  ),
                ],
                const SizedBox(height: 36),
                const Text(
                  'Study operations',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A browser workspace for submitted and in-progress visits.',
                  style: TextStyle(color: Color(0xFF667085), fontSize: 16),
                ),
                const SizedBox(height: 28),
                _StatsGrid(stats: stats),
                const SizedBox(height: 32),
                _RecordsPanel(
                  records: filtered,
                  totalCount: records.length,
                  query: query,
                  filter: filter,
                  onQueryChanged: onQueryChanged,
                  onFilterChanged: onFilterChanged,
                  onRecordSelected: onRecordSelected,
                  onExport: onExport,
                ),
                const SizedBox(height: 22),
                _ArchiveNotice(onTap: onArchivePolicy),
                const SizedBox(height: 28),
                _ServerConflictInbox(
                  conflicts: serverConflicts,
                  onReview: onReviewConflict,
                  onResolve: onResolveConflict,
                  onRefresh: onRefresh,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: const Color(0xFF7EA2FF),
      borderRadius: BorderRadius.circular(11),
    ),
    child: const Icon(Icons.insights_rounded, color: Color(0xFF10224B)),
  );
}

class _ConflictNotice extends StatelessWidget {
  const _ConflictNotice({
    required this.conflictCount,
    required this.onFilterConflicts,
  });

  final int conflictCount;
  final VoidCallback onFilterConflicts;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFDE8E8),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFCC4B4B)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$conflictCount sync conflict${conflictCount == 1 ? '' : 's'} detected',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF9B1C1C),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Record conflicts occurred during collector synchronization (e.g. mismatched participant ID or phone). Select a record to inspect and edit.',
                  style: TextStyle(color: Color(0xFF771D1D), fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: onFilterConflicts,
            child: const Text('View conflicts'),
          ),
        ],
      ),
    ),
  );
}

class _OfflineSnapshotNotice extends StatelessWidget {
  const _OfflineSnapshotNotice({
    required this.error,
    required this.lastSuccessfulLoad,
    required this.onRetry,
  });

  final Object error;
  final DateTime? lastSuccessfulLoad;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFFF4DE),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: Color(0xFF795500)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Could not refresh — showing last loaded records',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  'Last connected ${lastSuccessfulLoad == null ? 'earlier' : _fullDate(lastSuccessfulLoad!)}. '
                  'Records may have changed. Editing, archiving, and export are paused until the server reconnects.',
                ),
                Text(error.toString()),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onRefresh, required this.onArchivePolicy});
  final VoidCallback onRefresh;
  final VoidCallback onArchivePolicy;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const _LogoMark(),
      const SizedBox(width: 10),
      const Expanded(
        child: Text(
          'Study Admin',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      IconButton(
        tooltip: 'Refresh records',
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh_rounded),
      ),
      IconButton(
        tooltip: 'Archive policy',
        onPressed: onArchivePolicy,
        icon: const Icon(Icons.inventory_2_outlined),
      ),
      const SizedBox(width: 6),
      const CircleAvatar(
        radius: 18,
        backgroundColor: Color(0xFFE0E8FF),
        child: Icon(Icons.person_outline, color: Color(0xFF2855D9)),
      ),
    ],
  );
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});
  final _RecordStats stats;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1200
          ? 6
          : constraints.maxWidth >= 800
          ? 3
          : constraints.maxWidth >= 580
          ? 2
          : 1;
      const gap = 14.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          _MetricCard(
            width: width,
            label: 'Total visits',
            value: '${stats.total}',
            icon: Icons.assignment_outlined,
            color: const Color(0xFF2855D9),
          ),
          _MetricCard(
            width: width,
            label: 'Submitted',
            value: '${stats.submitted}',
            icon: Icons.check_circle_outline,
            color: const Color(0xFF16866D),
          ),
          _MetricCard(
            width: width,
            label: 'Needs sync',
            value: '${stats.needsSync}',
            icon: Icons.sync_problem_outlined,
            color: const Color(0xFFE08A24),
          ),
          _MetricCard(
            width: width,
            label: 'Sync conflicts',
            value: '${stats.conflicts}',
            icon: Icons.error_outline,
            color: const Color(0xFFCC4B4B),
          ),
          _MetricCard(
            width: width,
            label: 'Reviewed',
            value: '${stats.reviewed}',
            icon: Icons.verified_outlined,
            color: const Color(0xFF16866D),
          ),
          _MetricCard(
            width: width,
            label: 'Archived',
            value: '${stats.archived}',
            icon: Icons.inventory_2_outlined,
            color: const Color(0xFF667085),
          ),
        ],
      );
    },
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RecordsPanel extends StatelessWidget {
  const _RecordsPanel({
    required this.records,
    required this.totalCount,
    required this.query,
    required this.filter,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onRecordSelected,
    required this.onExport,
  });
  final List<VisitRecord> records;
  final int totalCount;
  final String query;
  final _RecordFilter filter;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_RecordFilter> onFilterChanged;
  final ValueChanged<VisitRecord> onRecordSelected;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Visit records',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Search, edit, and retain a complete visit history.',
                    style: TextStyle(color: Color(0xFF667085)),
                  ),
                ],
              ),
              FilledButton.tonalIcon(
                onPressed: onExport,
                icon: const Icon(Icons.content_copy_outlined),
                label: const Text('Copy CSV'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 680;
              final search = TextField(
                onChanged: onQueryChanged,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText:
                      'Study ID, participant, phone, collector, or visit ID',
                ),
              );
              final status = DropdownButtonFormField<_RecordFilter>(
                isExpanded: true,
                initialValue: filter,
                onChanged: (value) {
                  if (value != null) onFilterChanged(value);
                },
                decoration: const InputDecoration(labelText: 'Record status'),
                items: _RecordFilter.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.label),
                      ),
                    )
                    .toList(),
              );
              return stack
                  ? Column(
                      children: [search, const SizedBox(height: 12), status],
                    )
                  : Row(
                      children: [
                        Expanded(child: search),
                        const SizedBox(width: 14),
                        SizedBox(width: 205, child: status),
                      ],
                    );
            },
          ),
          const SizedBox(height: 18),
          Text(
            '${records.length} of $totalCount records shown',
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (records.isEmpty)
            const _EmptyRecords()
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: const WidgetStatePropertyAll(
                  Color(0xFFF7F9FC),
                ),
                horizontalMargin: 14,
                columnSpacing: 28,
                columns: const [
                  DataColumn(label: Text('Participant')),
                  DataColumn(label: Text('Phone')),
                  DataColumn(label: Text('Visit')),
                  DataColumn(label: Text('Collector')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Review')),
                  DataColumn(label: Text('Last updated')),
                  DataColumn(label: Text('')),
                ],
                rows: records
                    .map(
                      (record) => DataRow(
                        onSelectChanged: (_) => onRecordSelected(record),
                        cells: [
                          DataCell(_ParticipantCell(record: record)),
                          DataCell(Text(record.participant.indianPhone)),
                          DataCell(Text('Visit ${record.visitNumber}')),
                          DataCell(Text(record.collectorId)),
                          DataCell(_StatusPill(record: record)),
                          DataCell(_ReviewPill(record: record)),
                          DataCell(Text(_relativeTime(record.updatedAt))),
                          const DataCell(
                            Icon(Icons.chevron_right, color: Color(0xFF667085)),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    ),
  );
}

class _ParticipantCell extends StatelessWidget {
  const _ParticipantCell({required this.record});
  final VisitRecord record;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          record.participant.name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          record.participant.studyId,
          style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.record});
  final VisitRecord record;
  @override
  Widget build(BuildContext context) {
    final (label, color) = record.isArchived
        ? ('Archived', const Color(0xFF667085))
        : switch (record.syncState) {
            SyncState.synced => ('Synced', const Color(0xFF16866D)),
            SyncState.pending => ('Pending sync', const Color(0xFFE08A24)),
            SyncState.failed => ('Sync conflict', const Color(0xFFCC4B4B)),
            SyncState.localOnly => ('Local draft', const Color(0xFF7254C7)),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ReviewPill extends StatelessWidget {
  const _ReviewPill({required this.record});
  final VisitRecord record;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (record.reviewState) {
      NeutralReviewState.reviewed => ('Reviewed', const Color(0xFF16866D)),
      NeutralReviewState.pending => ('Pending review', const Color(0xFF667085)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _EmptyRecords extends StatelessWidget {
  const _EmptyRecords();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 58),
    child: Center(
      child: Column(
        children: [
          Icon(Icons.search_off_outlined, size: 36, color: Color(0xFF667085)),
          SizedBox(height: 12),
          Text(
            'No matching records',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 4),
          Text(
            'Clear or adjust the active search and status filter.',
            style: TextStyle(color: Color(0xFF667085)),
          ),
        ],
      ),
    ),
  );
}

class _ArchiveNotice extends StatelessWidget {
  const _ArchiveNotice({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFF0F4FF),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: const Icon(Icons.lock_outline, color: Color(0xFF2855D9)),
      title: const Text(
        'Records stay safe here',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: const Text(
        'Archiving is reversible and never deletes the original visit record.',
      ),
      trailing: TextButton(onPressed: onTap, child: const Text('View policy')),
    ),
  );
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 12),
            const Text(
              'Records could not be loaded',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RecordEditSheet extends StatefulWidget {
  const _RecordEditSheet({required this.record});
  final VisitRecord record;

  @override
  State<_RecordEditSheet> createState() => _RecordEditSheetState();
}

class _RecordEditSheetState extends State<_RecordEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _visit;
  late final TextEditingController _measurementValue;
  late final TextEditingController _measurementUnit;
  late final TextEditingController _measurementNote;
  late VisitStatus _status;
  late NeutralReviewState _reviewState;
  late bool _hasMeasurement;
  late bool _confirmationChecked;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final measurement = widget.record.stepTwoMeasurement;
    _name = TextEditingController(text: widget.record.participant.name);
    _phone = TextEditingController(text: widget.record.participant.indianPhone);
    _visit = TextEditingController(text: '${widget.record.visitNumber}');
    _measurementValue = TextEditingController(
      text: measurement?.value.toString() ?? '',
    );
    _measurementUnit = TextEditingController(text: measurement?.unit ?? '');
    _measurementNote = TextEditingController(text: measurement?.note ?? '');
    _status = widget.record.status;
    _reviewState = widget.record.reviewState;
    _hasMeasurement = measurement != null;
    _confirmationChecked = widget.record.isConfirmed;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _visit.dispose();
    _measurementValue.dispose();
    _measurementUnit.dispose();
    _measurementNote.dispose();
    super.dispose();
  }

  void _invalidateConfirmation(String _) {
    if (_confirmationChecked) setState(() => _confirmationChecked = false);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FractionallySizedBox(
      heightFactor: 0.93,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC8D0DD),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit ${widget.record.participant.studyId}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close editor',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'The participant ID and collector assignment are protected.',
                  style: TextStyle(color: Color(0xFF667085)),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _EditorSectionTitle('Participant details'),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _name,
                        onChanged: _invalidateConfirmation,
                        decoration: const InputDecoration(
                          labelText: 'Participant name',
                        ),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Enter a participant name.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        onChanged: _invalidateConfirmation,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Indian mobile number',
                        ),
                        validator: (value) =>
                            ParticipantProfile.normalizeIndianPhone(value) ==
                                null
                            ? 'Enter a valid Indian mobile number.'
                            : null,
                      ),
                      const SizedBox(height: 22),
                      const _EditorSectionTitle('Visit state'),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _visit,
                        onChanged: _invalidateConfirmation,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Visit number',
                        ),
                        validator: (value) =>
                            (int.tryParse(value ?? '') ?? 0) > 0
                            ? null
                            : 'Enter a visit number greater than zero.',
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<VisitStatus>(
                        initialValue: _status,
                        decoration: const InputDecoration(
                          labelText: 'Visit status',
                        ),
                        items: VisitStatus.values
                            .map(
                              (status) => DropdownMenuItem(
                                value: status,
                                child: Text(
                                  status == VisitStatus.submitted
                                      ? 'Submitted'
                                      : 'Draft',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() {
                          _status = value!;
                          _confirmationChecked = false;
                        }),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<NeutralReviewState>(
                        initialValue: _reviewState,
                        decoration: const InputDecoration(
                          labelText: 'Review state',
                        ),
                        items: NeutralReviewState.values
                            .map(
                              (state) => DropdownMenuItem(
                                value: state,
                                child: Text(
                                  state == NeutralReviewState.reviewed
                                      ? 'Reviewed'
                                      : 'Pending review',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _reviewState = value!),
                      ),
                      if (_status == VisitStatus.submitted) ...[
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _confirmationChecked,
                          onChanged: (value) => setState(
                            () => _confirmationChecked = value ?? false,
                          ),
                          title: const Text(
                            'I have confirmed the participant details and visit number.',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            'Required before a visit can be marked submitted.',
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ],
                      const SizedBox(height: 16),
                      const _EditorSectionTitle('Optional Step 2 measurement'),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _hasMeasurement,
                        onChanged: (value) =>
                            setState(() => _hasMeasurement = value),
                        title: const Text('Include Step 2 measurement'),
                      ),
                      if (_hasMeasurement) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _measurementValue,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Measurement value',
                          ),
                          validator: (value) {
                            if (!_hasMeasurement) return null;
                            final number = num.tryParse((value ?? '').trim());
                            return number == null || number < 0
                                ? 'Enter a zero or positive number.'
                                : null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _measurementUnit,
                          decoration: const InputDecoration(
                            labelText: 'Measurement unit',
                          ),
                          validator: (value) =>
                              _hasMeasurement && (value ?? '').trim().isEmpty
                              ? 'Enter a measurement unit.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _measurementNote,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Measurement note (optional)',
                          ),
                        ),
                      ],
                      if (_saveError != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _saveError!,
                          style: const TextStyle(
                            color: Color(0xFFB3261E),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save changes'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_status == VisitStatus.submitted && !_confirmationChecked) {
      setState(
        () => _saveError =
            'Confirm the participant details before saving a submitted visit.',
      );
      return;
    }
    try {
      final visitNumber = int.parse(_visit.text.trim());
      final participant = ParticipantProfile(
        studyId: widget.record.participant.studyId,
        name: _name.text,
        indianPhone: _phone.text,
        idPolicy: _policyForExistingId(widget.record.participant.studyId),
      );
      final measurement = _hasMeasurement
          ? StepTwoMeasurement(
              value: num.parse(_measurementValue.text.trim()),
              unit: _measurementUnit.text.trim(),
              note: _measurementNote.text.trim().isEmpty
                  ? null
                  : _measurementNote.text.trim(),
            )
          : null;
      final confirmation = _status == VisitStatus.submitted
          ? VisitConfirmation(
              name: participant.name,
              indianPhone: participant.indianPhone,
              visitNumber: visitNumber,
              confirmedAt: DateTime.now().toUtc(),
            )
          : null;
      Navigator.pop(
        context,
        VisitRecord(
          id: widget.record.id,
          participant: participant,
          visitNumber: visitNumber,
          collectorId: widget.record.collectorId,
          createdAt: widget.record.createdAt,
          updatedAt: widget.record.updatedAt,
          status: _status,
          syncState: _status == VisitStatus.draft
              ? SyncState.localOnly
              : widget.record.syncState == SyncState.localOnly
              ? SyncState.pending
              : widget.record.syncState,
          reviewState: _reviewState,
          revision: widget.record.revision,
          confirmation: confirmation,
          stepTwoMeasurement: measurement,
          stepTwoPlaceholderNote: widget.record.stepTwoPlaceholderNote,
          questionnaire: widget.record.questionnaire,
          archiveMetadata: widget.record.archiveMetadata,
          submittedAt: _status == VisitStatus.submitted
              ? widget.record.submittedAt ?? DateTime.now().toUtc()
              : null,
        ),
      );
    } on ArgumentError catch (error) {
      setState(
        () => _saveError =
            error.message?.toString() ?? 'Check the entered details.',
      );
    }
  }
}

class _EditorSectionTitle extends StatelessWidget {
  const _EditorSectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
  );
}

ParticipantIdPolicy _policyForExistingId(String studyId) {
  if (!isValidParticipantStudyId(studyId)) {
    throw ArgumentError('The existing participant ID cannot be validated.');
  }
  final match = RegExp(r'^(.*?)(\d+)$').firstMatch(studyId.trim());
  if (match == null || match.group(1)!.isEmpty) {
    throw ArgumentError('The existing participant ID cannot be validated.');
  }
  final digits = match.group(2)!;
  final number = int.parse(digits);
  return ParticipantIdPolicy(
    prefix: match.group(1)!.toUpperCase(),
    firstNumber: number,
    lastNumber: number,
    padding: digits.length,
  );
}

class _RecordDetails extends StatelessWidget {
  const _RecordDetails({
    required this.record,
    required this.readOnly,
    required this.onEdit,
    required this.onArchiveToggle,
  });
  final VisitRecord record;
  final bool readOnly;
  final VoidCallback onEdit;
  final VoidCallback onArchiveToggle;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFC8D0DD),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${record.participant.studyId} · Visit ${record.visitNumber}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            record.isArchived ? 'Archived record summary' : 'Record summary',
            style: const TextStyle(color: Color(0xFF667085)),
          ),
          const SizedBox(height: 20),
          if (record.syncState == SyncState.failed) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFDE8E8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF8B4B4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFCC4B4B)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Sync conflict detected: this record was flagged during upload. Use "Edit record" to update details or resolve discrepancies.',
                      style: TextStyle(color: Color(0xFF9B1C1C), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          _DetailRow(label: 'Participant', value: record.participant.name),
          _DetailRow(label: 'Study ID', value: record.participant.studyId),
          _DetailRow(label: 'Phone', value: record.participant.indianPhone),
          _DetailRow(label: 'Collector', value: record.collectorId),
          _DetailRow(
            label: 'Visit number',
            value: 'Visit ${record.visitNumber}',
          ),
          _DetailRow(label: 'Record ID', value: record.id),
          _DetailRow(
            label: 'Visit status',
            value: record.status == VisitStatus.submitted
                ? 'Submitted'
                : 'Draft',
          ),
          _DetailRow(
            label: 'Sync status',
            value: record.syncState == SyncState.failed
                ? 'Sync conflict / attention'
                : _syncLabel(record.syncState),
          ),
          _DetailRow(
            label: 'Review state',
            value: record.reviewState == NeutralReviewState.reviewed
                ? 'Reviewed'
                : 'Pending review',
          ),
          if (record.questionnaire case final questionnaire?) ...[
            const Divider(height: 28),
            const Text(
              'Questionnaire and measurements',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            _DetailRow(label: 'Study site', value: questionnaire.studySite),
            _DetailRow(
              label: 'Age / sex',
              value: '${questionnaire.age} · ${questionnaire.sex}',
            ),
            _DetailRow(
              label: 'BMI',
              value: questionnaire.bmi.toStringAsFixed(1),
            ),
            _DetailRow(
              label: 'Average BP',
              value:
                  '${questionnaire.averageSystolic.toStringAsFixed(0)} / ${questionnaire.averageDiastolic.toStringAsFixed(0)} mmHg',
            ),
            _DetailRow(
              label: 'Activity',
              value: '${questionnaire.weeklyActiveMinutes} min/week',
            ),
            _DetailRow(
              label: 'Sleep',
              value: '${questionnaire.sleepHours} hours/night',
            ),
          ],
          if (record.stepTwoPlaceholderNote != null)
            _DetailRow(
              label: 'Optional Step 2 note',
              value: record.stepTwoPlaceholderNote!,
            ),
          _DetailRow(
            label: 'Archive status',
            value: record.isArchived ? 'Archived' : 'Active',
          ),
          _DetailRow(label: 'Last updated', value: _fullDate(record.updatedAt)),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: readOnly ? null : onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit record'),
              ),
              OutlinedButton.icon(
                onPressed: readOnly ? null : onArchiveToggle,
                icon: Icon(
                  record.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.inventory_2_outlined,
                ),
                label: Text(
                  record.isArchived ? 'Restore visit' : 'Archive visit',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (readOnly)
            const Text(
              'This is the last loaded view. Reconnect to the home server before making changes.',
              style: TextStyle(color: Color(0xFF795500), fontSize: 13),
            ),
          const Text(
            'Archiving is reversible. This portal never provides a permanent delete action.',
            style: TextStyle(color: Color(0xFF667085), fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _RecordStats {
  const _RecordStats(this.records);
  final List<VisitRecord> records;
  int get total => records.length;
  int get submitted =>
      records.where((record) => record.status == VisitStatus.submitted).length;
  int get drafts =>
      records.where((record) => record.status == VisitStatus.draft).length;
  int get needsSync => records
      .where(
        (record) =>
            record.syncState == SyncState.pending ||
            record.syncState == SyncState.failed,
      )
      .length;
  int get conflicts =>
      records.where((record) => record.syncState == SyncState.failed).length;
  int get reviewed => records
      .where((record) => record.reviewState == NeutralReviewState.reviewed)
      .length;
  int get archived => records.where((record) => record.isArchived).length;
}

enum _RecordFilter {
  all,
  submitted,
  drafts,
  needsSync,
  conflicts,
  pendingReview,
  reviewed,
  archived,
}

extension on _RecordFilter {
  String get label => switch (this) {
    _RecordFilter.all => 'All records',
    _RecordFilter.submitted => 'Submitted',
    _RecordFilter.drafts => 'Drafts',
    _RecordFilter.needsSync => 'Needs sync',
    _RecordFilter.conflicts => 'Sync conflicts',
    _RecordFilter.pendingReview => 'Pending review',
    _RecordFilter.reviewed => 'Reviewed',
    _RecordFilter.archived => 'Archived',
  };
  bool matches(VisitRecord record) => switch (this) {
    _RecordFilter.all => true,
    _RecordFilter.submitted => record.status == VisitStatus.submitted,
    _RecordFilter.drafts => record.status == VisitStatus.draft,
    _RecordFilter.needsSync =>
      record.syncState == SyncState.pending ||
          record.syncState == SyncState.failed,
    _RecordFilter.conflicts => record.syncState == SyncState.failed,
    _RecordFilter.pendingReview =>
      record.reviewState == NeutralReviewState.pending && !record.isArchived,
    _RecordFilter.reviewed =>
      record.reviewState == NeutralReviewState.reviewed && !record.isArchived,
    _RecordFilter.archived => record.isArchived,
  };
}

String _syncLabel(SyncState state) => switch (state) {
  SyncState.synced => 'Synced',
  SyncState.pending => 'Pending sync',
  SyncState.failed => 'Sync conflict / attention',
  SyncState.localOnly => 'Local draft',
};

String _relativeTime(DateTime time) {
  final delta = DateTime.now().toUtc().difference(time.toUtc());
  if (delta.inMinutes < 1) return 'Just now';
  if (delta.inHours < 1) return '${delta.inMinutes}m ago';
  if (delta.inDays < 1) return '${delta.inHours}h ago';
  return '${delta.inDays}d ago';
}

String _fullDate(DateTime value) {
  final local = value.toLocal();
  final date =
      '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$date · $time';
}

class _ServerConflictInbox extends StatelessWidget {
  const _ServerConflictInbox({
    required this.conflicts,
    required this.onReview,
    required this.onResolve,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> conflicts;
  final ValueChanged<String>? onReview;
  final void Function(String id, Map<String, dynamic> resolution)? onResolve;
  final VoidCallback onRefresh;

  static String _field(Map<String, dynamic>? record, String key) {
    if (record == null) return '—';
    if (key == 'studyId') {
      final p = record['participant'];
      if (p is Map && p['studyId'] != null) return '${p['studyId']}';
      return '${record['studyId'] ?? record['participantId'] ?? '—'}';
    }
    if (key == 'name') {
      final p = record['participant'];
      if (p is Map && p['name'] != null) return '${p['name']}';
      return '${record['name'] ?? record['participantName'] ?? '—'}';
    }
    if (key == 'phone') {
      final p = record['participant'];
      if (p is Map && (p['indianPhone'] != null || p['phone'] != null)) {
        return '${p['indianPhone'] ?? p['phone']}';
      }
      return '${record['indianPhone'] ?? record['phone'] ?? '—'}';
    }
    if (key == 'visitNumber') {
      return '${record['visitNumber'] ?? '—'}';
    }
    if (key == 'collector') {
      return '${record['collectorId'] ?? record['collector'] ?? '—'}';
    }
    return '${record[key] ?? '—'}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFCC4B4B).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.sync_problem_outlined,
                        color: Color(0xFFCC4B4B),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Server Conflict Inbox',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (conflicts.isNotEmpty) ...[
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFDE8E8),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${conflicts.length} active',
                                  style: const TextStyle(
                                    color: Color(0xFF9B1C1C),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Synchronization conflicts reported by the server requiring administrator attention.',
                          style: TextStyle(color: Color(0xFF667085)),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Refresh conflict inbox',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (conflicts.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 38,
                      color: Color(0xFF16866D),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'No server conflicts detected',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'All uploads and synchronized records match server state cleanly.',
                      style: TextStyle(color: Color(0xFF667085), fontSize: 13),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: conflicts.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final conflict = conflicts[index];
                  final conflictId = '${conflict['id'] ?? 'conflict-$index'}';
                  final status = '${conflict['status'] ?? 'pending'}';
                  final reason =
                      '${conflict['reason'] ?? conflict['conflictType'] ?? 'Sync collision'}';
                  final rejected =
                      (conflict['rejectedRecord'] ??
                              conflict['rejected'] ??
                              conflict['incomingRecord'] ??
                              conflict['incoming'])
                          as Map<String, dynamic>? ??
                      const {};
                  final conflicting =
                      (conflict['conflictingRecord'] ??
                              conflict['conflicting'] ??
                              conflict['existingRecord'] ??
                              conflict['existing'])
                          as Map<String, dynamic>? ??
                      const {};

                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.white,
                    ),
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Conflict #$conflictId',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: status == 'reviewed'
                                    ? const Color(0xFFDEF7EC)
                                    : const Color(0xFFFEF08A),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                status == 'reviewed'
                                    ? 'Reviewed'
                                    : 'Pending review',
                                style: TextStyle(
                                  color: status == 'reviewed'
                                      ? const Color(0xFF03543F)
                                      : const Color(0xFF713F12),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Reason: $reason',
                              style: const TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isNarrow = constraints.maxWidth < 650;
                            final rejectedView = _ConflictRecordView(
                              title: 'Rejected Record (Incoming)',
                              color: const Color(0xFFFFF5F5),
                              borderColor: const Color(0xFFF8B4B4),
                              studyId: _field(rejected, 'studyId'),
                              name: _field(rejected, 'name'),
                              phone: _field(rejected, 'phone'),
                              visitNumber: _field(rejected, 'visitNumber'),
                              collector: _field(rejected, 'collector'),
                            );
                            final conflictingView = _ConflictRecordView(
                              title: 'Conflicting Record (Server)',
                              color: const Color(0xFFF0F5FF),
                              borderColor: const Color(0xFFA4CAFE),
                              studyId: _field(conflicting, 'studyId'),
                              name: _field(conflicting, 'name'),
                              phone: _field(conflicting, 'phone'),
                              visitNumber: _field(conflicting, 'visitNumber'),
                              collector: _field(conflicting, 'collector'),
                            );

                            if (isNarrow) {
                              return Column(
                                children: [
                                  rejectedView,
                                  const SizedBox(height: 12),
                                  conflictingView,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: rejectedView),
                                const SizedBox(width: 14),
                                Expanded(child: conflictingView),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              onPressed: onReview == null
                                  ? null
                                  : () => onReview!(conflictId),
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Mark as Reviewed'),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              onPressed: onResolve == null
                                  ? null
                                  : () async {
                                      final res =
                                          await showDialog<
                                            Map<String, dynamic>
                                          >(
                                            context: context,
                                            builder: (ctx) => _ResolveConflictDialog(
                                              conflictId: conflictId,
                                              recordIdCollision:
                                                  conflict['conflictType'] ==
                                                      'idempotency_collision' &&
                                                  rejected['id'] ==
                                                      conflicting['id'],
                                              initialStudyId:
                                                  _field(rejected, 'studyId') !=
                                                      '—'
                                                  ? _field(rejected, 'studyId')
                                                  : _field(
                                                      conflicting,
                                                      'studyId',
                                                    ),
                                              initialVisitNumber:
                                                  _field(
                                                        rejected,
                                                        'visitNumber',
                                                      ) !=
                                                      '—'
                                                  ? _field(
                                                      rejected,
                                                      'visitNumber',
                                                    )
                                                  : _field(
                                                      conflicting,
                                                      'visitNumber',
                                                    ),
                                            ),
                                          );
                                      if (res != null) {
                                        onResolve!(conflictId, res);
                                      }
                                    },
                              icon: const Icon(
                                Icons.build_circle_outlined,
                                size: 18,
                              ),
                              label: const Text('Resolve Conflict'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ConflictRecordView extends StatelessWidget {
  const _ConflictRecordView({
    required this.title,
    required this.color,
    required this.borderColor,
    required this.studyId,
    required this.name,
    required this.phone,
    required this.visitNumber,
    required this.collector,
  });

  final String title;
  final Color color;
  final Color borderColor;
  final String studyId;
  final String name;
  final String phone;
  final String visitNumber;
  final String collector;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 10),
          _ConflictDetailRow(label: 'Study ID', value: studyId),
          _ConflictDetailRow(label: 'Participant Name', value: name),
          _ConflictDetailRow(label: 'Mobile Phone', value: phone),
          _ConflictDetailRow(label: 'Visit Number', value: visitNumber),
          _ConflictDetailRow(label: 'Collector', value: collector),
        ],
      ),
    );
  }
}

class _ConflictDetailRow extends StatelessWidget {
  const _ConflictDetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2.5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF475467),
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _ResolveConflictDialog extends StatefulWidget {
  const _ResolveConflictDialog({
    required this.conflictId,
    required this.recordIdCollision,
    required this.initialStudyId,
    required this.initialVisitNumber,
  });

  final String conflictId;
  final bool recordIdCollision;
  final String initialStudyId;
  final String initialVisitNumber;

  @override
  State<_ResolveConflictDialog> createState() => _ResolveConflictDialogState();
}

class _ResolveConflictDialogState extends State<_ResolveConflictDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _studyId;
  late final TextEditingController _recordId;
  late final TextEditingController _visitNumber;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _studyId = TextEditingController(
      text: widget.initialStudyId == '—' ? '' : widget.initialStudyId,
    );
    _recordId = TextEditingController();
    _visitNumber = TextEditingController(
      text: widget.initialVisitNumber == '—' ? '1' : widget.initialVisitNumber,
    );
    _notes = TextEditingController();
  }

  @override
  void dispose() {
    _studyId.dispose();
    _recordId.dispose();
    _visitNumber.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Resolve Conflict #${widget.conflictId}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Accept the record as corrected with updated Study ID or visit number:',
                  style: TextStyle(color: Color(0xFF667085), fontSize: 13),
                ),
                const SizedBox(height: 16),
                if (widget.recordIdCollision) ...[
                  const Text(
                    'This upload reused an accepted visit ID. Enter a new, unique record ID; the accepted visit will not be replaced.',
                    style: TextStyle(color: Color(0xFF667085), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _recordId,
                    decoration: const InputDecoration(
                      labelText: 'New record ID',
                    ),
                    validator: (value) {
                      final id = (value ?? '').trim();
                      return id.isNotEmpty && !id.contains('/')
                          ? null
                          : 'Enter a new record ID without a slash.';
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _studyId,
                  decoration: const InputDecoration(
                    labelText: 'Study ID',
                    hintText: 'e.g. C01-000001 or P001',
                  ),
                  validator: (value) =>
                      isValidParticipantStudyId(value) ? null : 'Enter a valid participant Study ID (e.g. C01-000001 or P001).',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _visitNumber,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Visit number'),
                  validator: (value) {
                    final n = int.tryParse((value ?? '').trim());
                    return (n != null && n > 0)
                        ? null
                        : 'Enter a visit number greater than zero.';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Resolution notes (optional)',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, {
              'action': 'accept_corrected',
              if (widget.recordIdCollision) 'recordId': _recordId.text.trim(),
              'studyId': _studyId.text.trim(),
              'visitNumber': int.parse(_visitNumber.text.trim()),
              if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
            });
          },
          child: const Text('Resolve Conflict'),
        ),
      ],
    );
  }
}
