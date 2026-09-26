import '../../domain/authenticated_user.dart';
import 'collector_account.dart';

/// Backend boundary for collector access administration.
///
/// Implementations must enforce [AuthenticatedUser.isAdmin] on the server as
/// well. None of these operations delete a collector account or study data.
abstract interface class CollectorAccountGateway {
  Future<List<CollectorAccount>> listCollectors(AuthenticatedUser admin);

  /// Creates the next unused sequential collector code, such as C001.
  Future<CollectorAccount> createNextCollector(
    AuthenticatedUser admin, {
    String? displayName,
  });

  /// Blocks future use of this collector code without deleting it.
  Future<CollectorAccount> disableCollector(
    AuthenticatedUser admin,
    String collectorCode,
  );

  /// Revokes the existing device access and makes the code claimable again.
  ///
  /// A production backend must invalidate the old device token transactionally.
  Future<CollectorAccount> resetDeviceBinding(
    AuthenticatedUser admin,
    String collectorCode,
  );
}

/// Separate capability: demo gateways cannot issue production credentials.
abstract interface class CollectorQrGateway {
  Future<String> signInQrPayload(AuthenticatedUser admin, String collectorCode);
}
