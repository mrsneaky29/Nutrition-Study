import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../cloud/study_cloud_gateway.dart';
import '../collector_auth/collector_access.dart';
import '../domain/measurement.dart';
import '../domain/ncd_questionnaire.dart';
import '../domain/participant_profile.dart';
import '../domain/study_configuration.dart';
import '../domain/visit_record.dart';
import 'firebase_collector_access_gateway.dart';

class FirebaseStudyCloudGateway implements StudyCloudGateway {
  FirebaseStudyCloudGateway({
    required String studyId,
    required FirebaseCollectorAccessGateway access,
    required FirebaseFunctions functions,
    required FirebaseFirestore firestore,
  }) : this._(studyId, access, functions, firestore);

  FirebaseStudyCloudGateway._(
    this.studyId,
    this._access,
    this._functions,
    this._firestore,
  );

  final String studyId;
  final FirebaseCollectorAccessGateway _access;
  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  @override
  Future<CollectorInstallationSession> claimFirstDevice({
    required CollectorCode collectorCode,
    required String installationId,
  }) => _access.claimFirstDevice(
    collectorCode: collectorCode,
    installationId: installationId,
  );

  @override
  Future<CollectorInstallationSession> validateSession(
    CollectorInstallationSession session,
  ) => _access.validateSession(session);

  @override
  Future<ParticipantLookupResult?> lookupParticipant({
    required CollectorInstallationSession session,
    required ParticipantLookupQuery query,
  }) async {
    await validateSession(session);
    final response = await _functions
        .httpsCallable('lookupStudyParticipant')
        .call({
          'studyId': studyId,
          'query': {
            'participantCode': ?query.studyId,
            'indianPhone': ?query.indianPhone,
          },
        });
    final root = _map(response.data);
    if (root['participant'] == null) return null;
    final participant = _map(root['participant']);
    final profile = _map(participant['profile']);
    return ParticipantLookupResult(
      participant: _profile(_text(participant, 'participantCode'), profile),
      nextVisitNumber: _integer(participant, 'nextVisitNumber'),
    );
  }

  @override
  Future<VisitAllocation> allocateVisit({
    required CollectorInstallationSession session,
    required NewParticipantDetails participant,
    required String requestKey,
  }) async {
    await validateSession(session);
    final response = await _functions.httpsCallable('allocateStudyVisit').call({
      'studyId': studyId,
      'requestKey': requestKey,
      'participant': {
        'name': participant.name,
        'indianPhone': participant.indianPhone,
      },
    });
    final data = _map(response.data);
    return VisitAllocation(
      visitId: _text(data, 'visitId'),
      requestKey: requestKey,
      participant: _profile(
        _text(data, 'participantCode'),
        _map(data['profile']),
      ),
      visitNumber: _integer(data, 'visitNumber'),
    );
  }

  @override
  Future<UploadVisitResult> uploadVisit({
    required CollectorInstallationSession session,
    required VisitRecord record,
    required String idempotencyKey,
  }) async {
    await validateSession(session);
    final questionnaire = record.questionnaire;
    final confirmation = record.confirmation;
    if (questionnaire == null ||
        confirmation == null ||
        record.submittedAt == null) {
      throw ArgumentError('A completed and confirmed visit is required.');
    }
    final response = await _functions
        .httpsCallable('submitAllocatedStudyVisit')
        .call({
          'studyId': studyId,
          'visitId': record.id,
          'idempotencyKey': idempotencyKey,
          'visit': {
            'visitDate': record.submittedAt!.toUtc(),
            'submittedAt': record.submittedAt!.toUtc(),
            'reviewState': record.reviewState.name,
            'questionnaire': questionnaire.toMap(),
            if (record.stepTwoMeasurement case final measurement?)
              'stepTwoMeasurement': measurement.toFirestoreMap(),
            'confirmation': {
              'name': confirmation.name,
              'indianPhone': confirmation.indianPhone,
              'visitNumber': confirmation.visitNumber,
              'confirmedAt': confirmation.confirmedAt.toUtc(),
            },
            'metadata': {'schemaVersion': 1, 'sourceRevision': record.revision},
          },
        });
    final result = _map(response.data);
    return UploadVisitResult(
      record: record.copyWith(syncState: SyncState.synced),
      created: result['replayed'] != true,
    );
  }

  @override
  Future<List<VisitRecord>> listCollectorHistory({
    required CollectorInstallationSession session,
  }) async {
    await validateSession(session);
    final visits = await _firestore
        .collection('studies')
        .doc(studyId)
        .collection('visits')
        .where('collectorId', isEqualTo: session.collectorCode.value)
        .get();
    final records = await Future.wait(
      visits.docs
          .where((visit) => visit.data()['status'] == 'submitted')
          .map((visit) => _record(visit)),
    );
    records.sort((a, b) => b.submittedAt!.compareTo(a.submittedAt!));
    return List.unmodifiable(records);
  }

  Future<VisitRecord> _record(
    QueryDocumentSnapshot<Map<String, dynamic>> visit,
  ) async {
    final data = visit.data();
    final participantId = _text(data, 'participantId');
    final participantSnapshot = await _firestore
        .collection('studies')
        .doc(studyId)
        .collection('participants')
        .doc(participantId)
        .get();
    final participantData = participantSnapshot.data();
    if (participantData == null) {
      throw StateError('Participant $participantId is unavailable.');
    }
    final participant = _profile(
      _text(participantData, 'participantCode'),
      _map(participantData['profile']),
    );
    final confirmationData = _map(data['confirmation']);
    final submittedAt = _date(data['submittedAt'], 'submittedAt');
    final measurementData = data['stepTwoMeasurement'];
    final archivedAt = data['archivedAt'];
    final archivedBy = data['archivedBy'];
    return VisitRecord(
      id: visit.id,
      participant: participant,
      visitNumber: _integer(data, 'visitNumber'),
      collectorId: _text(data, 'collectorId'),
      createdAt: _date(data['createdAt'], 'createdAt'),
      updatedAt: _date(data['updatedAt'], 'updatedAt'),
      submittedAt: submittedAt,
      status: VisitStatus.submitted,
      syncState: SyncState.synced,
      reviewState: data['reviewState'] == 'reviewed'
          ? NeutralReviewState.reviewed
          : NeutralReviewState.pending,
      revision: _integer(data, 'revision'),
      confirmation: VisitConfirmation(
        name: _text(confirmationData, 'name'),
        indianPhone: _text(confirmationData, 'indianPhone'),
        visitNumber: _integer(confirmationData, 'visitNumber'),
        confirmedAt: _date(confirmationData['confirmedAt'], 'confirmedAt'),
      ),
      questionnaire: NcdQuestionnaire.fromMap(data['questionnaire']),
      stepTwoMeasurement: measurementData is Map
          ? _measurement(Map<String, Object?>.from(measurementData))
          : null,
      archiveMetadata: archivedAt is Timestamp && archivedBy is String
          ? ArchiveMetadata(
              archivedBy: archivedBy,
              archivedAt: archivedAt.toDate(),
            )
          : null,
    );
  }
}

ParticipantProfile _profile(String participantCode, Map<String, Object?> data) {
  final match = RegExp(r'^(.*?)(\d+)$').firstMatch(participantCode);
  if (match == null || match.group(1)!.isEmpty) {
    throw StateError('Firebase returned an invalid participant code.');
  }
  final digits = match.group(2)!;
  final number = int.parse(digits);
  return ParticipantProfile(
    studyId: participantCode,
    name: _text(data, 'name'),
    indianPhone: _text(data, 'indianPhone'),
    idPolicy: ParticipantIdPolicy(
      prefix: match.group(1)!,
      firstNumber: number,
      lastNumber: number,
      padding: digits.length,
    ),
  );
}

StepTwoMeasurement _measurement(Map<String, Object?> data) =>
    StepTwoMeasurement(
      value: data['value'] as num,
      unit: _text(data, 'unit'),
      recordedAt: data['recordedAt'] == null
          ? null
          : _date(data['recordedAt'], 'recordedAt'),
      note: data['note'] as String?,
    );

Map<String, Object?> _map(Object? value) {
  if (value is! Map) throw StateError('Firebase returned an invalid object.');
  return Map<String, Object?>.from(value);
}

String _text(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String || value.trim().isEmpty) {
    throw StateError('Firebase returned an invalid $field.');
  }
  return value;
}

int _integer(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! num || value.toInt() != value || value < 1) {
    throw StateError('Firebase returned an invalid $field.');
  }
  return value.toInt();
}

DateTime _date(Object? value, String field) {
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  throw StateError('Firebase returned an invalid $field.');
}
