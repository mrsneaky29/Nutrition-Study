/// Shared-LAN record service for the local prototype.
///
/// Run from the project directory:
///   dart run tool/local_sync_server.dart --host=0.0.0.0 --port=8787
///
/// Records are deliberately local-only. This is not an authentication service:
/// put it on a trusted LAN only, and use the Firebase deployment for production.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const _defaultHost = '0.0.0.0';
const _defaultPort = 8787;
const _maxRequestBytes = 1024 * 1024;

final _random = Random.secure();

Future<void> main(List<String> arguments) async {
  final configuration = _ServerConfiguration.parse(arguments);
  final accessKey = Platform.environment['LOCAL_SYNC_KEY'] ?? '';
  if (accessKey.length < 16) {
    stderr.writeln(
      'Set LOCAL_SYNC_KEY to a private value containing at least 16 characters.',
    );
    exitCode = 64;
    return;
  }
  final store = LocalRecordStore(Directory('.local_data'));
  await store.load();

  final server = await HttpServer.bind(configuration.host, configuration.port);
  stdout.writeln(
    'Local sync service listening at http://${configuration.host}:${server.port}',
  );
  stdout.writeln('Record store: ${store.recordsFile.path}');

  await for (final request in server) {
    unawaited(_handleRequest(request, store, accessKey));
  }
}

class _ServerConfiguration {
  const _ServerConfiguration({required this.host, required this.port});

  final String host;
  final int port;

  static _ServerConfiguration parse(List<String> arguments) {
    var host = Platform.environment['LOCAL_SYNC_HOST'] ?? _defaultHost;
    var port =
        int.tryParse(Platform.environment['LOCAL_SYNC_PORT'] ?? '') ??
        _defaultPort;

    for (final argument in arguments) {
      if (argument == '--help' || argument == '-h') {
        stdout.writeln(
          'Usage: dart run tool/local_sync_server.dart [--host=0.0.0.0] [--port=8787]',
        );
        exit(0);
      }
      if (argument.startsWith('--host=')) {
        host = argument.substring('--host='.length).trim();
      } else if (argument.startsWith('--port=')) {
        port = int.tryParse(argument.substring('--port='.length)) ?? -1;
      } else {
        throw ArgumentError('Unsupported argument: $argument');
      }
    }
    if (host.isEmpty) {
      throw ArgumentError('host cannot be empty.');
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError('port must be between 1 and 65535.');
    }
    return _ServerConfiguration(host: host, port: port);
  }
}

Future<void> _handleRequest(
  HttpRequest request,
  LocalRecordStore store,
  String accessKey,
) async {
  _addCorsHeaders(request.response);
  try {
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    if (request.headers.value('x-local-sync-key') != accessKey) {
      throw ApiException(HttpStatus.unauthorized, 'Invalid local access key.');
    }

    final segments = request.uri.pathSegments;
    if (request.method == 'GET' &&
        segments.length == 1 &&
        segments.single == 'health') {
      await _writeJson(request.response, HttpStatus.ok, {
        'status': 'ok',
        'records': store.length,
      });
      return;
    }
    if (request.method == 'GET' &&
        segments.length == 1 &&
        segments.single == 'records') {
      await _writeJson(request.response, HttpStatus.ok, store.records());
      return;
    }
    if (request.method == 'POST' &&
        segments.length == 1 &&
        segments.single == 'records') {
      final record = await store.upsertCollector(
        await _readJsonObject(request),
      );
      await _writeJson(request.response, HttpStatus.ok, record);
      return;
    }
    if (request.method == 'PUT' &&
        segments.length == 2 &&
        segments.first == 'records') {
      final record = await store.replaceAdmin(
        segments[1],
        await _readJsonObject(request),
      );
      await _writeJson(request.response, HttpStatus.ok, record);
      return;
    }
    if (request.method == 'POST' &&
        segments.length == 3 &&
        segments.first == 'records' &&
        segments[2] == 'archive') {
      final payload = await _readJsonObject(request);
      final archived = payload['archived'];
      final actor = payload['actor'];
      if (archived is! bool || actor is! String || actor.trim().isEmpty) {
        throw ApiException(
          HttpStatus.badRequest,
          'archived must be bool and actor must be non-empty text.',
        );
      }
      final record = await store.setArchived(
        segments[1],
        archived: archived,
        actor: actor.trim(),
      );
      await _writeJson(request.response, HttpStatus.ok, record);
      return;
    }
    if (request.method == 'DELETE') {
      throw ApiException(
        HttpStatus.methodNotAllowed,
        'DELETE is not supported by this service.',
      );
    }
    throw ApiException(HttpStatus.notFound, 'Route not found.');
  } on ApiException catch (error) {
    await _writeJson(request.response, error.statusCode, {
      'error': error.message,
    });
  } on FormatException catch (error) {
    await _writeJson(request.response, HttpStatus.badRequest, {
      'error': error.message,
    });
  } catch (error, stackTrace) {
    stderr.writeln('Request failed: $error\n$stackTrace');
    await _writeJson(request.response, HttpStatus.internalServerError, {
      'error': 'Internal server error.',
    });
  }
}

void _addCorsHeaders(HttpResponse response) {
  response.headers
    ..set(HttpHeaders.accessControlAllowOriginHeader, '*')
    ..set(
      HttpHeaders.accessControlAllowMethodsHeader,
      'GET, POST, PUT, OPTIONS',
    )
    ..set(
      HttpHeaders.accessControlAllowHeadersHeader,
      'Content-Type, X-Local-Sync-Key',
    )
    ..set(HttpHeaders.accessControlMaxAgeHeader, '600');
}

Future<Map<String, dynamic>> _readJsonObject(HttpRequest request) async {
  final contentLength = request.contentLength;
  if (contentLength > _maxRequestBytes) {
    throw ApiException(
      HttpStatus.requestEntityTooLarge,
      'Request body is too large.',
    );
  }
  final bytes = <int>[];
  await for (final chunk in request) {
    bytes.addAll(chunk);
    if (bytes.length > _maxRequestBytes) {
      throw ApiException(
        HttpStatus.requestEntityTooLarge,
        'Request body is too large.',
      );
    }
  }
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map) {
    throw ApiException(
      HttpStatus.badRequest,
      'Request body must be a JSON object.',
    );
  }
  return Map<String, dynamic>.from(decoded);
}

Future<void> _writeJson(
  HttpResponse response,
  int statusCode,
  Object body,
) async {
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;
}

/// Dependency-free persistence and validation for the canonical VisitRecord JSON
/// shape. The web admin page is expected to use PUT and archive endpoints; this
/// local service provides no identity provider or role authentication.
class LocalRecordStore {
  LocalRecordStore(Directory dataDirectory)
    : _dataDirectory = dataDirectory,
      recordsFile = File(
        '${dataDirectory.path}${Platform.pathSeparator}records.json',
      ),
      _backupFile = File(
        '${dataDirectory.path}${Platform.pathSeparator}records.json.bak',
      );

  final Directory _dataDirectory;
  final File recordsFile;
  final File _backupFile;
  final Map<String, Map<String, dynamic>> _records = {};
  Future<void> _writeTail = Future<void>.value();

  int get length => _records.length;

  Future<void> load() async {
    await _dataDirectory.create(recursive: true);
    final source = await recordsFile.exists()
        ? recordsFile
        : (await _backupFile.exists() ? _backupFile : null);
    if (source == null) {
      return;
    }
    final decoded = jsonDecode(await source.readAsString());
    if (decoded is! List) {
      throw FormatException('Stored records must be a JSON list.');
    }
    for (final value in decoded) {
      if (value is! Map) {
        throw FormatException('Stored record must be a JSON object.');
      }
      final record = _normalizeRecord(Map<String, dynamic>.from(value));
      _records[record['id'] as String] = record;
    }
    if (source.path == _backupFile.path && !await recordsFile.exists()) {
      await _persist();
    }
  }

  List<Map<String, dynamic>> records() {
    final values = _records.values.map(_clone).toList()
      ..sort(
        (left, right) => (right['updatedAt'] as String).compareTo(
          left['updatedAt'] as String,
        ),
      );
    return values;
  }

  Future<Map<String, dynamic>> upsertCollector(Map<String, dynamic> incoming) {
    return _serialize(() async {
      final record = _normalizeRecord(incoming, allowMissingAuditFields: true);
      final id = record['id'] as String;
      final existing = _records[id];
      if (existing != null) {
        _requireCollectorMayUpdate(existing, record);
        record
          ..['createdAt'] = existing['createdAt']
          ..['updatedAt'] = _now()
          ..['revision'] = (existing['revision'] as int) + 1
          ..['syncState'] = 'synced'
          ..['archivedAt'] = null
          ..['archivedBy'] = null;
      } else {
        if (_isArchived(record)) {
          throw ApiException(
            HttpStatus.badRequest,
            'Collectors cannot create archived records.',
          );
        }
        record
          ..['createdAt'] = _now()
          ..['updatedAt'] = _now()
          ..['revision'] = 1
          ..['syncState'] = 'synced';
      }
      _validateRecord(record);
      _records[id] = record;
      await _persist();
      return _clone(record);
    });
  }

  Future<Map<String, dynamic>> replaceAdmin(
    String id,
    Map<String, dynamic> incoming,
  ) {
    return _serialize(() async {
      final existing = _records[id];
      if (existing == null) {
        throw ApiException(HttpStatus.notFound, 'Record not found.');
      }
      final record = _normalizeRecord(incoming, allowMissingAuditFields: true);
      if (record['id'] != id) {
        throw ApiException(
          HttpStatus.badRequest,
          'Body id must match the record URL.',
        );
      }
      _requireAdminImmutableFields(existing, record);
      record
        ..['createdAt'] = existing['createdAt']
        ..['updatedAt'] = _now()
        ..['revision'] = (existing['revision'] as int) + 1;
      _copyArchiveMarker(existing, record);
      _validateRecord(record);
      _records[id] = record;
      await _persist();
      return _clone(record);
    });
  }

  Future<Map<String, dynamic>> setArchived(
    String id, {
    required bool archived,
    required String actor,
  }) {
    return _serialize(() async {
      final existing = _records[id];
      if (existing == null) {
        throw ApiException(HttpStatus.notFound, 'Record not found.');
      }
      final record = _clone(existing);
      if (archived) {
        record
          ..['archivedAt'] = _now()
          ..['archivedBy'] = actor;
      } else {
        record
          ..['archivedAt'] = null
          ..['archivedBy'] = null;
      }
      record
        ..['updatedAt'] = _now()
        ..['revision'] = (existing['revision'] as int) + 1;
      _validateRecord(record);
      _records[id] = record;
      await _persist();
      return _clone(record);
    });
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _writeTail.then((_) => operation());
    _writeTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<void> _persist() async {
    await _dataDirectory.create(recursive: true);
    final temporary = File(
      '${recordsFile.path}.tmp-$pid-${_random.nextInt(1 << 32)}',
    );
    await temporary.writeAsString(jsonEncode(records()), flush: true);
    try {
      await temporary.rename(recordsFile.path);
      if (await _backupFile.exists()) {
        await _backupFile.delete();
      }
    } on FileSystemException {
      // Windows cannot always replace an existing file with rename. Keep a
      // recoverable backup until the replacement has completed successfully.
      if (await _backupFile.exists()) {
        await _backupFile.delete();
      }
      if (await recordsFile.exists()) {
        await recordsFile.rename(_backupFile.path);
      }
      try {
        await temporary.rename(recordsFile.path);
        if (await _backupFile.exists()) {
          await _backupFile.delete();
        }
      } catch (_) {
        if (!await recordsFile.exists() && await _backupFile.exists()) {
          await _backupFile.rename(recordsFile.path);
        }
        rethrow;
      }
    }
  }
}

const _recordFields = {
  'id',
  'participant',
  'visitNumber',
  'collectorId',
  'createdAt',
  'updatedAt',
  'status',
  'syncState',
  'reviewState',
  'revision',
  'confirmation',
  'stepTwoMeasurement',
  'stepTwoPlaceholderNote',
  'questionnaire',
  'submittedAt',
  'archivedAt',
  'archivedBy',
};

Map<String, dynamic> _normalizeRecord(
  Map<String, dynamic> incoming, {
  bool allowMissingAuditFields = false,
}) {
  if (incoming.keys.any((key) => !_recordFields.contains(key))) {
    throw ApiException(
      HttpStatus.badRequest,
      'Record contains unsupported fields.',
    );
  }
  final record = _clone(incoming);
  for (final field in [
    'confirmation',
    'stepTwoMeasurement',
    'stepTwoPlaceholderNote',
    'questionnaire',
    'submittedAt',
    'archivedAt',
    'archivedBy',
  ]) {
    record.putIfAbsent(field, () => null);
  }
  if (allowMissingAuditFields) {
    record
      ..putIfAbsent('status', () => 'draft')
      ..putIfAbsent('syncState', () => 'pending')
      ..putIfAbsent('reviewState', () => 'pending')
      ..putIfAbsent('createdAt', _now)
      ..putIfAbsent('updatedAt', _now)
      ..putIfAbsent('revision', () => 1);
  }
  _validateRecord(record);
  return record;
}

void _validateRecord(Map<String, dynamic> record) {
  const required = {
    'id',
    'participant',
    'visitNumber',
    'collectorId',
    'createdAt',
    'updatedAt',
    'status',
    'syncState',
    'reviewState',
    'revision',
  };
  if (!record.keys.toSet().containsAll(required)) {
    throw ApiException(
      HttpStatus.badRequest,
      'Record is missing required fields.',
    );
  }
  _requireText(record['id'], 'id', allowSlash: false);
  _requireText(record['collectorId'], 'collectorId');
  if (record['visitNumber'] is! int || (record['visitNumber'] as int) < 1) {
    throw ApiException(
      HttpStatus.badRequest,
      'visitNumber must be a positive integer.',
    );
  }
  if (record['revision'] is! int || (record['revision'] as int) < 1) {
    throw ApiException(
      HttpStatus.badRequest,
      'revision must be a positive integer.',
    );
  }
  for (final field in ['createdAt', 'updatedAt']) {
    _requireTimestamp(record[field], field);
  }
  _requireOneOf(record['status'], 'status', const {'draft', 'submitted'});
  _requireOneOf(record['syncState'], 'syncState', const {
    'localOnly',
    'pending',
    'synced',
    'failed',
  });
  _requireOneOf(record['reviewState'], 'reviewState', const {
    'pending',
    'reviewed',
  });
  final participant = record['participant'];
  if (participant is! Map) {
    throw ApiException(HttpStatus.badRequest, 'participant must be an object.');
  }
  final participantMap = Map<String, dynamic>.from(participant);
  if (participantMap.keys.any(
    (key) => key != 'studyId' && key != 'name' && key != 'indianPhone',
  )) {
    throw ApiException(
      HttpStatus.badRequest,
      'participant contains unsupported fields.',
    );
  }
  for (final field in ['studyId', 'name', 'indianPhone']) {
    _requireText(participantMap[field], 'participant.$field');
  }
  record['participant'] = participantMap;

  _validateConfirmation(
    record['confirmation'],
    participantMap,
    record['visitNumber'] as int,
  );
  _validateStepTwoMeasurement(record['stepTwoMeasurement']);
  _validateStepTwoPlaceholderNote(record['stepTwoPlaceholderNote']);
  _validateQuestionnaire(record['questionnaire']);
  if (record['submittedAt'] != null) {
    _requireTimestamp(record['submittedAt'], 'submittedAt');
  }
  final hasArchivedAt = record['archivedAt'] != null;
  final hasArchivedBy = record['archivedBy'] != null;
  if (hasArchivedAt != hasArchivedBy) {
    throw ApiException(
      HttpStatus.badRequest,
      'archivedAt and archivedBy must be supplied together.',
    );
  }
  if (hasArchivedAt) {
    _requireTimestamp(record['archivedAt'], 'archivedAt');
    _requireText(record['archivedBy'], 'archivedBy');
  }
  if (record['status'] == 'submitted' &&
      (record['confirmation'] == null || record['submittedAt'] == null)) {
    throw ApiException(
      HttpStatus.badRequest,
      'Submitted records require confirmation and submittedAt.',
    );
  }
  if (record['status'] == 'draft' && record['submittedAt'] != null) {
    throw ApiException(
      HttpStatus.badRequest,
      'Draft records cannot contain submittedAt.',
    );
  }
}

void _validateQuestionnaire(Object? value) {
  if (value == null) return; // Legacy submissions remain valid.
  if (value is! Map) {
    throw ApiException(HttpStatus.badRequest, 'questionnaire must be an object.');
  }
  final questionnaire = Map<String, dynamic>.from(value);
  const requiredText = {
    'studySite', 'sex', 'education', 'employment', 'fruitFrequency',
    'vegetableFrequency', 'sugaryDrinkFrequency', 'processedFoodFrequency',
  };
  const requiredNumbers = {
    'age', 'activeDaysPerWeek', 'activeMinutesPerDay', 'sleepHours',
    'heightCm', 'weightKg', 'waistCm', 'bpOneSystolic', 'bpOneDiastolic',
    'bpTwoSystolic', 'bpTwoDiastolic', 'weeklyActiveMinutes', 'bmi',
    'averageSystolic', 'averageDiastolic',
  };
  final allowed = {...requiredText, ...requiredNumbers, 'tobaccoUse',
    'tobaccoType', 'tobaccoFrequency', 'alcoholPast30Days',
    'alcoholFrequency', 'hypertensionDiagnosis', 'diabetesDiagnosis',
    'highCholesterolDiagnosis', 'cardiovascularDiagnosis'};
  if (questionnaire.keys.any((key) => !allowed.contains(key)) ||
      !questionnaire.keys.toSet().containsAll({...requiredText, ...requiredNumbers})) {
    throw ApiException(HttpStatus.badRequest, 'questionnaire has an invalid shape.');
  }
  for (final field in requiredText) { _requireText(questionnaire[field], 'questionnaire.$field'); }
  for (final field in requiredNumbers) {
    if (questionnaire[field] is! num) {
      throw ApiException(HttpStatus.badRequest, 'questionnaire.$field must be numeric.');
    }
  }
  final age = questionnaire['age'] as num;
  final days = questionnaire['activeDaysPerWeek'] as num;
  if (age < 18 || age > 120 || days < 0 || days > 7 ||
      (questionnaire['heightCm'] as num) <= 0 ||
      (questionnaire['weightKg'] as num) <= 0 ||
      (questionnaire['waistCm'] as num) <= 0) {
    throw ApiException(HttpStatus.badRequest, 'questionnaire values are outside allowed ranges.');
  }
  final weekly = (questionnaire['activeDaysPerWeek'] as num) *
      (questionnaire['activeMinutesPerDay'] as num);
  final heightMetres = (questionnaire['heightCm'] as num) / 100;
  final bmi = (questionnaire['weightKg'] as num) /
      (heightMetres * heightMetres);
  final averageSystolic = ((questionnaire['bpOneSystolic'] as num) +
          (questionnaire['bpTwoSystolic'] as num)) /
      2;
  final averageDiastolic = ((questionnaire['bpOneDiastolic'] as num) +
          (questionnaire['bpTwoDiastolic'] as num)) /
      2;
  bool differs(num actual, num expected) => (actual - expected).abs() > 0.0001;
  if (differs(questionnaire['weeklyActiveMinutes'] as num, weekly) ||
      differs(questionnaire['bmi'] as num, bmi) ||
      differs(questionnaire['averageSystolic'] as num, averageSystolic) ||
      differs(questionnaire['averageDiastolic'] as num, averageDiastolic)) {
    throw ApiException(
      HttpStatus.badRequest,
      'questionnaire derived values do not match the recorded measurements.',
    );
  }
  for (final field in allowed.difference({...requiredText, ...requiredNumbers})) {
    final item = questionnaire[field];
    if (item != null && item is! String) {
      throw ApiException(HttpStatus.badRequest, 'questionnaire.$field must be text or null.');
    }
  }
}

void _requireCollectorMayUpdate(
  Map<String, dynamic> existing,
  Map<String, dynamic> incoming,
) {
  if (_isArchived(existing)) {
    throw ApiException(
      HttpStatus.conflict,
      'Archived records can only be changed through admin routes.',
    );
  }
  if (incoming['collectorId'] != existing['collectorId'] ||
      _participant(incoming)['studyId'] != _participant(existing)['studyId']) {
    throw ApiException(
      HttpStatus.forbidden,
      'Collectors cannot change record ownership or participant ID.',
    );
  }
  if (_isArchived(incoming)) {
    throw ApiException(
      HttpStatus.forbidden,
      'Collectors cannot archive records.',
    );
  }
}

void _requireAdminImmutableFields(
  Map<String, dynamic> existing,
  Map<String, dynamic> incoming,
) {
  if (incoming['collectorId'] != existing['collectorId'] ||
      _participant(incoming)['studyId'] != _participant(existing)['studyId']) {
    throw ApiException(
      HttpStatus.forbidden,
      'Admin edits cannot change record ownership or participant ID.',
    );
  }
  if (_isArchived(incoming) &&
      (incoming['archivedAt'] != existing['archivedAt'] ||
          incoming['archivedBy'] != existing['archivedBy'])) {
    throw ApiException(
      HttpStatus.badRequest,
      'Use the archive endpoint to change archive state.',
    );
  }
}

void _copyArchiveMarker(
  Map<String, dynamic> source,
  Map<String, dynamic> destination,
) {
  destination
    ..['archivedAt'] = null
    ..['archivedBy'] = null;
  if (_isArchived(source)) {
    destination
      ..['archivedAt'] = source['archivedAt']
      ..['archivedBy'] = source['archivedBy'];
  }
}

Map<String, dynamic> _participant(Map<String, dynamic> record) =>
    Map<String, dynamic>.from(record['participant'] as Map);

bool _isArchived(Map<String, dynamic> record) => record['archivedAt'] != null;

String _now() => DateTime.now().toUtc().toIso8601String();

void _requireTimestamp(Object? value, String field) {
  if (value is! String || DateTime.tryParse(value)?.toUtc() == null) {
    throw ApiException(
      HttpStatus.badRequest,
      '$field must be an ISO-8601 timestamp.',
    );
  }
}

void _requireText(Object? value, String field, {bool allowSlash = true}) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > 512 ||
      (!allowSlash && value.contains('/'))) {
    throw ApiException(HttpStatus.badRequest, '$field must be non-empty text.');
  }
}

void _requireOneOf(Object? value, String field, Set<String> allowed) {
  if (value is! String || !allowed.contains(value)) {
    throw ApiException(HttpStatus.badRequest, '$field is not valid.');
  }
}

void _validateConfirmation(
  Object? value,
  Map<String, dynamic> participant,
  int visitNumber,
) {
  if (value == null) {
    return;
  }
  if (value is! Map) {
    throw ApiException(
      HttpStatus.badRequest,
      'confirmation must be an object when present.',
    );
  }
  final confirmation = Map<String, dynamic>.from(value);
  const allowed = {'name', 'indianPhone', 'visitNumber', 'confirmedAt'};
  if (confirmation.keys.any((key) => !allowed.contains(key)) ||
      !confirmation.keys.toSet().containsAll(allowed)) {
    throw ApiException(
      HttpStatus.badRequest,
      'confirmation has an invalid shape.',
    );
  }
  _requireText(confirmation['name'], 'confirmation.name');
  _requireText(confirmation['indianPhone'], 'confirmation.indianPhone');
  _requireTimestamp(confirmation['confirmedAt'], 'confirmation.confirmedAt');
  if (confirmation['visitNumber'] is! int ||
      confirmation['name'] != participant['name'] ||
      confirmation['indianPhone'] != participant['indianPhone'] ||
      confirmation['visitNumber'] != visitNumber) {
    throw ApiException(
      HttpStatus.badRequest,
      'confirmation does not match the visit identity.',
    );
  }
}

void _validateStepTwoMeasurement(Object? value) {
  if (value == null) {
    return;
  }
  if (value is! Map) {
    throw ApiException(
      HttpStatus.badRequest,
      'stepTwoMeasurement must be an object when present.',
    );
  }
  final measurement = Map<String, dynamic>.from(value);
  const allowed = {'value', 'unit', 'recordedAt', 'note'};
  if (measurement.keys.any((key) => !allowed.contains(key)) ||
      !measurement.keys.toSet().containsAll({'value', 'unit'})) {
    throw ApiException(
      HttpStatus.badRequest,
      'stepTwoMeasurement has an invalid shape.',
    );
  }
  if (measurement['value'] is! num || (measurement['value'] as num) < 0) {
    throw ApiException(
      HttpStatus.badRequest,
      'stepTwoMeasurement.value must be non-negative.',
    );
  }
  _requireText(measurement['unit'], 'stepTwoMeasurement.unit');
  if (measurement['recordedAt'] != null) {
    _requireTimestamp(
      measurement['recordedAt'],
      'stepTwoMeasurement.recordedAt',
    );
  }
  if (measurement['note'] != null) {
    _requireText(measurement['note'], 'stepTwoMeasurement.note');
  }
}

void _validateStepTwoPlaceholderNote(Object? value) {
  if (value == null) return;
  _requireText(value, 'stepTwoPlaceholderNote');
}

Map<String, dynamic> _clone(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
