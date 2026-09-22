import '../../domain/authenticated_user.dart';

/// Authentication boundary for the administration portal.
///
/// The production implementation will obtain this identity from the hosted
/// authentication provider. UI and account-management code only receives an
/// already-authenticated administrator through this interface.
abstract interface class AdminSessionGateway {
  /// Returns the current administrator, or `null` when no valid session exists.
  Future<AuthenticatedUser?> currentAdmin();
}

/// Small in-memory session implementation for local previews and widget tests.
class InMemoryAdminSessionGateway implements AdminSessionGateway {
  const InMemoryAdminSessionGateway(this._admin);

  final AuthenticatedUser? _admin;

  @override
  Future<AuthenticatedUser?> currentAdmin() async {
    final admin = _admin;
    if (admin != null && !admin.isAdmin) {
      throw StateError('The current session is not an administrator session.');
    }
    return admin;
  }
}
