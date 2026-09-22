import '../collector_auth/collector_access.dart';
import '../domain/participant_profile.dart';
import '../domain/study_configuration.dart';
import '../domain/visit_record.dart';
import 'study_cloud_gateway.dart';

/// Deterministic in-memory implementation for local integration and tests.
///
/// It models server-side invariants (device binding, atomic numbering and
/// idempotency) but is not persistent and must never be used for real data.
class InMemoryStudyCloudGateway implements StudyCloudGateway {
  InMemoryStudyCloudGateway({
    required this.participantIdPolicy,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _nextParticipantNumber = participantIdPolicy.firstNumber;

  final ParticipantIdPolicy participantIdPolicy;
  final DateTime Function() _clock;

  final Map<String, _CollectorRegistration> _collectorsByCode = {};
  final Map<String, CollectorInstallationSession> _sessionsByToken = {};
  final Map<String, ParticipantProfile> _participantsByStudyId = {};
  final Map<String, String> _studyIdByPhone = {};
  final Map<String, VisitAllocation> _allocationsByRequestKey = {};
  final Map<String, _VisitReservation> _reservationsByVisitId = {};
  final Map<String, VisitRecord> _recordsByVisitId = {};
  final Map<String, String> _visitIdByUploadKey = {};
  int _nextParticipantNumber;
  int _nextVisitId = 1;
  int _nextToken = 1;

  /// Registering and disabling collectors belongs to the future admin backend.
  /// It is exposed here only to set up fakes and tests.
  void registerCollector({required CollectorCode code, required String id}) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Collector ID is required.');
    }
    if (_collectorsByCode.containsKey(code.value)) {
      throw ArgumentError.value(code, 'code', 'Collector code already exists.');
    }
    _collectorsByCode[code.value] = _CollectorRegistration(id: id.trim());
  }

  void setCollectorEnabled(CollectorCode code, bool enabled) {
    final registration = _collectorsByCode[code.value];
    if (registration == null) {
      throw ArgumentError.value(code, 'code', 'Unknown collector code.');
    }
    registration.enabled = enabled;
  }

  /// Represents an administrator resetting a lost/replaced device binding.
  void resetDeviceBinding(CollectorCode code) {
    final registration = _collectorsByCode[code.value];
    if (registration == null) {
      throw ArgumentError.value(code, 'code', 'Unknown collector code.');
    }
    registration.boundInstallationId = null;
    _sessionsByToken.removeWhere(
      (_, session) => session.collectorCode.value == code.value,
    );
  }

  @override
  Future<CollectorInstallationSession> claimFirstDevice({
    required CollectorCode collectorCode,
    required String installationId,
  }) async {
    _requireInstallationId(installationId);
    final registration = _collectorsByCode[collectorCode.value];
    if (registration == null) {
      throw const CollectorAccessException(CollectorAccessFailure.unknownCode);
    }
    if (!registration.enabled) {
      throw const CollectorAccessException(
        CollectorAccessFailure.disabledCollector,
      );
    }
    if (registration.boundInstallationId != null &&
        registration.boundInstallationId != installationId) {
      throw const CollectorAccessException(
        CollectorAccessFailure.boundToAnotherDevice,
      );
    }

    registration.boundInstallationId = installationId;
    final session = CollectorInstallationSession(
      collectorId: registration.id,
      collectorCode: collectorCode,
      installationId: installationId,
      accessToken: 'test-token-${_nextToken++}',
      issuedAt: _clock(),
    );
    _sessionsByToken[session.accessToken] = session;
    return session;
  }

  @override
  Future<CollectorInstallationSession> validateSession(
    CollectorInstallationSession session,
  ) async {
    return _requireSession(session);
  }

  @override
  Future<ParticipantLookupResult?> lookupParticipant({
    required CollectorInstallationSession session,
    required ParticipantLookupQuery query,
  }) async {
    _requireSession(session);
    final participant = query.studyId == null
        ? _participantsByStudyId[_studyIdByPhone[query.indianPhone]]
        : _participantsByStudyId[query.studyId];
    if (participant == null) return null;
    return ParticipantLookupResult(
      participant: participant,
      nextVisitNumber: _nextVisitNumber(participant.studyId),
    );
  }

  @override
  Future<VisitAllocation> allocateVisit({
    required CollectorInstallationSession session,
    required NewParticipantDetails participant,
    required String requestKey,
  }) async {
    final verifiedSession = _requireSession(session);
    _requireKey(requestKey, 'requestKey');
    final existingAllocation = _allocationsByRequestKey[requestKey];
    if (existingAllocation != null) {
      final reservation = _reservationsByVisitId[existingAllocation.visitId]!;
      if (reservation.collectorId != verifiedSession.collectorId) {
        throw const CloudVisitConflictException(
          'An allocation key cannot be reused by another collector.',
        );
      }
      return existingAllocation;
    }

    final knownStudyId = _studyIdByPhone[participant.indianPhone];
    final profile = knownStudyId == null
        ? _createParticipant(participant)
        : _participantsByStudyId[knownStudyId]!;
    final allocation = VisitAllocation(
      visitId: 'cloud-visit-${_nextVisitId++}',
      requestKey: requestKey,
      participant: profile,
      visitNumber: _nextVisitNumber(profile.studyId),
    );
    _allocationsByRequestKey[requestKey] = allocation;
    _reservationsByVisitId[allocation.visitId] = _VisitReservation(
      collectorId: verifiedSession.collectorId,
      participant: profile,
      visitNumber: allocation.visitNumber,
    );
    return allocation;
  }

  @override
  Future<UploadVisitResult> uploadVisit({
    required CollectorInstallationSession session,
    required VisitRecord record,
    required String idempotencyKey,
  }) async {
    final verifiedSession = _requireSession(session);
    _requireKey(idempotencyKey, 'idempotencyKey');
    final previouslyUploadedVisitId = _visitIdByUploadKey[idempotencyKey];
    if (previouslyUploadedVisitId != null) {
      if (previouslyUploadedVisitId != record.id) {
        throw const CloudVisitConflictException(
          'An upload key cannot be reused for another visit.',
        );
      }
      return UploadVisitResult(
        record: _recordsByVisitId[previouslyUploadedVisitId]!,
        created: false,
      );
    }

    final reservation = _reservationsByVisitId[record.id];
    if (reservation == null ||
        reservation.collectorId != verifiedSession.collectorId ||
        record.collectorId != verifiedSession.collectorId ||
        record.participant.studyId != reservation.participant.studyId ||
        record.participant.indianPhone != reservation.participant.indianPhone ||
        record.visitNumber != reservation.visitNumber) {
      throw const CloudVisitConflictException(
        'The visit does not match its server allocation.',
      );
    }

    final existing = _recordsByVisitId[record.id];
    if (existing != null && record.revision < existing.revision) {
      throw const CloudVisitConflictException(
        'The phone has an older revision than the cloud record.',
      );
    }
    final stored = record.copyWith(syncState: SyncState.synced);
    _recordsByVisitId[record.id] = stored;
    _visitIdByUploadKey[idempotencyKey] = record.id;
    return UploadVisitResult(record: stored, created: existing == null);
  }

  @override
  Future<List<VisitRecord>> listCollectorHistory({
    required CollectorInstallationSession session,
  }) async {
    final verifiedSession = _requireSession(session);
    final records =
        _recordsByVisitId.values
            .where(
              (record) =>
                  record.collectorId == verifiedSession.collectorId &&
                  !record.isArchived,
            )
            .toList()
          ..sort((one, two) => one.createdAt.compareTo(two.createdAt));
    return List.unmodifiable(records);
  }

  CollectorInstallationSession _requireSession(
    CollectorInstallationSession session,
  ) {
    final issued = _sessionsByToken[session.accessToken];
    final registration = _collectorsByCode[session.collectorCode.value];
    if (issued == null ||
        issued.collectorId != session.collectorId ||
        issued.installationId != session.installationId ||
        registration == null ||
        !registration.enabled ||
        registration.boundInstallationId != session.installationId) {
      throw const CollectorAccessException(
        CollectorAccessFailure.invalidSession,
      );
    }
    return issued;
  }

  ParticipantProfile _createParticipant(NewParticipantDetails details) {
    while (!participantIdPolicy.contains(_nextParticipantNumber) ||
        _participantsByStudyId.containsKey(
          participantIdPolicy.format(_nextParticipantNumber),
        )) {
      _nextParticipantNumber++;
      if (_nextParticipantNumber > participantIdPolicy.lastNumber) {
        throw StateError('No participant IDs remain in the configured range.');
      }
    }
    final profile = ParticipantProfile(
      studyId: participantIdPolicy.format(_nextParticipantNumber++),
      name: details.name,
      indianPhone: details.indianPhone,
      idPolicy: participantIdPolicy,
    );
    _participantsByStudyId[profile.studyId] = profile;
    _studyIdByPhone[profile.indianPhone] = profile.studyId;
    return profile;
  }

  int _nextVisitNumber(String studyId) =>
      _reservationsByVisitId.values
          .where((reservation) => reservation.participant.studyId == studyId)
          .map((reservation) => reservation.visitNumber)
          .fold(0, (highest, number) => number > highest ? number : highest) +
      1;

  void _requireInstallationId(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(
        value,
        'installationId',
        'Installation ID is required.',
      );
    }
  }

  void _requireKey(String value, String parameter) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, parameter, '$parameter is required.');
    }
  }
}

class _CollectorRegistration {
  _CollectorRegistration({required this.id});

  final String id;
  bool enabled = true;
  String? boundInstallationId;
}

class _VisitReservation {
  const _VisitReservation({
    required this.collectorId,
    required this.participant,
    required this.visitNumber,
  });

  final String collectorId;
  final ParticipantProfile participant;
  final int visitNumber;
}
