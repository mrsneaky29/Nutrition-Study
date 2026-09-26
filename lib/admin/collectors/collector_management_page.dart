import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../collector_auth/collector_qr_payload.dart';

import '../../domain/authenticated_user.dart';
import '../access/admin_session_gateway.dart';
import 'collector_account.dart';
import 'collector_account_gateway.dart';

/// Standalone portal screen for collector numbers and phone bindings.
///
/// It is intentionally not wired into the current demo dashboard. The hosting
/// app should provide a real [AdminSessionGateway] and [CollectorAccountGateway]
/// when administrator authentication and the cloud backend are enabled.
class CollectorManagementPage extends StatefulWidget {
  const CollectorManagementPage({
    required this.sessionGateway,
    required this.collectorGateway,
    super.key,
  });

  final AdminSessionGateway sessionGateway;
  final CollectorAccountGateway collectorGateway;

  @override
  State<CollectorManagementPage> createState() =>
      _CollectorManagementPageState();
}

class _CollectorManagementPageState extends State<CollectorManagementPage> {
  AuthenticatedUser? _admin;
  List<CollectorAccount>? _accounts;
  Object? _loadError;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (_isLoading && !force) return;
    setState(() => _isLoading = true);
    try {
      final admin = await widget.sessionGateway.currentAdmin();
      if (admin == null) {
        if (mounted) {
          setState(() {
            _admin = null;
            _accounts = null;
          });
        }
        return;
      }
      if (!admin.isAdmin) {
        throw StateError('This account is not an administrator.');
      }
      final accounts = await widget.collectorGateway.listCollectors(admin);
      if (!mounted) {
        return;
      }
      setState(() {
        _admin = admin;
        _accounts = accounts;
        _loadError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createCollector() async {
    final displayName = await showDialog<String>(
      context: context,
      builder: (context) => const _NewCollectorDialog(),
    );
    if (displayName == null) return;
    await _runOperation(
      successMessage: 'Collector created.',
      operation: (admin) => widget.collectorGateway.createNextCollector(
        admin,
        displayName: displayName,
      ),
    );
  }

  Future<void> _disable(CollectorAccount account) async {
    final confirmed = await _confirm(
      title: 'Disable collector ${_collectorNumber(account.code)}?',
      message: 'This blocks new activity for this collector number. Existing study records remain retained.',
      action: 'Disable collector',
    );
    if (!confirmed) return;
    await _runOperation(
      successMessage:
          'Collector ${_collectorNumber(account.code)} disabled. Existing records were retained.',
      operation: (admin) =>
          widget.collectorGateway.disableCollector(admin, account.code),
    );
  }

  Future<void> _showQr(CollectorAccount account) async {
    final admin = _admin;
    final gateway = widget.collectorGateway;
    if (admin == null || !account.isActive || gateway is! CollectorQrGateway) {
      return;
    }
    setState(() => _isLoading = true);
    try {
      final payload = await (gateway as CollectorQrGateway).signInQrPayload(
        admin,
        account.code,
      );
      final parsed = CollectorQrPayload.parse(payload);
      if ('C${parsed.collectorNumber.toString().padLeft(3, '0')}' !=
          account.code) {
        throw StateError('Collector mismatch.');
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Collector ${_collectorNumber(account.code)} sign-in QR'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Private access credential. Show only to this collector. Do not share publicly or upload to a QR website.',
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 280,
                  height: 280,
                  child: QrImageView(
                    data: payload,
                    backgroundColor: Colors.white,
                    semanticsLabel: 'Private collector sign-in QR',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Scan with the +6 collector app. Signing in on another phone replaces the previous session.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The sign-in QR could not be generated. Check administrator access and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetBinding(CollectorAccount account) async {
    final live = widget.collectorGateway is CollectorQrGateway;
    final confirmed = await _confirm(
      title: live
          ? 'Reset collector ${_collectorNumber(account.code)} session?'
          : 'Reset collector ${_collectorNumber(account.code)} device?',
      message: live
          ? 'The current phone session will lose access. Saved study records remain. The collector can sign in again with the same QR.'
          : 'The currently bound phone will lose access. A replacement phone can use this collector number after the reset.',
      action: live ? 'Reset session' : 'Reset device access',
    );
    if (!confirmed) return;
    await _runOperation(
      successMessage:
          'Collector ${_collectorNumber(account.code)} device access reset.',
      operation: (admin) =>
          widget.collectorGateway.resetDeviceBinding(admin, account.code),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _runOperation({
    required Future<CollectorAccount> Function(AuthenticatedUser admin)
    operation,
    required String successMessage,
  }) async {
    final admin = _admin;
    if (admin == null) return;
    setState(() => _isLoading = true);
    try {
      await operation(admin);
      final accounts = await widget.collectorGateway.listCollectors(admin);
      if (mounted) setState(() => _accounts = accounts);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The access change could not be saved.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collector access'),
        actions: [
          IconButton(
            tooltip: 'Refresh collector access',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _admin == null && _loadError == null && !_isLoading
            ? _NoAdminSession(onRetry: _load)
            : accounts == null
            ? _LoadState(
                isLoading: _isLoading,
                error: _loadError,
                onRetry: _load,
              )
            : _CollectorList(
                admin: _admin!,
                accounts: accounts,
                isLoading: _isLoading,
                onCreate: _createCollector,
                onDisable: _disable,
                onResetBinding: _resetBinding,
                onQr: widget.collectorGateway is CollectorQrGateway
                    ? _showQr
                    : null,
              ),
      ),
    );
  }
}

class _NoAdminSession extends StatelessWidget {
  const _NoAdminSession({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 42),
          const SizedBox(height: 14),
          const Text(
            'Administrator sign-in required',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Collector access can only be managed from an authenticated administrator session.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Check session')),
        ],
      ),
    ),
  );
}

class _LoadState extends StatelessWidget {
  const _LoadState({
    required this.isLoading,
    required this.error,
    required this.onRetry,
  });
  final bool isLoading;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: isLoading
          ? const CircularProgressIndicator()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 42),
                const SizedBox(height: 14),
                const Text(
                  'Collector access could not be loaded',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(error?.toString() ?? 'Try again.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ),
    ),
  );
}

class _CollectorList extends StatelessWidget {
  const _CollectorList({
    required this.admin,
    required this.accounts,
    required this.isLoading,
    required this.onCreate,
    required this.onDisable,
    required this.onResetBinding,
    this.onQr,
  });
  final AuthenticatedUser admin;
  final List<CollectorAccount> accounts;
  final bool isLoading;
  final VoidCallback onCreate;
  final ValueChanged<CollectorAccount> onDisable;
  final ValueChanged<CollectorAccount> onResetBinding;
  final ValueChanged<CollectorAccount>? onQr;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'Signed in as ${admin.id}',
        style: const TextStyle(
          color: Color(0xFF667085),
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Collector numbers',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text(
        'Create collector numbers and manage access without deleting study records. Private sign-in QR codes are reusable; the latest phone login replaces the previous session.',
        style: TextStyle(color: Color(0xFF667085)),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: isLoading ? null : onCreate,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Create next collector number'),
      ),
      const SizedBox(height: 20),
      if (accounts.isEmpty)
        const _EmptyCollectors()
      else
        ...accounts.map(
          (account) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CollectorCard(
              account: account,
              disabled: isLoading,
              onDisable: () => onDisable(account),
              onResetBinding: () => onResetBinding(account),
              onQr: onQr == null ? null : () => onQr!(account),
            ),
          ),
        ),
    ],
  );
}

class _EmptyCollectors extends StatelessWidget {
  const _EmptyCollectors();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text('No collector numbers have been created yet.'),
    ),
  );
}

class _CollectorCard extends StatelessWidget {
  const _CollectorCard({
    required this.account,
    required this.disabled,
    required this.onDisable,
    required this.onResetBinding,
    this.onQr,
  });
  final CollectorAccount account;
  final bool disabled;
  final VoidCallback onDisable;
  final VoidCallback onResetBinding;
  final VoidCallback? onQr;

  @override
  Widget build(BuildContext context) {
    final binding = account.deviceBinding;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Collector ${_collectorNumber(account.code)}',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _StatusChip(status: account.status),
              ],
            ),
            if (account.displayName case final name?) ...[
              const SizedBox(height: 4),
              Text(name),
            ],
            const SizedBox(height: 14),
            Text(
              onQr != null
                  ? 'Reusable QR access · no permanent phone binding'
                  : binding == null
                  ? 'No phone currently bound'
                  : 'Bound to ${binding.label} · ${_date(binding.boundAt)}',
              style: const TextStyle(color: Color(0xFF475467)),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (account.isActive && onQr != null)
                  FilledButton.icon(
                    onPressed: disabled ? null : onQr,
                    icon: const Icon(Icons.qr_code_rounded),
                    label: const Text('Generate sign-in QR'),
                  ),
                if (binding != null || onQr != null)
                  OutlinedButton.icon(
                    onPressed: disabled ? null : onResetBinding,
                    icon: const Icon(Icons.phonelink_erase_outlined),
                    label: Text(
                      onQr != null ? 'Reset session' : 'Reset device',
                    ),
                  ),
                if (account.isActive)
                  FilledButton.tonalIcon(
                    onPressed: disabled ? null : onDisable,
                    icon: const Icon(Icons.block_outlined),
                    label: const Text('Disable collector'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final CollectorAccountStatus status;

  @override
  Widget build(BuildContext context) {
    final active = status == CollectorAccountStatus.active;
    return Chip(
      label: Text(active ? 'Active' : 'Disabled'),
      avatar: Icon(
        active ? Icons.check_circle_outline : Icons.block_outlined,
        size: 18,
      ),
    );
  }
}

class _NewCollectorDialog extends StatefulWidget {
  const _NewCollectorDialog();

  @override
  State<_NewCollectorDialog> createState() => _NewCollectorDialogState();
}

class _NewCollectorDialogState extends State<_NewCollectorDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create collector number'),
    content: TextField(
      controller: _name,
      autofocus: true,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: 'Collector name (optional)',
        helperText: 'The next number is assigned automatically.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _name.text),
        child: const Text('Create number'),
      ),
    ],
  );
}

String _date(DateTime value) {
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String _collectorNumber(String internalCode) {
  final match = RegExp(r'^C(\d+)$').firstMatch(internalCode);
  final number = match == null ? null : int.tryParse(match.group(1)!);
  return number?.toString() ?? internalCode;
}
