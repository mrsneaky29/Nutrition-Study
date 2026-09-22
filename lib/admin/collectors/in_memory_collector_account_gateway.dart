import '../../domain/authenticated_user.dart';
import 'collector_account.dart';
import 'collector_account_gateway.dart';

/// Local fake of the future cloud collector-account service.
class InMemoryCollectorAccountGateway implements CollectorAccountGateway {
  InMemoryCollectorAccountGateway({Iterable<CollectorAccount> seed = const []})
    : _accounts = {for (final account in seed) account.code: account};

  final Map<String, CollectorAccount> _accounts;

  @override
  Future<List<CollectorAccount>> listCollectors(AuthenticatedUser admin) async {
    _requireAdmin(admin);
    final accounts = _accounts.values.toList()
      ..sort((a, b) => a.code.compareTo(b.code));
    return accounts;
  }

  @override
  Future<CollectorAccount> createNextCollector(
    AuthenticatedUser admin, {
    String? displayName,
  }) async {
    _requireAdmin(admin);
    final nextNumber = _accounts.keys
            .map(_numberFromCode)
            .whereType<int>()
            .fold(0, (highest, number) => number > highest ? number : highest) +
        1;
    final account = CollectorAccount(
      code: 'C${nextNumber.toString().padLeft(3, '0')}',
      displayName: _cleanName(displayName),
      status: CollectorAccountStatus.active,
      createdAt: DateTime.now().toUtc(),
    );
    _accounts[account.code] = account;
    return account;
  }

  @override
  Future<CollectorAccount> disableCollector(
    AuthenticatedUser admin,
    String collectorCode,
  ) async {
    _requireAdmin(admin);
    final current = _requireAccount(collectorCode);
    final updated = current.copyWith(status: CollectorAccountStatus.disabled);
    _accounts[collectorCode] = updated;
    return updated;
  }

  @override
  Future<CollectorAccount> resetDeviceBinding(
    AuthenticatedUser admin,
    String collectorCode,
  ) async {
    _requireAdmin(admin);
    final current = _requireAccount(collectorCode);
    final updated = current.copyWith(clearDeviceBinding: true);
    _accounts[collectorCode] = updated;
    return updated;
  }

  CollectorAccount _requireAccount(String collectorCode) {
    final account = _accounts[collectorCode];
    if (account == null) throw StateError('Collector $collectorCode was not found.');
    return account;
  }

  static int? _numberFromCode(String code) {
    final match = RegExp(r'^C(\d+)$').firstMatch(code);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static String? _cleanName(String? value) {
    final name = value?.trim() ?? '';
    return name.isEmpty ? null : name;
  }

  static void _requireAdmin(AuthenticatedUser admin) {
    if (!admin.isAdmin) {
      throw StateError('Only an administrator can manage collector access.');
    }
  }
}
