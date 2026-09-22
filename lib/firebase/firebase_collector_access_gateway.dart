import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../collector_auth/collector_access.dart';

/// Binds the first anonymous Firebase installation to an administrator-issued
/// collector number. Firebase Auth retains its refresh credential; this class
/// never writes an ID token into the study database.
class FirebaseCollectorAccessGateway implements CollectorAccessGateway {
  FirebaseCollectorAccessGateway({
    required FirebaseAuth auth,
    required FirebaseFunctions functions,
  }) : this._(auth, functions);

  FirebaseCollectorAccessGateway._(this._auth, this._functions);

  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  @override
  Future<CollectorInstallationSession> claimFirstDevice({
    required CollectorCode collectorCode,
    required String installationId,
  }) async {
    if (installationId.trim().isEmpty) {
      throw ArgumentError.value(
        installationId,
        'installationId',
        'Installation ID is required.',
      );
    }
    try {
      var user = _auth.currentUser;
      user ??= (await _auth.signInAnonymously()).user;
      if (user == null) throw FirebaseAuthException(code: 'no-user');

      await _functions.httpsCallable('claimCollectorCode').call<void>({
        'collectorCode': collectorCode.value,
      });
      final token = await user.getIdTokenResult(true);
      return _sessionFromClaims(user, token.claims, collectorCode);
    } on FirebaseFunctionsException catch (error) {
      throw _accessError(error.code);
    } on FirebaseAuthException {
      throw const CollectorAccessException(
        CollectorAccessFailure.invalidSession,
      );
    }
  }

  @override
  Future<CollectorInstallationSession> validateSession(
    CollectorInstallationSession session,
  ) async {
    final user = _auth.currentUser;
    if (user == null || user.uid != session.installationId) {
      throw const CollectorAccessException(
        CollectorAccessFailure.invalidSession,
      );
    }
    try {
      await user.reload();
      final refreshed = _auth.currentUser;
      if (refreshed == null || refreshed.uid != session.installationId) {
        throw const CollectorAccessException(
          CollectorAccessFailure.invalidSession,
        );
      }
      final token = await refreshed.getIdTokenResult(true);
      return _sessionFromClaims(refreshed, token.claims, session.collectorCode);
    } on FirebaseAuthException catch (error) {
      if (error.code == 'user-disabled') {
        throw const CollectorAccessException(
          CollectorAccessFailure.disabledCollector,
        );
      }
      throw const CollectorAccessException(
        CollectorAccessFailure.invalidSession,
      );
    }
  }

  static CollectorInstallationSession _sessionFromClaims(
    User user,
    Map<String, Object?>? claims,
    CollectorCode expectedCode,
  ) {
    final role = claims?['role'];
    final claimedCode = claims?['collectorCode'];
    if (role != 'collector' || claimedCode != expectedCode.value) {
      throw const CollectorAccessException(
        CollectorAccessFailure.invalidSession,
      );
    }
    return CollectorInstallationSession(
      collectorId: expectedCode.value,
      collectorCode: expectedCode,
      installationId: user.uid,
      // Firebase Auth itself securely persists the refresh credential. This is
      // only an opaque session marker required by the platform-neutral model.
      accessToken: 'firebase:${user.uid}',
      issuedAt: DateTime.now().toUtc(),
    );
  }

  static CollectorAccessException _accessError(String code) => switch (code) {
    'not-found' => const CollectorAccessException(
      CollectorAccessFailure.unknownCode,
    ),
    'already-exists' => const CollectorAccessException(
      CollectorAccessFailure.boundToAnotherDevice,
    ),
    'permission-denied' => const CollectorAccessException(
      CollectorAccessFailure.disabledCollector,
    ),
    _ => const CollectorAccessException(CollectorAccessFailure.invalidSession),
  };
}
