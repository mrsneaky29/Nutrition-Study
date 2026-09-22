import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/visit_repository.dart';
import '../domain/authenticated_user.dart';
import '../domain/measurement.dart';
import '../domain/participant_profile.dart';
import '../domain/study_configuration.dart';
import '../domain/visit_record.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({
    required this.repository,
    required this.admin,
    super.key,
  });

  final VisitRepository repository;
  final AuthenticatedUser admin;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  List<VisitRecord>? _records;
  String? _recordsSignature;
  Object? _initialLoadError;
  bool _isRefreshing = false;
  Timer? _poller;
  String _query = '';
  _RecordFilter _filter = _RecordFilter.all;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _poller = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<List<VisitRecord>> _loadRecords() =>
      widget.repository.listVisibleTo(widget.admin);

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final records = await _loadRecords();
      if (!mounted) return;
      final signature = _signatureFor(records);
      if (_recordsSignature != signature || _initialLoadError != null) {
        setState(() {
          _records = records;
          _recordsSignature = signature;
          _initialLoadError = null;
        });
      }
    } catch (error) {
      if (mounted && _records == null) {
        setState(() => _initialLoadError = error);
      }
    } finally {
      _isRefreshing = false;
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
              query: _query,
              filter: _filter,
              onQueryChanged: (value) => setState(() => _query = value.trim()),
              onFilterChanged: (value) => setState(() => _filter = value),
              onRefresh: _refresh,
              onArchivePolicy: () => _showArchivePolicy(context),
              onRecordSelected: (record) => _showRecord(context, record),
              onExport: () => _copyCsv(context, records),
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

  void _showRecord(BuildContext context, VisitRecord record) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _RecordDetails(
        record: record,
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
    final questionnaireHeaders = records
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
      ...records.map(
        (record) {
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
        },
      ),
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
    required this.query,
    required this.filter,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.onArchivePolicy,
    required this.onRecordSelected,
    required this.onExport,
  });

  final List<VisitRecord> records;
  final String query;
  final _RecordFilter filter;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_RecordFilter> onFilterChanged;
  final VoidCallback onRefresh;
  final VoidCallback onArchivePolicy;
  final ValueChanged<VisitRecord> onRecordSelected;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final filtered = records.where((record) {
      final haystack = [
        record.id,
        record.participant.studyId,
        record.participant.name,
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
                  'A secure browser workspace for submitted and in-progress visits.',
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
      final columns = constraints.maxWidth >= 1100
          ? 5
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
            label: 'Drafts',
            value: '${stats.drafts}',
            icon: Icons.edit_note_outlined,
            color: const Color(0xFF7254C7),
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
  final VoidCallback onExport;

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
                  hintText: 'Study ID, participant, collector, or visit ID',
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
                headingRowColor: WidgetStatePropertyAll(
                  const Color(0xFFF7F9FC),
                ),
                horizontalMargin: 14,
                columnSpacing: 34,
                columns: const [
                  DataColumn(label: Text('Participant')),
                  DataColumn(label: Text('Visit')),
                  DataColumn(label: Text('Collector')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Last updated')),
                  DataColumn(label: Text('')),
                ],
                rows: records
                    .map(
                      (record) => DataRow(
                        onSelectChanged: (_) => onRecordSelected(record),
                        cells: [
                          DataCell(_ParticipantCell(record: record)),
                          DataCell(Text('Visit ${record.visitNumber}')),
                          DataCell(Text(record.collectorId)),
                          DataCell(_StatusPill(record: record)),
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
            SyncState.failed => ('Sync attention', const Color(0xFFCC4B4B)),
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
  final match = RegExp(r'^(.*?)(\d+)$').firstMatch(studyId);
  if (match == null || match.group(1)!.isEmpty) {
    throw ArgumentError('The existing participant ID cannot be validated.');
  }
  final digits = match.group(2)!;
  final number = int.parse(digits);
  return ParticipantIdPolicy(
    prefix: match.group(1)!,
    firstNumber: number,
    lastNumber: number,
    padding: digits.length,
  );
}

class _RecordDetails extends StatelessWidget {
  const _RecordDetails({
    required this.record,
    required this.onEdit,
    required this.onArchiveToggle,
  });
  final VisitRecord record;
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
          _DetailRow(label: 'Participant', value: record.participant.name),
          _DetailRow(label: 'Phone', value: record.participant.indianPhone),
          _DetailRow(label: 'Collector', value: record.collectorId),
          _DetailRow(label: 'Record ID', value: record.id),
          _DetailRow(
            label: 'Visit status',
            value: record.status == VisitStatus.submitted
                ? 'Submitted'
                : 'Draft',
          ),
          _DetailRow(label: 'Sync status', value: _syncLabel(record.syncState)),
          if (record.questionnaire case final questionnaire?) ...[
            const Divider(height: 28),
            const Text(
              'Questionnaire and measurements',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            _DetailRow(label: 'Study site', value: questionnaire.studySite),
            _DetailRow(label: 'Age / sex', value: '${questionnaire.age} · ${questionnaire.sex}'),
            _DetailRow(label: 'BMI', value: questionnaire.bmi.toStringAsFixed(1)),
            _DetailRow(
              label: 'Average BP',
              value: '${questionnaire.averageSystolic.toStringAsFixed(0)} / ${questionnaire.averageDiastolic.toStringAsFixed(0)} mmHg',
            ),
            _DetailRow(
              label: 'Activity',
              value: '${questionnaire.weeklyActiveMinutes} min/week',
            ),
            _DetailRow(label: 'Sleep', value: '${questionnaire.sleepHours} hours/night'),
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
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit record'),
              ),
              OutlinedButton.icon(
                onPressed: onArchiveToggle,
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
  int get archived => records.where((record) => record.isArchived).length;
}

enum _RecordFilter { all, submitted, drafts, needsSync, archived }

extension on _RecordFilter {
  String get label => switch (this) {
    _RecordFilter.all => 'All records',
    _RecordFilter.submitted => 'Submitted',
    _RecordFilter.drafts => 'Drafts',
    _RecordFilter.needsSync => 'Needs sync',
    _RecordFilter.archived => 'Archived',
  };
  bool matches(VisitRecord record) => switch (this) {
    _RecordFilter.all => true,
    _RecordFilter.submitted => record.status == VisitStatus.submitted,
    _RecordFilter.drafts => record.status == VisitStatus.draft,
    _RecordFilter.needsSync =>
      record.syncState == SyncState.pending ||
          record.syncState == SyncState.failed,
    _RecordFilter.archived => record.isArchived,
  };
}

String _syncLabel(SyncState state) => switch (state) {
  SyncState.synced => 'Synced',
  SyncState.pending => 'Pending sync',
  SyncState.failed => 'Sync needs attention',
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
