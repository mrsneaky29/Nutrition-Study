import '../domain/authenticated_user.dart';

/// A collector identifier issued by an administrator, for example `C001`.
///
/// A code is not a password. Its purpose is to identify the collector while
/// the backend binds the first device that claims it and issues a secret
/// installation token.
class CollectorCode {
  CollectorCode(String value) : value = _normalize(value);

  final String value;

  static String _normalize(String value) {
    final normalized = value.trim().toUpperCase();
    if (!RegExp(r'^C\d{3,}$').hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        'value',
        'A collector code must use C followed by at least three digits.',
      );
    }
    return normalized;
  }

  @override
  String toString() => value;
}

/// A locally held session issued to one bound collector installation.
///
/// [accessToken] is an opaque secret. A production implementation keeps it in
/// platform secure storage and never includes it in logs, exports, or UI.
class CollectorInstallationSession {
  const CollectorInstallationSession({
    required this.collectorId,
    required this.collectorCode,
    required this.installationId,
    required this.accessToken,
    required this.issuedAt,
  }) : assert(collectorId != ''),
       assert(installationId != ''),
       assert(accessToken != '');

  final String collectorId;
  final CollectorCode collectorCode;

  /// Opaque per-installation identifier, ideally derived and protected by the
  /// platform rather than a hardware serial number.
  final String installationId;
  final String accessToken;
  final DateTime issuedAt;

  AuthenticatedUser get authenticatedUser =>
      AuthenticatedUser(id: collectorId, role: UserRole.collector);
}

enum CollectorAccessFailure {
  unknownCode,
  disabledCollector,
  boundToAnotherDevice,
  invalidSession,
}

class CollectorAccessException implements Exception {
  const CollectorAccessException(this.failure);

  final CollectorAccessFailure failure;

  @override
  String toString() => 'CollectorAccessException(${failure.name})';
}

/// Cloud boundary for claiming and validating a collector installation.
///
/// The first call to [claimFirstDevice] for an enabled code creates the device
/// binding. Subsequent calls must use the same [installationId] until an
/// administrator explicitly resets that binding.
abstract interface class CollectorAccessGateway {
  Future<CollectorInstallationSession> claimFirstDevice({
    required CollectorCode collectorCode,
    required String installationId,
  });

  Future<CollectorInstallationSession> validateSession(
    CollectorInstallationSession session,
  );
}

/// Persistence seam for a session stored securely by the app shell.
///
/// This file deliberately has no Flutter secure-storage dependency so it can
/// be exercised in tests and implemented with a platform storage adapter.
abstract interface class InstallationSessionStore {
  Future<CollectorInstallationSession?> read();

  Future<void> write(CollectorInstallationSession session);

  Future<void> clear();
}

class InMemoryInstallationSessionStore implements InstallationSessionStore {
  CollectorInstallationSession? _session;

  @override
  Future<void> clear() async {
    _session = null;
  }

  @override
  Future<CollectorInstallationSession?> read() async => _session;

  @override
  Future<void> write(CollectorInstallationSession session) async {
    _session = session;
  }
}
