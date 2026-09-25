/// Shared-LAN record service for the local prototype.
///
/// Run from the project directory:
///   dart run tool/local_sync_server.dart --host=0.0.0.0 --port=8787
///
/// Records are deliberately local-only. Keep this on a trusted LAN; shared
/// bearer keys and cleartext HTTP are not suitable for internet exposure.
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
  final accessKeys = AccessKeys.fromEnvironment(Platform.environment);
  if (accessKeys == null) {
    stderr.writeln(
      'Set distinct LOCAL_SYNC_COLLECTOR_KEY(S) and LOCAL_SYNC_ADMIN_KEY '
      '(at least 16 characters each), or legacy LOCAL_SYNC_KEY for local demo.',
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
  stdout.writeln('Conflict store: ${store.conflictsFile.path}');

  await for (final request in server) {
    unawaited(handleRequest(request, store, accessKeys));
  }
}

class AccessKeys {
  const AccessKeys({
    required this.collectorKeys,
    required this.admin,
    this.collectorIdentities = const {},
    this.requireCollectorSession = false,
  });

  final Set<String> collectorKeys;
  final String admin;
  final Map<String, String> collectorIdentities;
  final bool requireCollectorSession;

  String get collector => collectorKeys.first;

  bool isCollector(String? key) =>
      key != null && key.isNotEmpty && collectorKeys.contains(key);

  bool isAdmin(String? key) => key != null && key.isNotEmpty && key == admin;

  String? collectorIdForKey(String? key) {
    if (key == null || !isCollector(key)) return null;
    if (collectorIdentities.containsKey(key)) {
      return collectorIdentities[key];
    }
    final index = collectorKeys.toList().indexOf(key);
    if (index >= 0) {
      return 'C${(index + 1).toString().padLeft(3, '0')}';
    }
    return 'C001';
  }

  static AccessKeys? fromEnvironment(Map<String, String> environment) {
    final collectorKeys = <String>{};
    final collectorIdentities = <String, String>{};

    void parseCollectorKeys(String? raw, {String? defaultCollectorId}) {
      if (raw == null || raw.trim().isEmpty) return;
      for (final part in raw.split(',')) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        String id;
        String key;
        if (trimmed.contains(':')) {
          final colonIdx = trimmed.indexOf(':');
          final p1 = trimmed.substring(0, colonIdx).trim();
          final p2 = trimmed.substring(colonIdx + 1).trim();
          if (p1.length >= 16 && p2.length < 16) {
            key = p1;
            id = p2;
          } else if (p2.length >= 16 && p1.length < 16) {
            id = p1;
            key = p2;
          } else if (RegExp(r'^C\d+$', caseSensitive: false).hasMatch(p1)) {
            id = p1;
            key = p2;
          } else if (RegExp(r'^C\d+$', caseSensitive: false).hasMatch(p2)) {
            id = p2;
            key = p1;
          } else {
            id = p1;
            key = p2;
          }
        } else {
          key = trimmed;
          id =
              defaultCollectorId ??
              'C${(collectorKeys.length + 1).toString().padLeft(3, '0')}';
        }
        collectorKeys.add(key);
        collectorIdentities[key] = id;
      }
    }

    parseCollectorKeys(environment['LOCAL_SYNC_COLLECTOR_KEYS']);
    parseCollectorKeys(
      environment['LOCAL_SYNC_COLLECTOR_KEY'],
      defaultCollectorId: 'C001',
    );

    final admin = (environment['LOCAL_SYNC_ADMIN_KEY'] ?? '').trim();

    if (collectorKeys.isNotEmpty || admin.isNotEmpty) {
      if (admin.length < 16 ||
          collectorKeys.isEmpty ||
          collectorKeys.any((key) => key.length < 16) ||
          collectorKeys.contains(admin)) {
        return null;
      }
      return AccessKeys(
        collectorKeys: collectorKeys,
        admin: admin,
        collectorIdentities: collectorIdentities,
        requireCollectorSession: true,
      );
    }

    final legacy = (environment['LOCAL_SYNC_KEY'] ?? '').trim();
    if (legacy.length >= 16) {
      return AccessKeys(
        collectorKeys: {legacy},
        admin: legacy,
        collectorIdentities: {legacy: 'C001'},
      );
    }
    return null;
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

Future<void> handleRequest(
  HttpRequest request,
  LocalRecordStore store,
  AccessKeys accessKeys,
) async {
  _addCorsHeaders(request.response);
  try {
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    if (request.method == 'DELETE') {
      throw const ApiException(
        HttpStatus.methodNotAllowed,
        'DELETE is not supported by this service.',
      );
    }

    final suppliedKey = request.headers.value('x-local-sync-key');
    final isCollector = accessKeys.isCollector(suppliedKey);
    final isAdmin = accessKeys.isAdmin(suppliedKey);
    if (!isCollector && !isAdmin) {
      throw const ApiException(
        HttpStatus.unauthorized,
        'Invalid local access key.',
      );
    }

    final segments = request.uri.pathSegments;
    if (request.method == 'POST' &&
        segments.length == 2 &&
        segments[0] == 'collector' &&
        segments[1] == 'session') {
      if (!isCollector) {
        throw const ApiException(
          HttpStatus.forbidden,
          'Collector access required.',
        );
      }
      final identity = accessKeys.collectorIdForKey(suppliedKey)!;
      final payload = await _readJsonObject(request);
      if (payload['collectorId'] != identity) {
        throw const ApiException(
          HttpStatus.forbidden,
          'Collector number does not match the access key.',
        );
      }
      final token = await store.openCollectorSession(identity);
      await _writeJson(request.response, HttpStatus.ok, {
        'collectorId': identity,
        'sessionToken': token,
      });
      return;
    }
    if (isCollector && accessKeys.requireCollectorSession && !isAdmin) {
      final identity = accessKeys.collectorIdForKey(suppliedKey)!;
      final token = request.headers.value('x-local-session');
      if (!store.isCurrentCollectorSession(identity, token)) {
        throw const ApiException(
          HttpStatus.unauthorized,
          'Collector session expired. Sign in again on this phone.',
          errorName: 'collector_session_expired',
        );
      }
    }
    if (request.method == 'GET' &&
        segments.length == 1 &&
        segments.single == 'health') {
      await _writeJson(request.response, HttpStatus.ok, {
        'status': store.recoveredFromBackup ? 'degraded' : 'ok',
        'records': store.length,
        'recoveredFromBackup': store.recoveredFromBackup,
      });
      return;
    }
    if (request.method == 'GET' &&
        segments.length == 2 &&
        segments.first == 'participants' &&
        segments[1] == 'lookup') {
      if (!isCollector) {
        throw const ApiException(
          HttpStatus.forbidden,
          'Collector access required.',
        );
      }
      final phone = request.uri.queryParameters['phone'];
      if (phone == null || phone.trim().isEmpty) {
        throw const ApiException(
          HttpStatus.badRequest,
          'phone query parameter is required.',
        );
      }
      final result = store.lookupParticipant(phone);
      await _writeJson(request.response, HttpStatus.ok, result);
      return;
    }
    if (request.method == 'GET' &&
        segments.length == 1 &&
        segments.single == 'records') {
      _requireAdminAccess(isAdmin);
      await _writeJson(request.response, HttpStatus.ok, store.records());
      return;
    }
    if (request.method == 'POST' &&
        segments.length == 1 &&
        segments.single == 'records') {
      if (!isCollector) {
        throw const ApiException(
          HttpStatus.forbidden,
          'Collector access required.',
        );
      }
      final payload = await _readJsonObject(request);
      final authenticatedCollectorId = accessKeys.collectorIdForKey(
        suppliedKey,
      );
      final recordCollectorId = payload['collectorId'];
      if (authenticatedCollectorId != null &&
          recordCollectorId != authenticatedCollectorId) {
        throw const ApiException(
          HttpStatus.forbidden,
          'Collector identity in payload does not match authenticated credential.',
          errorName: 'collector_identity_mismatch',
        );
      }
      final record = await store.upsertCollector(
        payload,
        authenticatedCollectorId: authenticatedCollectorId,
        collectorSessionToken: accessKeys.requireCollectorSession
            ? request.headers.value('x-local-session')
            : null,
      );
      await _writeJson(request.response, HttpStatus.ok, record);
      return;
    }
    if (request.method == 'PUT' &&
        segments.length == 2 &&
        segments.first == 'records') {
      _requireAdminAccess(isAdmin);
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
      _requireAdminAccess(isAdmin);
      final payload = await _readJsonObject(request);
      final archived = payload['archived'];
      final actor = payload['actor'];
      if (archived is! bool || actor is! String || actor.trim().isEmpty) {
        throw const ApiException(
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
    if (segments.isNotEmpty && segments.first == 'conflicts') {
      _requireAdminAccess(isAdmin);
      if (request.method == 'GET' && segments.length == 1) {
        await _writeJson(request.response, HttpStatus.ok, store.conflicts());
        return;
      }
      if (request.method == 'GET' && segments.length == 2) {
        final conflict = store.getConflict(segments[1]);
        if (conflict == null) {
          throw const ApiException(
            HttpStatus.notFound,
            'Conflict report not found.',
          );
        }
        await _writeJson(request.response, HttpStatus.ok, conflict);
        return;
      }
      if (request.method == 'POST' &&
          segments.length == 3 &&
          segments[2] == 'review') {
        final payload = await _readJsonObject(request);
        final notes = payload['notes'] as String?;
        final updated = await store.reviewConflict(segments[1], notes: notes);
        await _writeJson(request.response, HttpStatus.ok, updated);
        return;
      }
      if (request.method == 'POST' &&
          segments.length == 3 &&
          segments[2] == 'resolve') {
        final payload = await _readJsonObject(request);
        final updated = await store.resolveConflict(segments[1], payload);
        await _writeJson(request.response, HttpStatus.ok, updated);
        return;
      }
      throw const ApiException(HttpStatus.notFound, 'Route not found.');
    }
    throw const ApiException(HttpStatus.notFound, 'Route not found.');
  } on ApiException catch (error) {
    await _writeJson(request.response, error.statusCode, error.toJson());
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

void _requireAdminAccess(bool isAdmin) {
  if (!isAdmin) {
    throw ApiException(HttpStatus.forbidden, 'Administrator access required.');
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
      'Content-Type, X-Local-Sync-Key, X-Local-Session',
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
  const ApiException(
    this.statusCode,
    this.message, {
    this.conflictType,
    this.conflictId,
    this.errorName,
  });

  final int statusCode;
  final String message;
  final String? conflictType;
  final String? conflictId;
  final String? errorName;

  Map<String, dynamic> toJson() {
    if (errorName != null) {
      final json = <String, dynamic>{'error': errorName, 'message': message};
      if (conflictId != null) json['conflictId'] = conflictId;
      if (conflictType != null) json['conflictType'] = conflictType;
      return json;
    }
    if (statusCode == HttpStatus.conflict) {
      final json = <String, dynamic>{
        'error': 'conflict',
        'message': message,
        'conflictType': conflictType ?? 'conflict',
      };
      if (conflictId != null) {
        json['conflictId'] = conflictId;
      }
      return json;
    }
    return {'error': message};
  }

  @override
  String toString() =>
      'ApiException($statusCode, $message'
      '${conflictType != null ? ', conflictType: $conflictType' : ''}'
      '${conflictId != null ? ', conflictId: $conflictId' : ''}'
      '${errorName != null ? ', errorName: $errorName' : ''})';
}

class DuplicateStoredRecordIdException implements Exception {
  const DuplicateStoredRecordIdException();

  @override
  String toString() => 'Stored records contain duplicate record IDs.';
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
      ),
      conflictsFile = File(
        '${dataDirectory.path}${Platform.pathSeparator}conflicts.json',
      ),
      _backupConflictsFile = File(
        '${dataDirectory.path}${Platform.pathSeparator}conflicts.json.bak',
      ),
      _collectorSessionsFile = File(
        '${dataDirectory.path}${Platform.pathSeparator}collector_sessions.json',
      ),
      _backupCollectorSessionsFile = File(
        '${dataDirectory.path}${Platform.pathSeparator}collector_sessions.json.bak',
      );

  final Directory _dataDirectory;
  final File recordsFile;
  final File _backupFile;
  final File conflictsFile;
  final File _backupConflictsFile;
  final File _collectorSessionsFile;
  final File _backupCollectorSessionsFile;
  final Map<String, Map<String, dynamic>> _records = {};
  final Map<String, Map<String, dynamic>> _conflicts = {};
  final Map<String, String> _collectorSessions = {};
  Future<void> _writeTail = Future<void>.value();
  bool _primaryWasCorrupt = false;
  bool _primaryConflictsWasCorrupt = false;
  bool _recordsRecoveredFromBackup = false;
  bool _conflictsRecoveredFromBackup = false;

  int get length => _records.length;
  int get conflictsCount => _conflicts.length;
  bool get recoveredFromBackup =>
      _recordsRecoveredFromBackup || _conflictsRecoveredFromBackup;

  Future<void> load() async {
    await _dataDirectory.create(recursive: true);
    final interruptedRestore = File(
      '${_dataDirectory.path}${Platform.pathSeparator}restore_in_progress.json',
    );
    if (await interruptedRestore.exists()) {
      throw StateError(
        'An interrupted restore was detected. Do not serve possibly mixed records. '
        'Run the backup utility recover action for ${_dataDirectory.path} first.',
      );
    }
    await _loadRecords();
    await _loadConflicts();
    // Session state is authorization state, not participant data. If a power
    // loss left only the previous .bak, or if the primary is corrupt, require
    // everyone to sign in again instead of reviving a superseded phone token.
    if (await _collectorSessionsFile.exists()) {
      try {
        final decoded = jsonDecode(await _collectorSessionsFile.readAsString());
        if (decoded is! Map<String, dynamic> ||
            decoded.values.any((value) => value is! String || value.isEmpty)) {
          throw const FormatException('collector_sessions.json is invalid.');
        }
        _collectorSessions.addAll(decoded.cast<String, String>());
      } on FileSystemException {
        _collectorSessions.clear();
      } on FormatException {
        _collectorSessions.clear();
      } on TypeError {
        _collectorSessions.clear();
      }
    }
  }

  bool isCurrentCollectorSession(String collectorId, String? token) =>
      token != null &&
      token.isNotEmpty &&
      _collectorSessions[collectorId] == token;

  Future<String> openCollectorSession(
    String collectorId,
  ) => _serialize(() async {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final token = base64Url.encode(bytes);
    final previous = _collectorSessions[collectorId];
    _collectorSessions[collectorId] = token;
    try {
      final temporary = File(
        '${_collectorSessionsFile.path}.tmp-$pid-${_random.nextInt(1 << 32)}',
      );
      await temporary.writeAsString(
        jsonEncode(_collectorSessions),
        flush: true,
      );
      try {
        if (await _collectorSessionsFile.exists()) {
          await _collectorSessionsFile.copy(_backupCollectorSessionsFile.path);
          await _collectorSessionsFile.delete();
        }
        await temporary.rename(_collectorSessionsFile.path);
      } catch (_) {
        if (!await _collectorSessionsFile.exists() &&
            await _backupCollectorSessionsFile.exists()) {
          await _backupCollectorSessionsFile.copy(_collectorSessionsFile.path);
        }
        rethrow;
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
      return token;
    } catch (_) {
      if (previous == null) {
        _collectorSessions.remove(collectorId);
      } else {
        _collectorSessions[collectorId] = previous;
      }
      rethrow;
    }
  });

  Future<void> _loadRecords() async {
    if (await recordsFile.exists()) {
      try {
        _records.addAll(await _readStoredRecords(recordsFile));
        return;
      } on DuplicateStoredRecordIdException {
        // Duplicate IDs are ambiguous canonical data, not a torn write. Do not
        // serve an older snapshot or allow a later write to replace the file.
        rethrow;
      } catch (error) {
        if (!await _backupFile.exists()) rethrow;
        _primaryWasCorrupt = true;
        _recordsRecoveredFromBackup = true;
        stderr.writeln(
          'Primary record file is invalid; loading previous snapshot.',
        );
      }
    }
    if (!await _backupFile.exists()) return;
    _recordsRecoveredFromBackup = true;
    _records.addAll(await _readStoredRecords(_backupFile));
    if (!_primaryWasCorrupt) {
      // A write may have been interrupted after moving the old primary aside.
      await _persist();
    }
  }

  Future<void> _loadConflicts() async {
    if (await conflictsFile.exists()) {
      try {
        _conflicts.addAll(await _readStoredConflicts(conflictsFile));
        return;
      } catch (error) {
        if (!await _backupConflictsFile.exists()) rethrow;
        _primaryConflictsWasCorrupt = true;
        _conflictsRecoveredFromBackup = true;
        stderr.writeln(
          'Primary conflicts file is invalid; loading previous snapshot.',
        );
      }
    }
    if (!await _backupConflictsFile.exists()) return;
    _conflictsRecoveredFromBackup = true;
    _conflicts.addAll(await _readStoredConflicts(_backupConflictsFile));
    if (!_primaryConflictsWasCorrupt) {
      await _persistConflicts();
    }
  }

  Future<Map<String, Map<String, dynamic>>> _readStoredRecords(
    File source,
  ) async {
    final decoded = jsonDecode(await source.readAsString());
    if (decoded is! List) {
      throw const FormatException('Stored records must be a JSON list.');
    }
    final loaded = <String, Map<String, dynamic>>{};
    for (final value in decoded) {
      if (value is! Map) {
        throw const FormatException('Stored record must be a JSON object.');
      }
      final record = _normalizeRecord(Map<String, dynamic>.from(value));
      final id = record['id'] as String;
      if (loaded.containsKey(id)) {
        throw const DuplicateStoredRecordIdException();
      }
      loaded[id] = record;
    }
    return loaded;
  }

  Future<Map<String, Map<String, dynamic>>> _readStoredConflicts(
    File source,
  ) async {
    final decoded = jsonDecode(await source.readAsString());
    if (decoded is! List) {
      throw const FormatException('Stored conflicts must be a JSON list.');
    }
    final loaded = <String, Map<String, dynamic>>{};
    for (final value in decoded) {
      if (value is! Map) {
        throw const FormatException('Stored conflict must be a JSON object.');
      }
      final conflict = Map<String, dynamic>.from(value);
      final id = conflict['id'] as String;
      loaded[id] = conflict;
    }
    return loaded;
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

  List<Map<String, dynamic>> conflicts() {
    final values = _conflicts.values.map(_clone).toList()
      ..sort(
        (left, right) => (right['createdAt'] as String).compareTo(
          left['createdAt'] as String,
        ),
      );
    return values;
  }

  Map<String, dynamic>? getConflict(String id) {
    final conflict = _conflicts[id];
    return conflict == null ? null : _clone(conflict);
  }

  Future<Map<String, dynamic>> reviewConflict(String id, {String? notes}) {
    return _serialize(() async {
      final conflict = _conflicts[id];
      if (conflict == null) {
        throw const ApiException(
          HttpStatus.notFound,
          'Conflict report not found.',
        );
      }
      if (conflict['status'] == 'resolved') {
        throw const ApiException(
          HttpStatus.conflict,
          'Resolved conflicts cannot be marked reviewed again.',
        );
      }
      final previous = _clone(conflict);
      conflict['status'] = 'reviewed';
      if (notes != null) {
        conflict['notes'] = notes;
      }
      conflict['reviewedAt'] = _now();
      try {
        await _persistConflicts();
      } catch (_) {
        _conflicts[id] = previous;
        rethrow;
      }
      return _clone(conflict);
    });
  }

  Future<Map<String, dynamic>> resolveConflict(
    String id,
    Map<String, dynamic> resolution,
  ) {
    return _serialize(() async {
      final conflict = _conflicts[id];
      if (conflict == null) {
        throw const ApiException(
          HttpStatus.notFound,
          'Conflict report not found.',
        );
      }
      if (conflict['status'] == 'resolved') return _clone(conflict);
      final rejected = Map<String, dynamic>.from(
        conflict['rejectedRecord'] as Map,
      );
      final record = _clone(rejected);

      // A rejected upload may have reused the ID of a valid stored visit.
      // Never let conflict resolution replace that visit. The administrator
      // must give the rejected upload a fresh record ID before accepting it.
      if (resolution['recordId'] != null) {
        record['id'] = resolution['recordId'];
      }
      final recordId = record['id'] as String;
      final uploadKey = record['idempotencyKey'];
      if (uploadKey != null &&
          _records.values.any(
            (stored) =>
                stored['id'] != record['id'] &&
                stored['idempotencyKey'] == uploadKey,
          )) {
        // Keep the original rejected key in the conflict report so retries
        // can be mapped to this accepted record, while giving the stored visit
        // its own unique upload key.
        record['idempotencyKey'] = 'resolved-$id';
      }

      if (resolution['studyId'] != null) {
        final participant = Map<String, dynamic>.from(
          record['participant'] as Map,
        );
        participant['studyId'] = resolution['studyId'];
        record['participant'] = participant;
      }
      if (resolution['visitNumber'] != null) {
        record['visitNumber'] = resolution['visitNumber'];
        if (record['confirmation'] != null) {
          final conf = Map<String, dynamic>.from(record['confirmation'] as Map);
          conf['visitNumber'] = resolution['visitNumber'];
          record['confirmation'] = conf;
        }
      }
      if (resolution['name'] != null) {
        final participant = Map<String, dynamic>.from(
          record['participant'] as Map,
        );
        participant['name'] = resolution['name'];
        record['participant'] = participant;
        if (record['confirmation'] != null) {
          final conf = Map<String, dynamic>.from(record['confirmation'] as Map);
          conf['name'] = resolution['name'];
          record['confirmation'] = conf;
        }
      }
      if (resolution['indianPhone'] != null) {
        final participant = Map<String, dynamic>.from(
          record['participant'] as Map,
        );
        participant['indianPhone'] = resolution['indianPhone'];
        record['participant'] = participant;
        if (record['confirmation'] != null) {
          final conf = Map<String, dynamic>.from(record['confirmation'] as Map);
          conf['indianPhone'] = resolution['indianPhone'];
          record['confirmation'] = conf;
        }
      }

      record
        ..['createdAt'] = record['createdAt'] ?? _now()
        ..['updatedAt'] = _now()
        ..['revision'] = record['revision'] ?? 1
        ..['syncState'] = 'synced';

      _validateRecord(record);
      final alreadyAccepted = _records[recordId];
      if (alreadyAccepted != null) {
        // Record data and conflict status live in separate files. A process
        // restart between their commits leaves the record accepted and the
        // report pending. Recognize that exact retry so the report can finish
        // resolving without ever replacing an unrelated visit.
        if (!_sameResolvedRecord(alreadyAccepted, record)) {
          throw const ApiException(
            HttpStatus.conflict,
            'Record ID already belongs to an accepted visit. Choose a new record ID.',
            conflictType: 'record_id_collision',
          );
        }
      } else {
        _requireUniqueUpload(record);
        await _saveRecord(recordId, record);
      }
      final previous = _clone(conflict);
      conflict['status'] = 'resolved';
      conflict['acceptedRecordId'] = recordId;
      conflict['resolution'] = _clone(resolution);
      conflict['resolvedAt'] = _now();
      try {
        await _persistConflicts();
      } catch (_) {
        _conflicts[id] = previous;
        rethrow;
      }

      return _clone(conflict);
    });
  }

  Map<String, dynamic> lookupParticipant(String phone) {
    final matchingRecords = _records.values.where((record) {
      if (_isArchived(record)) return false;
      final p = _participant(record);
      final storedPhone = (p['indianPhone'] as String?) ?? '';
      return _phoneMatches(storedPhone, phone);
    }).toList();

    if (matchingRecords.isEmpty) {
      return {'found': false};
    }

    final byStudyId = <String, Map<String, dynamic>>{};
    for (final r in matchingRecords) {
      final p = _participant(r);
      final studyId = p['studyId'] as String;
      final entry = byStudyId.putIfAbsent(
        studyId,
        () => {'studyId': studyId, 'name': p['name'], 'nextVisitNumber': 1},
      );
      final visit = r['visitNumber'];
      if (visit is int && visit >= (entry['nextVisitNumber'] as int)) {
        entry['nextVisitNumber'] = visit + 1;
      }
    }

    final participants = byStudyId.values.toList()
      ..sort(
        (a, b) => (a['studyId'] as String).compareTo(b['studyId'] as String),
      );
    if (participants.length > 1) {
      return {'found': true, 'ambiguous': true, 'participants': participants};
    }

    return {'found': true, 'participant': participants.single};
  }

  Future<Map<String, dynamic>> _recordConflict({
    required String conflictType,
    required String message,
    required Map<String, dynamic> incoming,
    required Map<String, dynamic> conflictingRecord,
  }) async {
    final incomingKey = incoming['idempotencyKey'] as String?;
    if (incomingKey != null) {
      for (final existingReport in _conflicts.values) {
        if (existingReport['idempotencyKey'] == incomingKey) {
          return existingReport;
        }
      }
    } else {
      final incomingId = incoming['id'] as String?;
      if (incomingId != null) {
        for (final existingReport in _conflicts.values) {
          if (existingReport['rejectedRecord']?['id'] == incomingId) {
            return existingReport;
          }
        }
      }
    }

    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final hash = _random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final conflictId = 'conflict-$timestamp-$hash';

    final report = <String, dynamic>{
      'id': conflictId,
      'conflictType': conflictType,
      'message': message,
      'createdAt': _now(),
      'collectorId': incoming['collectorId'],
      'idempotencyKey': incomingKey,
      'rejectedRecord': _clone(incoming),
      'conflictingRecordId': conflictingRecord['id'],
      'conflictingRecord': _clone(conflictingRecord),
      'status': 'pending',
      'resolution': null,
    };

    _conflicts[conflictId] = report;
    try {
      await _persistConflicts();
    } catch (_) {
      _conflicts.remove(conflictId);
      rethrow;
    }
    return report;
  }

  Future<void> _checkCollectorConflicts(Map<String, dynamic> incoming) async {
    final participant = _participant(incoming);
    for (final existing in _records.values) {
      if (existing['id'] == incoming['id']) continue;
      final other = _participant(existing);
      if (incoming['idempotencyKey'] != null &&
          incoming['idempotencyKey'] == existing['idempotencyKey']) {
        final report = await _recordConflict(
          conflictType: 'idempotency_collision',
          message: 'Upload key is already used.',
          incoming: incoming,
          conflictingRecord: existing,
        );
        throw ApiException(
          HttpStatus.conflict,
          'Upload key is already used.',
          conflictType: 'idempotency_collision',
          conflictId: report['id'] as String,
        );
      }
      if (participant['studyId'] == other['studyId'] &&
          participant['indianPhone'] != other['indianPhone']) {
        final report = await _recordConflict(
          conflictType: 'participant_mismatch',
          message: 'Participant number belongs to another phone. Resolve this conflict before syncing.',
          incoming: incoming,
          conflictingRecord: existing,
        );
        throw ApiException(
          HttpStatus.conflict,
          'Participant number belongs to another phone. Resolve this conflict before syncing.',
          conflictType: 'participant_mismatch',
          conflictId: report['id'] as String,
        );
      }
      if (participant['studyId'] == other['studyId'] &&
          participant['name'] != other['name']) {
        final report = await _recordConflict(
          conflictType: 'participant_mismatch',
          message: 'Participant number belongs to another name. Resolve this conflict before syncing.',
          incoming: incoming,
          conflictingRecord: existing,
        );
        throw ApiException(
          HttpStatus.conflict,
          'Participant number belongs to another name. Resolve this conflict before syncing.',
          conflictType: 'participant_mismatch',
          conflictId: report['id'] as String,
        );
      }
      if (participant['studyId'] == other['studyId'] &&
          incoming['visitNumber'] == existing['visitNumber']) {
        final report = await _recordConflict(
          conflictType: 'duplicate_visit',
          message: 'Visit number is already recorded for this participant.',
          incoming: incoming,
          conflictingRecord: existing,
        );
        throw ApiException(
          HttpStatus.conflict,
          'Visit number is already recorded for this participant.',
          conflictType: 'duplicate_visit',
          conflictId: report['id'] as String,
        );
      }
    }
  }

  Future<Map<String, dynamic>> upsertCollector(
    Map<String, dynamic> incoming, {
    String? authenticatedCollectorId,
    String? collectorSessionToken,
  }) {
    return _serialize(() async {
      // A newer login may have completed while this request body was arriving
      // or while the upload waited behind another store write. Check again at
      // the serialized write point so the accepted upload order is unambiguous.
      if (collectorSessionToken != null &&
          (authenticatedCollectorId == null ||
              !isCurrentCollectorSession(
                authenticatedCollectorId,
                collectorSessionToken,
              ))) {
        throw const ApiException(
          HttpStatus.unauthorized,
          'Collector session expired. Sign in again on this phone.',
          errorName: 'collector_session_expired',
        );
      }
      // Check if this record was previously conflicted and has now been resolved
      final incomingKey = incoming['idempotencyKey'] as String?;
      final incomingId = incoming['id'] as String?;
      for (final conflict in _conflicts.values) {
        if (conflict['status'] == 'resolved') {
          final matchesKey =
              incomingKey != null && conflict['idempotencyKey'] == incomingKey;
          final matchesId =
              incomingId != null &&
              conflict['rejectedRecord']?['id'] == incomingId;
          if (matchesKey || matchesId) {
            final acceptedId = conflict['acceptedRecordId'];
            final accepted = acceptedId is String ? _records[acceptedId] : null;
            if (accepted != null) {
              return _clone(accepted);
            }
          }
        }
      }

      final record = _normalizeRecord(incoming, allowMissingAuditFields: true);
      final id = record['id'] as String;
      final existing = _records[id];
      if (existing != null) {
        final previousKey = existing['idempotencyKey'];
        if (previousKey != incomingKey &&
            !(previousKey == null &&
                incomingKey != null &&
                existing['submittedAt'] == record['submittedAt'])) {
          final report = await _recordConflict(
            conflictType: 'idempotency_collision',
            message: 'Record ID was already used for a different upload.',
            incoming: record,
            conflictingRecord: existing,
          );
          throw ApiException(
            HttpStatus.conflict,
            'Record ID was already used for a different upload.',
            conflictType: 'idempotency_collision',
            conflictId: report['id'] as String,
          );
        }
        _requireCollectorMayUpdate(existing, record);
        // An upload retry must not increment the revision or restore stale
        // collector data over a later administrator correction.
        return _clone(existing);
      }
      if (_isArchived(record)) {
        throw const ApiException(
          HttpStatus.badRequest,
          'Collectors cannot create archived records.',
        );
      }

      // Check collector-scoped prefix on new participant
      if (authenticatedCollectorId != null) {
        final studyId = _participant(record)['studyId'] as String;
        final isNewParticipant = !_records.values.any(
          (r) => _participant(r)['studyId'] == studyId,
        );
        if (isNewParticipant) {
          final studyMatch = RegExp(r'^C(\d{2,3})-').firstMatch(studyId);
          if (studyMatch != null) {
            final studyCollectorNum = int.tryParse(studyMatch.group(1)!);
            final authCollectorNum = _extractCollectorNumber(
              authenticatedCollectorId,
            );
            if (studyCollectorNum != null &&
                authCollectorNum != null &&
                studyCollectorNum != authCollectorNum) {
              throw const ApiException(
                HttpStatus.badRequest,
                'Participant Study ID prefix does not match authenticated collector.',
              );
            }
          }
        }
      }

      await _checkCollectorConflicts(record);

      record
        ..['createdAt'] = _now()
        ..['updatedAt'] = _now()
        ..['revision'] = 1
        ..['syncState'] = 'synced';
      _validateRecord(record);
      await _saveRecord(id, record);
      return _clone(record);
    });
  }

  void _requireUniqueUpload(
    Map<String, dynamic> incoming, {
    String? excludeId,
  }) {
    final participant = _participant(incoming);
    for (final existing in _records.values) {
      if (existing['id'] == excludeId) continue;
      final other = _participant(existing);
      if (incoming['idempotencyKey'] != null &&
          incoming['idempotencyKey'] == existing['idempotencyKey']) {
        throw const ApiException(
          HttpStatus.conflict,
          'Upload key is already used.',
          conflictType: 'idempotency_collision',
        );
      }
      if (participant['studyId'] == other['studyId'] &&
          participant['indianPhone'] != other['indianPhone']) {
        throw const ApiException(
          HttpStatus.conflict,
          'Participant number belongs to another phone. Resolve this conflict before syncing.',
          conflictType: 'participant_mismatch',
        );
      }
      if (participant['studyId'] == other['studyId'] &&
          participant['name'] != other['name']) {
        throw const ApiException(
          HttpStatus.conflict,
          'Participant number belongs to another name. Resolve this conflict before syncing.',
          conflictType: 'participant_mismatch',
        );
      }
      if (participant['studyId'] == other['studyId'] &&
          incoming['visitNumber'] == existing['visitNumber']) {
        throw const ApiException(
          HttpStatus.conflict,
          'Visit number is already recorded for this participant.',
          conflictType: 'duplicate_visit',
        );
      }
    }
  }

  Future<Map<String, dynamic>> replaceAdmin(
    String id,
    Map<String, dynamic> incoming,
  ) {
    return _serialize(() async {
      final existing = _records[id];
      if (existing == null) {
        throw const ApiException(HttpStatus.notFound, 'Record not found.');
      }
      final record = _normalizeRecord(incoming, allowMissingAuditFields: true);
      if (record['id'] != id) {
        throw const ApiException(
          HttpStatus.badRequest,
          'Body id must match the record URL.',
        );
      }
      // Preserve existing questionnaire if incoming is omitted or null
      if (incoming['questionnaire'] == null &&
          existing['questionnaire'] != null) {
        record['questionnaire'] = existing['questionnaire'] is Map
            ? _clone(
                Map<String, dynamic>.from(existing['questionnaire'] as Map),
              )
            : existing['questionnaire'];
      }
      _requireAdminImmutableFields(existing, record);
      _requireUniqueUpload(record, excludeId: id);
      record
        ..['createdAt'] = existing['createdAt']
        ..['updatedAt'] = _now()
        ..['revision'] = (existing['revision'] as int) + 1;
      record['idempotencyKey'] = existing['idempotencyKey'];
      _copyArchiveMarker(existing, record);
      _validateRecord(record);
      await _saveRecord(id, record);
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
      await _saveRecord(id, record);
      return _clone(record);
    });
  }

  Future<void> _saveRecord(String id, Map<String, dynamic> record) async {
    final previous = _records[id];
    _records[id] = record;
    try {
      await _persist();
    } catch (_) {
      if (previous == null) {
        _records.remove(id);
      } else {
        _records[id] = previous;
      }
      rethrow;
    }
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
      if (await recordsFile.exists() && !_primaryWasCorrupt) {
        // Retain the last successfully committed state, not just a transient
        // rename fallback. Never replace a valid backup with a corrupt primary.
        await recordsFile.copy(_backupFile.path);
      }
      try {
        await temporary.rename(recordsFile.path);
      } on FileSystemException {
        // Windows cannot replace an existing file with rename. Move the old
        // primary aside before installing the flushed temporary file.
        if (await recordsFile.exists()) {
          if (_primaryWasCorrupt) {
            await recordsFile.rename(
              '${recordsFile.path}.corrupt-$pid-${_random.nextInt(1 << 32)}',
            );
          } else {
            if (await _backupFile.exists()) await _backupFile.delete();
            await recordsFile.rename(_backupFile.path);
          }
        }
        await temporary.rename(recordsFile.path);
      }
      _primaryWasCorrupt = false;
    } catch (_) {
      if (_primaryWasCorrupt || !await recordsFile.exists()) {
        if (!await recordsFile.exists() && await _backupFile.exists()) {
          await _backupFile.copy(recordsFile.path);
        }
      }
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _persistConflicts() async {
    await _dataDirectory.create(recursive: true);
    final temporary = File(
      '${conflictsFile.path}.tmp-$pid-${_random.nextInt(1 << 32)}',
    );
    await temporary.writeAsString(jsonEncode(conflicts()), flush: true);
    try {
      if (await conflictsFile.exists() && !_primaryConflictsWasCorrupt) {
        await conflictsFile.copy(_backupConflictsFile.path);
      }
      try {
        await temporary.rename(conflictsFile.path);
      } on FileSystemException {
        if (await conflictsFile.exists()) {
          if (_primaryConflictsWasCorrupt) {
            await conflictsFile.rename(
              '${conflictsFile.path}.corrupt-$pid-${_random.nextInt(1 << 32)}',
            );
          } else {
            if (await _backupConflictsFile.exists()) {
              await _backupConflictsFile.delete();
            }
            await conflictsFile.rename(_backupConflictsFile.path);
          }
        }
        await temporary.rename(conflictsFile.path);
      }
      _primaryConflictsWasCorrupt = false;
    } catch (_) {
      if (_primaryConflictsWasCorrupt || !await conflictsFile.exists()) {
        if (!await conflictsFile.exists() &&
            await _backupConflictsFile.exists()) {
          await _backupConflictsFile.copy(conflictsFile.path);
        }
      }
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
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
  'idempotencyKey',
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
    'idempotencyKey',
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
  if (record['idempotencyKey'] != null) {
    _requireText(record['idempotencyKey'], 'idempotencyKey');
  }
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
  final studyId = participantMap['studyId'] as String;
  final collectorIdMatch = RegExp(r'^C(\d{2,3})-(\d{6,})$').firstMatch(studyId);
  final legacyIdMatch = RegExp(r'^P(\d{3,})$').firstMatch(studyId);
  final validCollectorId =
      collectorIdMatch != null &&
      (int.tryParse(collectorIdMatch.group(1)!) ?? 0) > 0 &&
      (int.tryParse(collectorIdMatch.group(1)!) ?? 0) <= 99 &&
      (BigInt.tryParse(collectorIdMatch.group(2)!) ?? BigInt.zero) >
          BigInt.zero;
  final validLegacyId =
      legacyIdMatch != null &&
      (BigInt.tryParse(legacyIdMatch.group(1)!) ?? BigInt.zero) > BigInt.zero;
  if (!validCollectorId && !validLegacyId) {
    throw const ApiException(
      HttpStatus.badRequest,
      'participant.studyId must be a positive C01-000001-style or legacy P001-style number.',
    );
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
    throw ApiException(
      HttpStatus.badRequest,
      'questionnaire must be an object.',
    );
  }
  final questionnaire = Map<String, dynamic>.from(value);
  final version = questionnaire['schemaVersion'] ?? 1;
  if (version is! int || (version != 1 && version != 2)) {
    throw ApiException(
      HttpStatus.badRequest,
      'questionnaire.schemaVersion must be 1 or 2.',
    );
  }
  const requiredText = {
    'studySite',
    'sex',
    'education',
    'employment',
    'fruitFrequency',
    'vegetableFrequency',
    'sugaryDrinkFrequency',
    'processedFoodFrequency',
  };
  const requiredNumbers = {
    'age',
    'activeDaysPerWeek',
    'activeMinutesPerDay',
    'sleepHours',
    'weeklyActiveMinutes',
  };
  const derivedNumbers = {'bmi', 'averageSystolic', 'averageDiastolic'};
  const measurementFields = {
    'heightCm',
    'weightKg',
    'waistCm',
    'bpOneSystolic',
    'bpOneDiastolic',
    'bpTwoSystolic',
    'bpTwoDiastolic',
  };
  const missingReasonFields = {
    'heightMissingReason',
    'weightMissingReason',
    'waistMissingReason',
    'bpOneMissingReason',
    'bpTwoMissingReason',
  };
  final allowed = {
    ...requiredText,
    ...requiredNumbers,
    ...derivedNumbers,
    ...measurementFields,
    ...missingReasonFields,
    'schemaVersion',
    'tobaccoUse',
    'tobaccoType',
    'tobaccoFrequency',
    'alcoholPast30Days',
    'alcoholFrequency',
    'hypertensionDiagnosis',
    'diabetesDiagnosis',
    'highCholesterolDiagnosis',
    'cardiovascularDiagnosis',
  };
  final requiredFields = {
    ...requiredText,
    ...requiredNumbers,
    ...derivedNumbers,
    ...measurementFields,
  };
  if (questionnaire.keys.any((key) => !allowed.contains(key)) ||
      !questionnaire.keys.toSet().containsAll(requiredFields)) {
    throw ApiException(
      HttpStatus.badRequest,
      'questionnaire has an invalid shape.',
    );
  }
  for (final field in requiredText) {
    _requireText(questionnaire[field], 'questionnaire.$field');
  }
  for (final field in requiredNumbers) {
    if (questionnaire[field] is! num) {
      throw ApiException(
        HttpStatus.badRequest,
        'questionnaire.$field must be numeric.',
      );
    }
  }
  for (final field in derivedNumbers) {
    if (questionnaire[field] != null && questionnaire[field] is! num) {
      throw ApiException(
        HttpStatus.badRequest,
        'questionnaire.$field must be numeric or null.',
      );
    }
  }
  final age = questionnaire['age'] as num;
  final days = questionnaire['activeDaysPerWeek'] as num;
  if (age < 18 || age > 120 || days < 0 || days > 7) {
    throw ApiException(
      HttpStatus.badRequest,
      'questionnaire values are outside allowed ranges.',
    );
  }
  final isV2 = version == 2;
  void validateOptionalMeasurement(String field, String reasonField) {
    final measurement = questionnaire[field];
    final reason = questionnaire[reasonField];
    if (reason != null && reason is! String) {
      throw ApiException(
        HttpStatus.badRequest,
        'questionnaire.$reasonField must be text or null.',
      );
    }
    if (measurement == null) {
      if (!isV2 || (reason != 'unable' && reason != 'declined')) {
        throw ApiException(
          HttpStatus.badRequest,
          'questionnaire.$reasonField must be unable or declined when $field is missing.',
        );
      }
      return;
    }
    if (measurement is! num || measurement <= 0 || reason != null) {
      throw ApiException(
        HttpStatus.badRequest,
        'questionnaire.$field must be positive numeric and cannot have a missing reason.',
      );
    }
  }

  validateOptionalMeasurement('heightCm', 'heightMissingReason');
  validateOptionalMeasurement('weightKg', 'weightMissingReason');
  validateOptionalMeasurement('waistCm', 'waistMissingReason');

  void validateBloodPressurePair({
    required String systolicField,
    required String diastolicField,
    required String reasonField,
  }) {
    final systolic = questionnaire[systolicField];
    final diastolic = questionnaire[diastolicField];
    final reason = questionnaire[reasonField];
    if (reason != null && reason is! String) {
      throw ApiException(
        HttpStatus.badRequest,
        'questionnaire.$reasonField must be text or null.',
      );
    }
    if (systolic == null || diastolic == null) {
      if (!isV2 ||
          systolic != null ||
          diastolic != null ||
          (reason != 'unable' && reason != 'declined')) {
        throw ApiException(
          HttpStatus.badRequest,
          'questionnaire.$reasonField must be unable or declined when both blood pressure readings are missing.',
        );
      }
      return;
    }
    if (systolic is! num ||
        diastolic is! num ||
        systolic <= 0 ||
        diastolic <= 0 ||
        reason != null) {
      throw ApiException(
        HttpStatus.badRequest,
        'questionnaire.$systolicField and $diastolicField must be positive numeric and cannot have a missing reason.',
      );
    }
  }

  validateBloodPressurePair(
    systolicField: 'bpOneSystolic',
    diastolicField: 'bpOneDiastolic',
    reasonField: 'bpOneMissingReason',
  );
  validateBloodPressurePair(
    systolicField: 'bpTwoSystolic',
    diastolicField: 'bpTwoDiastolic',
    reasonField: 'bpTwoMissingReason',
  );
  final weekly =
      (questionnaire['activeDaysPerWeek'] as num) *
      (questionnaire['activeMinutesPerDay'] as num);
  final height = questionnaire['heightCm'] as num?;
  final weight = questionnaire['weightKg'] as num?;
  final bmi = height == null || weight == null
      ? null
      : weight / ((height / 100) * (height / 100));
  final bpOneSystolic = questionnaire['bpOneSystolic'] as num?;
  final bpOneDiastolic = questionnaire['bpOneDiastolic'] as num?;
  final bpTwoSystolic = questionnaire['bpTwoSystolic'] as num?;
  final bpTwoDiastolic = questionnaire['bpTwoDiastolic'] as num?;
  final averageSystolic = bpOneSystolic == null || bpTwoSystolic == null
      ? null
      : (bpOneSystolic + bpTwoSystolic) / 2;
  final averageDiastolic = bpOneDiastolic == null || bpTwoDiastolic == null
      ? null
      : (bpOneDiastolic + bpTwoDiastolic) / 2;
  bool differs(Object? actual, num? expected) {
    if (expected == null) return actual != null;
    return actual is! num || (actual - expected).abs() > 0.0001;
  }

  if (differs(questionnaire['weeklyActiveMinutes'], weekly) ||
      differs(questionnaire['bmi'], bmi) ||
      differs(questionnaire['averageSystolic'], averageSystolic) ||
      differs(questionnaire['averageDiastolic'], averageDiastolic)) {
    throw ApiException(
      HttpStatus.badRequest,
      'questionnaire derived values do not match the recorded measurements.',
    );
  }
  for (final field in allowed.difference({
    ...requiredText,
    ...requiredNumbers,
    ...derivedNumbers,
    ...measurementFields,
    ...missingReasonFields,
    'schemaVersion',
  })) {
    final item = questionnaire[field];
    if (item != null && item is! String) {
      throw ApiException(
        HttpStatus.badRequest,
        'questionnaire.$field must be text or null.',
      );
    }
  }
}

void _requireCollectorMayUpdate(
  Map<String, dynamic> existing,
  Map<String, dynamic> incoming,
) {
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

bool _sameResolvedRecord(
  Map<String, dynamic> accepted,
  Map<String, dynamic> candidate,
) {
  final acceptedContent = _clone(accepted)
    ..remove('createdAt')
    ..remove('updatedAt')
    ..remove('revision')
    ..remove('syncState');
  final candidateContent = _clone(candidate)
    ..remove('createdAt')
    ..remove('updatedAt')
    ..remove('revision')
    ..remove('syncState');
  return jsonEncode(_canonicalJsonValue(acceptedContent)) ==
      jsonEncode(_canonicalJsonValue(candidateContent));
}

Object? _canonicalJsonValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonicalJsonValue(value[key])};
  }
  if (value is List) return value.map(_canonicalJsonValue).toList();
  return value;
}

bool _isArchived(Map<String, dynamic> record) => record['archivedAt'] != null;

int? _extractCollectorNumber(String collectorId) {
  final match = RegExp(
    r'^C(\d+)$',
    caseSensitive: false,
  ).firstMatch(collectorId.trim());
  if (match != null) {
    return int.tryParse(match.group(1)!);
  }
  final matchDigits = RegExp(r'(\d+)$').firstMatch(collectorId.trim());
  if (matchDigits != null) {
    return int.tryParse(matchDigits.group(1)!);
  }
  return null;
}

bool _phoneMatches(String storedPhone, String queryPhone) {
  final cleanStored = storedPhone.trim();
  final cleanQuery = queryPhone.trim();
  if (cleanStored == cleanQuery) return true;
  final digitsStored = cleanStored.replaceAll(RegExp(r'\D'), '');
  final digitsQuery = cleanQuery.replaceAll(RegExp(r'\D'), '');
  if (digitsStored.isNotEmpty && digitsStored == digitsQuery) return true;
  if (digitsStored.length >= 10 &&
      digitsQuery.length == 10 &&
      digitsStored.endsWith(digitsQuery)) {
    return true;
  }
  return false;
}

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
