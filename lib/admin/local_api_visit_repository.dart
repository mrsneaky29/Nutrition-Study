import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/visit_repository.dart';
import '../domain/authenticated_user.dart';
import '../domain/measurement.dart';
import '../domain/ncd_questionnaire.dart';
import '../domain/participant_id.dart';
import '../domain/participant_profile.dart';
import '../domain/study_configuration.dart';
import '../domain/visit_record.dart';

/// Contract for server conflict inbox management.
abstract class ServerConflictRepository {
  Future<List<Map<String, dynamic>>> listConflicts({String? status});
  Future<Map<String, dynamic>?> getConflict(String id);
  Future<void> reviewConflict(String id, {String? notes});
  Future<void> resolveConflict(String id, Map<String, dynamic> resolution);
}

/// Visit repository backed by the local administration REST service.
///
/// It deliberately implements only administrator operations. The collector
/// application does not create or use this repository.
class LocalApiVisitRepository implements VisitRepository, ServerConflictRepository {
  LocalApiVisitRepository({
    required this.apiKey,
    String? baseUrl,
    http.Client? client,
  }) : _baseUri = Uri.parse(baseUrl ?? defaultBaseUrl),
       _client = client ?? http.Client();

  static const defaultBaseUrl = String.fromEnvironment(
    'LOCAL_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8787',
  );

  final Uri _baseUri;
  final http.Client _client;
  final String apiKey;

  Uri _uri(String path) => _baseUri.resolve(path);

  @override
  Future<List<VisitRecord>> listVisibleTo(AuthenticatedUser actor) async {
    _requireAdmin(actor);
    final response = await _get('/records');
    final decoded = _decode(response);
    final records = decoded is List
        ? decoded
        : _map(decoded)['records'] ?? _map(decoded)['data'] ?? const [];
    if (records is! List) {
      throw const LocalApiException(
        'The local service returned an invalid records response.',
      );
    }
    return List.unmodifiable(
      records.map((value) => _recordFromJson(_map(value))).toList(),
    );
  }

  @override
  Future<VisitRecord?> getById(String id, AuthenticatedUser actor) async {
    final records = await listVisibleTo(actor);
    for (final record in records) {
      if (record.id == id) return record;
    }
    return null;
  }

  @override
  Future<VisitRecord> saveAdminRecord({
    required AuthenticatedUser actor,
    required VisitRecord record,
    DateTime? now,
  }) async {
    _requireAdmin(actor);
    final response = await _put(
      '/records/${Uri.encodeComponent(record.id)}',
      _recordToJson(record),
    );
    return _recordFromJson(_responseRecord(_decode(response)));
  }

  @override
  Future<VisitRecord> setArchived({
    required AuthenticatedUser actor,
    required String visitId,
    required bool archived,
    DateTime? now,
  }) async {
    _requireAdmin(actor);
    final response = await _post(
      '/records/${Uri.encodeComponent(visitId)}/archive',
      {'archived': archived, 'actor': actor.id},
    );
    return _recordFromJson(_responseRecord(_decode(response)));
  }

  @override
  Future<List<Map<String, dynamic>>> listConflicts({String? status}) async {
    final query = (status != null && status.isNotEmpty)
        ? '?status=${Uri.encodeQueryComponent(status)}'
        : '';
    final response = await _get('/conflicts$query');
    final decoded = _decode(response);
    final list = decoded is List
        ? decoded
        : _map(decoded)['conflicts'] ?? _map(decoded)['data'] ?? const [];
    if (list is! List) {
      throw const LocalApiException(
        'The local service returned an invalid conflicts response.',
      );
    }
    return list.map((item) => Map<String, dynamic>.from(_map(item))).toList();
  }

  @override
  Future<Map<String, dynamic>?> getConflict(String id) async {
    final response = await _checked(
      _client
          .get(
            _uri('/conflicts/${Uri.encodeComponent(id)}'),
            headers: _jsonHeaders,
          )
          .timeout(const Duration(seconds: 8)),
      allowNotFound: true,
    );
    if (response.statusCode == 404) return null;
    final decoded = _decode(response);
    final data = decoded is Map && decoded['conflict'] != null
        ? decoded['conflict']
        : decoded;
    return Map<String, dynamic>.from(_map(data));
  }

  @override
  Future<void> reviewConflict(String id, {String? notes}) async {
    await _post(
      '/conflicts/${Uri.encodeComponent(id)}/review',
      {
        'notes': ?notes,
      },
    );
  }

  @override
  Future<void> resolveConflict(
    String id,
    Map<String, dynamic> resolution,
  ) async {
    await _post(
      '/conflicts/${Uri.encodeComponent(id)}/resolve',
      resolution,
    );
  }

  @override
  Future<VisitRecord> createDraft({
    required AuthenticatedUser actor,
    required ParticipantProfile participant,
    DateTime? now,
  }) => _collectorOnly();

  @override
  Future<VisitRecord> saveOwnRecord({
    required AuthenticatedUser actor,
    required VisitRecord record,
  }) => _collectorOnly();

  @override
  Future<VisitRecord> submit({
    required AuthenticatedUser actor,
    required String visitId,
    DateTime? now,
  }) => _collectorOnly();

  @override
  Future<VisitRecord> updateSyncState({
    required AuthenticatedUser actor,
    required String visitId,
    required SyncState syncState,
    DateTime? now,
  }) => _collectorOnly();

  Future<http.Response> _get(String path) => _checked(
    _client
        .get(_uri(path), headers: _jsonHeaders)
        .timeout(const Duration(seconds: 8)),
  );

  Future<http.Response> _put(String path, Map<String, Object?> body) =>
      _checked(
        _client
            .put(_uri(path), headers: _jsonHeaders, body: jsonEncode(body))
            .timeout(const Duration(seconds: 8)),
      );

  Future<http.Response> _post(String path, Map<String, Object?> body) =>
      _checked(
        _client
            .post(_uri(path), headers: _jsonHeaders, body: jsonEncode(body))
            .timeout(const Duration(seconds: 8)),
      );

  Future<http.Response> _checked(
    Future<http.Response> request, {
    bool allowNotFound = false,
  }) async {
    try {
      final response = await request;
      if (allowNotFound && response.statusCode == 404) {
        return response;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LocalApiException(_errorMessage(response));
      }
      return response;
    } on TimeoutException {
      throw const LocalApiException(
        'The local service did not respond. Check that it is running on port 8787.',
      );
    } on http.ClientException catch (error) {
      throw LocalApiException(
        'Could not reach the local service: ${error.message}',
      );
    }
  }

  Map<String, String> get _jsonHeaders => {
    'content-type': 'application/json',
    'x-local-sync-key': apiKey,
  };

  static dynamic _decode(http.Response response) {
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw const LocalApiException('The local service returned invalid JSON.');
    }
  }

  static String _errorMessage(http.Response response) {
    try {
      final body = _map(jsonDecode(response.body));
      final message = body['message'] ?? body['error'];
      if (message is String && message.isNotEmpty) return message;
    } on FormatException {
      // Use the status below when a non-JSON error is returned.
    }
    return 'Local service returned HTTP ${response.statusCode}.';
  }

  static Map<String, Object?> _responseRecord(dynamic value) {
    final map = _map(value);
    final record = map['record'] ?? map['data'] ?? value;
    return _map(record);
  }

  static Map<String, Object?> _map(dynamic value) {
    if (value is! Map) {
      throw const LocalApiException(
        'The local service returned an invalid record.',
      );
    }
    return value.map((key, item) => MapEntry('$key', item));
  }

  static VisitRecord _recordFromJson(Map<String, Object?> json) {
    final participantJson = _map(json['participant']);
    final studyId = _string(participantJson, 'studyId');
    final participant = ParticipantProfile(
      studyId: studyId,
      name: _string(participantJson, 'name'),
      indianPhone: _string(participantJson, 'indianPhone'),
      idPolicy: _policyFor(studyId),
    );
    final confirmationJson = json['confirmation'];
    final measurementJson = json['stepTwoMeasurement'];
    final archivedAt = json['archivedAt'];
    final archiveJson = json['archiveMetadata'];
    final archive = archiveJson is Map
        ? _map(archiveJson)
        : archivedAt == null
        ? null
        : json;
    return VisitRecord(
      id: _string(json, 'id'),
      participant: participant,
      visitNumber: _integer(json, 'visitNumber'),
      collectorId: _string(json, 'collectorId'),
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
      status: _enumByName(VisitStatus.values, _string(json, 'status')),
      syncState: json['syncState'] == null
          ? SyncState.synced
          : _enumByName(SyncState.values, _string(json, 'syncState')),
      reviewState: json['reviewState'] == null
          ? NeutralReviewState.pending
          : _enumByName(
              NeutralReviewState.values,
              _string(json, 'reviewState'),
            ),
      revision: _integer(json, 'revision'),
      confirmation: confirmationJson == null
          ? null
          : _confirmation(_map(confirmationJson)),
      stepTwoMeasurement: measurementJson == null
          ? null
          : _measurement(_map(measurementJson)),
      stepTwoPlaceholderNote: _nullableString(json['stepTwoPlaceholderNote']),
      questionnaire: NcdQuestionnaire.fromMap(json['questionnaire']),
      archiveMetadata: archive == null
          ? null
          : ArchiveMetadata(
              archivedBy: _string(archive, 'archivedBy'),
              archivedAt: _date(archive['archivedAt']),
            ),
      submittedAt: json['submittedAt'] == null
          ? null
          : _date(json['submittedAt']),
    );
  }

  static Map<String, Object?> _recordToJson(VisitRecord record) => {
    'id': record.id,
    'participant': {
      'studyId': record.participant.studyId,
      'name': record.participant.name,
      'indianPhone': record.participant.indianPhone,
    },
    'visitNumber': record.visitNumber,
    'collectorId': record.collectorId,
    'createdAt': record.createdAt.toUtc().toIso8601String(),
    'updatedAt': record.updatedAt.toUtc().toIso8601String(),
    'status': record.status.name,
    'syncState': record.syncState.name,
    'reviewState': record.reviewState.name,
    'revision': record.revision,
    'confirmation': record.confirmation == null
        ? null
        : {
            'name': record.confirmation!.name,
            'indianPhone': record.confirmation!.indianPhone,
            'visitNumber': record.confirmation!.visitNumber,
            'confirmedAt': record.confirmation!.confirmedAt
                .toUtc()
                .toIso8601String(),
          },
    'stepTwoMeasurement': record.stepTwoMeasurement == null
        ? null
        : {
            'value': record.stepTwoMeasurement!.value,
            'unit': record.stepTwoMeasurement!.unit,
            'recordedAt': record.stepTwoMeasurement!.recordedAt
                ?.toUtc()
                .toIso8601String(),
            'note': record.stepTwoMeasurement!.note,
          },
    'stepTwoPlaceholderNote': record.stepTwoPlaceholderNote,
    'questionnaire': record.questionnaire?.toMap(),
    'submittedAt': record.submittedAt?.toUtc().toIso8601String(),
    if (record.archiveMetadata != null) ...{
      'archivedAt': record.archiveMetadata!.archivedAt
          .toUtc()
          .toIso8601String(),
      'archivedBy': record.archiveMetadata!.archivedBy,
    },
  };

  static VisitConfirmation _confirmation(Map<String, Object?> json) =>
      VisitConfirmation(
        name: _string(json, 'name'),
        indianPhone: _string(json, 'indianPhone'),
        visitNumber: _integer(json, 'visitNumber'),
        confirmedAt: _date(json['confirmedAt']),
      );

  static StepTwoMeasurement _measurement(Map<String, Object?> json) =>
      StepTwoMeasurement(
        value: json['value'] is num
            ? json['value']! as num
            : num.parse('${json['value']}'),
        unit: _string(json, 'unit'),
        recordedAt: json['recordedAt'] == null
            ? null
            : _date(json['recordedAt']),
        note: json['note']?.toString(),
      );

  static String? _nullableString(Object? value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    throw const LocalApiException(
      'The local service supplied an invalid Step 2 placeholder note.',
    );
  }

  static T _enumByName<T extends Enum>(List<T> options, String value) {
    for (final option in options) {
      if (option.name == value) return option;
    }
    throw LocalApiException('Unknown value "$value" from the local service.');
  }

  static String _string(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    throw LocalApiException('The local service omitted "$key" from a record.');
  }

  static int _integer(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ??
        (throw LocalApiException(
          'The local service supplied an invalid "$key".',
        ));
  }

  static DateTime _date(dynamic value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    if (value is Map) {
      final seconds = value['seconds'] ?? value['_seconds'];
      if (seconds is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          seconds.toInt() * 1000,
          isUtc: true,
        );
      }
    }
    throw const LocalApiException(
      'The local service supplied an invalid date.',
    );
  }

  static ParticipantIdPolicy _policyFor(String studyId) {
    if (!isValidParticipantStudyId(studyId)) {
      throw const LocalApiException(
        'The local service supplied an invalid participant ID.',
      );
    }
    final match = RegExp(r'^(.*?)(\d+)$').firstMatch(studyId.trim());
    if (match == null || match.group(1)!.isEmpty) {
      throw const LocalApiException(
        'The local service supplied an invalid participant ID.',
      );
    }
    final digits = match.group(2)!;
    final number = int.parse(digits);
    return ParticipantIdPolicy(
      prefix: match.group(1)!.toUpperCase(),
      firstNumber: number,
      lastNumber: number,
      padding: digits.length,
    );
  }

  void _requireAdmin(AuthenticatedUser actor) {
    if (!actor.isAdmin) {
      throw StateError('The local admin API requires an administrator.');
    }
  }

  Future<VisitRecord> _collectorOnly() => Future.error(
    UnsupportedError(
      'The local REST repository is available to the standalone admin portal only.',
    ),
  );
}

class LocalApiException implements Exception {
  const LocalApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
