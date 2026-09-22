import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../admin/access/admin_session_gateway.dart';
import '../admin/collectors/collector_account.dart';
import '../admin/collectors/collector_account_gateway.dart';
import '../domain/authenticated_user.dart';

class FirebaseAdminSessionGateway implements AdminSessionGateway {
  FirebaseAdminSessionGateway(this._auth);

  final FirebaseAuth _auth;

  @override
  Future<AuthenticatedUser?> currentAdmin() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final token = await user.getIdTokenResult(true);
    if (token.claims?['role'] != 'admin') return null;
    return AuthenticatedUser(id: user.uid, role: UserRole.admin);
  }
}

class FirebaseCollectorAccountGateway implements CollectorAccountGateway {
  FirebaseCollectorAccountGateway({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  }) : this._(firestore, functions);

  FirebaseCollectorAccountGateway._(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Future<List<CollectorAccount>> listCollectors(AuthenticatedUser admin) async {
    _requireAdmin(admin);
    final result = await _firestore
        .collection('collectorCodes')
        .orderBy('createdAt', descending: true)
        .get();
    return List.unmodifiable(result.docs.map(_accountFromDocument));
  }

  @override
  Future<CollectorAccount> createNextCollector(
    AuthenticatedUser admin, {
    String? displayName,
  }) async {
    _requireAdmin(admin);
    final result = await _functions.httpsCallable('createCollectorCode').call({
      if (displayName?.trim().isNotEmpty ?? false)
        'displayName': displayName!.trim(),
    });
    final data = Map<String, Object?>.from(result.data as Map);
    final code = _requiredText(data, 'collectorCode');
    final snapshot = await _firestore
        .collection('collectorCodes')
        .doc(code)
        .get();
    if (!snapshot.exists) {
      throw StateError('The created collector account could not be loaded.');
    }
    return _accountFromDocument(snapshot);
  }

  @override
  Future<CollectorAccount> disableCollector(
    AuthenticatedUser admin,
    String collectorCode,
  ) => _setState(admin, collectorCode, 'revoked');

  @override
  Future<CollectorAccount> resetDeviceBinding(
    AuthenticatedUser admin,
    String collectorCode,
  ) async {
    _requireAdmin(admin);
    final code = collectorCode.trim().toUpperCase();
    await _functions.httpsCallable('resetCollectorCodeBinding').call<void>({
      'collectorCode': code,
    });
    return _load(code);
  }

  Future<CollectorAccount> _setState(
    AuthenticatedUser admin,
    String collectorCode,
    String state,
  ) async {
    _requireAdmin(admin);
    final code = collectorCode.trim().toUpperCase();
    await _functions.httpsCallable('setCollectorCodeState').call<void>({
      'collectorCode': code,
      'state': state,
    });
    return _load(code);
  }

  Future<CollectorAccount> _load(String code) async {
    final snapshot = await _firestore
        .collection('collectorCodes')
        .doc(code)
        .get();
    if (!snapshot.exists) throw StateError('Collector account was not found.');
    return _accountFromDocument(snapshot);
  }

  static CollectorAccount _accountFromDocument(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) throw StateError('Collector account is missing.');
    final createdAt = data['createdAt'];
    final boundAt = data['boundAt'];
    final boundUid = data['boundUid'];
    return CollectorAccount(
      code: snapshot.id,
      displayName: data['displayName'] as String?,
      status: data['state'] == 'active'
          ? CollectorAccountStatus.active
          : CollectorAccountStatus.disabled,
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      deviceBinding: boundUid is String && boundAt is Timestamp
          ? CollectorDeviceBinding(
              label: 'Assigned phone',
              boundAt: boundAt.toDate(),
            )
          : null,
    );
  }

  static String _requiredText(Map<String, Object?> data, String field) {
    final value = data[field];
    if (value is! String || value.trim().isEmpty) {
      throw StateError('Firebase returned an invalid $field.');
    }
    return value;
  }

  static void _requireAdmin(AuthenticatedUser actor) {
    if (!actor.isAdmin) throw StateError('Administrator access is required.');
  }
}
