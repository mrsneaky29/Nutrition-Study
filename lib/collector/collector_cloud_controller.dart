import 'dart:math';

import '../cloud/study_cloud_gateway.dart';
import '../collector_auth/collector_access.dart';
import '../domain/visit_record.dart';

/// A small, platform-neutral orchestration layer for the collector app.
///
/// The UI owns draft editing and durable retry-key storage. This class owns
/// the order in which a locally stored collector session is restored,
/// validated, and used with [StudyCloudGateway].
class CollectorCloudController {
  CollectorCloudController({
    required this.gateway,
    required this.sessionStore,
    String Function()? installationIdGenerator,
    String Function()? requestIdGenerator,
  }) : _installationIdGenerator =
           installationIdGenerator ?? (() => _newOpaqueId('installation')),
       _requestIdGenerator = requestIdGenerator ?? (() => _newOpaqueId('req'));

  final StudyCloudGateway gateway;
  final InstallationSessionStore sessionStore;
  final String Function() _installationIdGenerator;
  final String Function() _requestIdGenerator;

  /// Restores a valid installation session, or claims [collectorCode] on this
  /// installation when no valid session exists.
  ///
  /// The supplied installation-ID generator must be stable for an app
  /// installation. Injecting it keeps this boundary deterministic in tests.
  Future<CollectorSessionResolution> restoreOrClaim({
    CollectorCode? collectorCode,
  }) async {
    final restored = await validatePersistedSession();
    if (restored != null) {
      return CollectorSessionResolution.restored(restored);
    }
    if (collectorCode == null) throw const CollectorSessionRequiredException();

    final session = await gateway.claimFirstDevice(
      collectorCode: collectorCode,
      installationId: _requireGeneratedId(
        _installationIdGenerator(),
        'installationId',
      ),
    );
    await sessionStore.write(session);
    return CollectorSessionResolution.claimed(session);
  }

  /// Reads the stored session and validates it with the backend.
  ///
  /// Malformed local data and an explicitly invalid cloud session are cleared
  /// so the caller can safely ask for a collector code again. Connectivity and
  /// other unexpected failures deliberately leave the session intact.
  Future<CollectorInstallationSession?> validatePersistedSession() async {
    CollectorInstallationSession? persisted;
    try {
      persisted = await sessionStore.read();
    } on FormatException {
      await sessionStore.clear();
      return null;
    }
    if (persisted == null) return null;

    try {
      final validated = await gateway.validateSession(persisted);
      await sessionStore.write(validated);
      return validated;
    } on CollectorAccessException catch (error) {
      if (error.failure == CollectorAccessFailure.invalidSession ||
          error.failure == CollectorAccessFailure.disabledCollector) {
        await sessionStore.clear();
        return null;
      }
      rethrow;
    }
  }

  /// Removes a locally held session after it is known to be invalid.
  Future<void> clearInvalidSession() => sessionStore.clear();

  Future<ParticipantLookupResult?> lookupParticipant(
    ParticipantLookupQuery query,
  ) async {
    final session = await _requiredSession();
    return gateway.lookupParticipant(session: session, query: query);
  }

  /// Atomically reserves the next visit for either a new participant or a
  /// participant already known by their phone number.
  ///
  /// Keep the returned [CollectorVisitAllocation.requestKey] with the draft;
  /// pass it back after an interrupted attempt to avoid consuming another
  /// visit number.
  Future<CollectorVisitAllocation> allocateNewOrRepeatVisit({
    required NewParticipantDetails participant,
    String? requestKey,
  }) async {
    final session = await _requiredSession();
    final key = _usableKey(requestKey ?? _requestIdGenerator(), 'requestKey');
    final allocation = await gateway.allocateVisit(
      session: session,
      participant: participant,
      requestKey: key,
    );
    return CollectorVisitAllocation(allocation: allocation, requestKey: key);
  }

  /// Uploads a visit using a caller-persisted idempotency key.
  ///
  /// If [idempotencyKey] is omitted, a generated key is returned in the
  /// result. The caller should durably save it before retrying after an
  /// interrupted request.
  Future<CollectorUploadResult> uploadIdempotently({
    required VisitRecord record,
    String? idempotencyKey,
  }) async {
    final session = await _requiredSession();
    if (record.collectorId != session.collectorId) {
      throw ArgumentError.value(
        record.collectorId,
        'record.collectorId',
        'A collector can upload only their own visits.',
      );
    }
    _requireUploadableRecord(record);
    final key = _usableKey(
      idempotencyKey ?? _requestIdGenerator(),
      'idempotencyKey',
    );
    final result = await gateway.uploadVisit(
      session: session,
      record: record,
      idempotencyKey: key,
    );
    return CollectorUploadResult(upload: result, idempotencyKey: key);
  }

  /// Refreshes history scoped by the backend to the currently bound collector.
  Future<List<VisitRecord>> refreshCollectorHistory() async {
    final session = await _requiredSession();
    return gateway.listCollectorHistory(session: session);
  }

  Future<CollectorInstallationSession> _requiredSession() async {
    final session = await validatePersistedSession();
    if (session == null) throw const CollectorSessionRequiredException();
    return session;
  }

  static String _usableKey(String value, String parameter) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, parameter, '$parameter is required.');
    }
    return normalized;
  }

  static String _requireGeneratedId(String value, String parameter) =>
      _usableKey(value, parameter);

  static void _requireUploadableRecord(VisitRecord record) {
    if (!record.isSubmitted || record.submittedAt == null) {
      throw ArgumentError('Only submitted visits can be uploaded.');
    }
    if (record.isArchived) {
      throw ArgumentError('Archived visits cannot be uploaded.');
    }
    if (!record.isConfirmed) {
      throw ArgumentError(
        'Name, phone, and visit number must be confirmed before upload.',
      );
    }
    if (record.questionnaire == null) {
      throw ArgumentError('A completed NCD questionnaire is required.');
    }
  }
}

/// Indicates whether [CollectorCloudController.restoreOrClaim] restored a
/// prior installation binding or made a new claim.
class CollectorSessionResolution {
  const CollectorSessionResolution._({
    required this.session,
    required this.restored,
  });

  factory CollectorSessionResolution.restored(
    CollectorInstallationSession session,
  ) => CollectorSessionResolution._(session: session, restored: true);

  factory CollectorSessionResolution.claimed(
    CollectorInstallationSession session,
  ) => CollectorSessionResolution._(session: session, restored: false);

  final CollectorInstallationSession session;
  final bool restored;

  bool get claimed => !restored;
}

/// Includes the durable server request key necessary to retry allocation.
class CollectorVisitAllocation {
  const CollectorVisitAllocation({
    required this.allocation,
    required this.requestKey,
  });

  final VisitAllocation allocation;
  final String requestKey;
}

/// Includes the durable server idempotency key necessary to retry an upload.
class CollectorUploadResult {
  const CollectorUploadResult({
    required this.upload,
    required this.idempotencyKey,
  });

  final UploadVisitResult upload;
  final String idempotencyKey;
}

class CollectorSessionRequiredException implements Exception {
  const CollectorSessionRequiredException();

  @override
  String toString() => 'CollectorSessionRequiredException';
}

String _newOpaqueId(String prefix) {
  final random = Random.secure();
  final values = List<int>.generate(16, (_) => random.nextInt(256));
  final hex = values
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '$prefix-$hex';
}
