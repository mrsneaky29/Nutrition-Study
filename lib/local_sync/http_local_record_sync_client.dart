import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/participant_id.dart';
import 'local_record_sync_gateway.dart';

/// The collector number has been signed in on another phone.
class CollectorSessionExpiredException implements Exception {
  const CollectorSessionExpiredException();

  @override
  String toString() => 'Collector session expired. Sign in again.';
}

/// HTTP implementation for the optional collector-to-server connection.
///
/// Configure it for a local LAN build with
/// `--dart-define=LOCAL_API_BASE_URL=http://192.168.1.20:8787`, or provide a
/// trusted HTTPS base URL in a public collector release. Without a base URL,
/// records intentionally remain local and pending for synchronization.
class HttpLocalRecordSyncClient implements LocalRecordSyncGateway {
  HttpLocalRecordSyncClient({
    http.Client? client,
    String? apiBaseUrl,
    String? apiKey,
    this.sessionToken,
    this.timeout = const Duration(seconds: 5),
    this.requireHttps = false,
  }) : _client = client ?? http.Client(),
       _apiBaseUrl = apiBaseUrl ?? configuredApiBaseUrl,
       _apiKey = apiKey ?? configuredApiKey;

  static const configuredApiBaseUrl = String.fromEnvironment(
    'LOCAL_API_BASE_URL',
    defaultValue: '',
  );
  static const configuredApiKey = String.fromEnvironment('LOCAL_API_KEY');

  final http.Client _client;
  final String _apiBaseUrl;
  final String _apiKey;

  /// Requires a clean HTTPS origin, as used by public collector releases.
  /// Kept opt-in so local LAN builds retain their HTTP behavior.
  final bool requireHttps;
  String? sessionToken;
  final Duration timeout;

  /// Whether [value] is an absolute server base URL safe for this client.
  /// Query strings, fragments, and user information are never part of a base
  /// endpoint. Public releases can additionally require HTTPS.
  static bool isValidApiBaseUrl(String value, {bool requireHttps = false}) {
    final input = value.trim();
    if (input.isEmpty || input.contains(RegExp(r'\s'))) return false;
    final uri = Uri.tryParse(input);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (requireHttps && uri.scheme != 'https') return false;
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      return false;
    }
    return true;
  }

  Uri? _endpoint(String suffix) {
    final base = _apiBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (!isValidApiBaseUrl(base, requireHttps: requireHttps)) return null;
    return Uri.tryParse('$base/$suffix');
  }

  /// A new successful login supersedes the previous phone for this collector.
  Future<String> startSession(String collectorId) async {
    final endpoint = _endpoint('collector/session');
    if (endpoint == null) {
      throw const FormatException('Enter a valid server address.');
    }
    final response = await _client
        .post(
          endpoint,
          headers: {
            'content-type': 'application/json',
            'x-local-sync-key': _apiKey,
          },
          body: jsonEncode({'collectorId': collectorId}),
        )
        .timeout(timeout);
    final body = _tryParseJsonMap(response.body);
    if (response.statusCode != 200 ||
        body?['sessionToken'] is! String ||
        body?['collectorId'] != collectorId) {
      throw StateError(
        body?['error']?.toString() ??
            'Collector login failed (${response.statusCode}).',
      );
    }
    sessionToken = body!['sessionToken'] as String;
    return sessionToken!;
  }

  SyncResponse? _lastResponse;

  /// The most recent [SyncResponse], preserving status code, message, and conflict details.
  SyncResponse? get lastResponse => _lastResponse;

  /// Returns [lastResponse] if the previous sync resulted in a conflict, or null otherwise.
  SyncResponse? get lastConflict =>
      _lastResponse?.isConflict == true ? _lastResponse : null;

  /// The error message / explanation from the last conflict response, if any.
  String? get lastConflictMessage => lastConflict?.message;

  /// The conflict type from the last conflict response (e.g. 'participant_mismatch'), if any.
  String? get lastConflictType => lastConflict?.conflictType;

  /// The conflict ID from the last conflict response, if any.
  String? get lastConflictId => lastConflict?.conflictId;

  @override
  Future<LocalRecordSyncResult> sendRecord(Map<String, Object?> record) async {
    final response = await sendRecordDetailed(record);
    return response.result;
  }

  @override
  Future<ParticipantLookupResult> lookupParticipant(
    String phone, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final endpoint = _participantLookupUri(phone);
    if (endpoint == null) {
      return const ParticipantLookupResult.offline();
    }

    try {
      final response = await _client
          .get(
            endpoint,
            headers: {
              'x-local-sync-key': _apiKey,
              if (sessionToken case final String token)
                'x-local-session': token,
            },
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final body = _tryParseJsonMap(response.body);
        if (body == null) return const ParticipantLookupResult.offline();
        if (body['found'] == false) {
          return const ParticipantLookupResult.notFound();
        }
        if (body['found'] == true) {
          if (body['ambiguous'] == true) {
            final raw = body['participants'];
            if (raw is! List || raw.length < 2) {
              return const ParticipantLookupResult.offline();
            }
            final candidates = <ParticipantLookupCandidate>[];
            final ids = <String>{};
            for (final item in raw) {
              if (item is! Map) return const ParticipantLookupResult.offline();
              final id = normalizeParticipantStudyId(
                item['studyId'] as String?,
              );
              final name = item['name'];
              final nextVisit = item['nextVisitNumber'];
              if (id == null ||
                  name is! String ||
                  name.trim().isEmpty ||
                  nextVisit is! int ||
                  nextVisit < 2 ||
                  !ids.add(id)) {
                return const ParticipantLookupResult.offline();
              }
              candidates.add(
                ParticipantLookupCandidate(
                  studyId: id,
                  name: name.trim(),
                  nextVisitNumber: nextVisit,
                ),
              );
            }
            return ParticipantLookupResult.ambiguous(candidates);
          }
          final participant = body['participant'];
          if (participant is Map) {
            final nextVisit = participant['nextVisitNumber'];
            final id = normalizeParticipantStudyId(
              participant['studyId'] as String?,
            );
            final name = participant['name'];
            if (id == null ||
                name is! String ||
                name.trim().isEmpty ||
                nextVisit is! int ||
                nextVisit < 2) {
              return const ParticipantLookupResult.offline();
            }
            return ParticipantLookupResult.found(
              studyId: id,
              name: name.trim(),
              nextVisitNumber: nextVisit,
            );
          }
          return const ParticipantLookupResult.offline();
        }
        return const ParticipantLookupResult.offline();
      }

      if (response.statusCode == 404) {
        return const ParticipantLookupResult.notFound();
      }

      if (response.statusCode == HttpStatus.unauthorized) {
        throw const CollectorSessionExpiredException();
      }

      return const ParticipantLookupResult.offline();
    } on CollectorSessionExpiredException {
      rethrow;
    } on TimeoutException {
      return const ParticipantLookupResult.offline();
    } on SocketException {
      return const ParticipantLookupResult.offline();
    } on http.ClientException {
      return const ParticipantLookupResult.offline();
    } catch (_) {
      return const ParticipantLookupResult.offline();
    }
  }

  /// Sends a record to the configured LAN service, returning a rich [SyncResponse]
  /// that preserves HTTP status code, conflict details, or error explanations.
  Future<SyncResponse> sendRecordDetailed(Map<String, Object?> record) async {
    final endpoint = _recordsEndpoint;
    if (endpoint == null) {
      final response = const SyncResponse.pending(
        message: 'No physical LAN endpoint configured.',
      );
      _lastResponse = response;
      return response;
    }

    try {
      final response = await _client
          .post(
            endpoint,
            headers: {
              'content-type': 'application/json',
              'x-local-sync-key': _apiKey,
              if (sessionToken case final String token)
                'x-local-session': token,
            },
            body: jsonEncode(record),
          )
          .timeout(timeout);

      final statusCode = response.statusCode;
      if (statusCode >= 200 && statusCode < 300) {
        final syncResponse = SyncResponse.synced(
          statusCode: statusCode,
          body: _tryParseJsonMap(response.body),
          rawBody: response.body,
        );
        _lastResponse = syncResponse;
        return syncResponse;
      }

      if (statusCode == 409) {
        final parsed = _parseConflictBody(response.body);
        final syncResponse = SyncResponse.conflict(
          statusCode: statusCode,
          message: parsed.message,
          conflictType: parsed.conflictType,
          conflictId: parsed.conflictId,
          body: parsed.body,
          rawBody: response.body,
        );
        _lastResponse = syncResponse;
        return syncResponse;
      }

      final parsed = _parseConflictBody(response.body);
      final syncResponse = SyncResponse.failed(
        statusCode: statusCode,
        message: parsed.message,
        body: parsed.body,
        rawBody: response.body,
      );
      _lastResponse = syncResponse;
      return syncResponse;
    } on TimeoutException catch (e) {
      final detail =
          (e.message != null &&
              e.message!.isNotEmpty &&
              e.message != 'Future not completed')
          ? e.message!
          : 'Network request timed out after ${timeout.inSeconds}s';
      final syncResponse = SyncResponse.pending(message: detail);
      _lastResponse = syncResponse;
      return syncResponse;
    } on SocketException catch (e) {
      final syncResponse = SyncResponse.pending(
        message: 'Network socket error: ${e.message}',
      );
      _lastResponse = syncResponse;
      return syncResponse;
    } on http.ClientException catch (e) {
      final syncResponse = SyncResponse.pending(
        message: 'HTTP client connection error: ${e.message}',
      );
      _lastResponse = syncResponse;
      return syncResponse;
    } on FormatException catch (e) {
      final syncResponse = SyncResponse.pending(
        message: 'Format error: ${e.message}',
      );
      _lastResponse = syncResponse;
      return syncResponse;
    } catch (e) {
      // Network availability must never prevent a collector from retaining a
      // completed visit locally. The next home/manual retry can try again.
      final syncResponse = SyncResponse.pending(message: e.toString());
      _lastResponse = syncResponse;
      return syncResponse;
    }
  }

  /// Alias for [sendRecordDetailed].
  Future<SyncResponse> syncRecord(Map<String, Object?> record) =>
      sendRecordDetailed(record);

  Uri? get _recordsEndpoint {
    return _endpoint('records');
  }

  Uri? _participantLookupUri(String phone) {
    final endpoint = _endpoint('participants/lookup');
    return endpoint?.replace(queryParameters: {'phone': phone});
  }

  static Map<String, Object?>? _tryParseJsonMap(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.cast<String, Object?>();
      }
    } catch (_) {}
    return null;
  }

  static ({
    String? message,
    String? conflictType,
    String? conflictId,
    Map<String, Object?>? body,
  })
  _parseConflictBody(String raw) {
    if (raw.trim().isEmpty) {
      return (message: null, conflictType: null, conflictId: null, body: null);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final map = decoded.cast<String, Object?>();
        final conflictType = map['conflictType'] as String?;
        final conflictId = (map['conflictId'] ?? map['conflict_id']) as String?;
        String? message;
        if (map['message'] is String && (map['message'] as String).isNotEmpty) {
          message = map['message'] as String;
        } else if (map['reason'] is String &&
            (map['reason'] as String).isNotEmpty) {
          message = map['reason'] as String;
        } else if (map['error'] is String &&
            (map['error'] as String).isNotEmpty) {
          message = map['error'] as String;
        }
        return (
          message: message,
          conflictType: conflictType,
          conflictId: conflictId,
          body: map,
        );
      } else if (decoded is String) {
        return (
          message: decoded,
          conflictType: null,
          conflictId: null,
          body: null,
        );
      }
    } catch (_) {
      final trimmed = raw.trim();
      return (
        message: trimmed.isNotEmpty ? trimmed : null,
        conflictType: null,
        conflictId: null,
        body: null,
      );
    }
    return (message: null, conflictType: null, conflictId: null, body: null);
  }
}

/// Extension to allow callers with a [LocalRecordSyncGateway] interface reference
/// to access detailed responses if the implementation supports it.
extension HttpLocalRecordSyncGatewayX on LocalRecordSyncGateway {
  Future<SyncResponse> sendRecordDetailed(Map<String, Object?> record) async {
    final self = this;
    if (self is HttpLocalRecordSyncClient) {
      return self.sendRecordDetailed(record);
    }
    final result = await sendRecord(record);
    return SyncResponse(result: result);
  }

  SyncResponse? get lastResponse {
    final self = this;
    if (self is HttpLocalRecordSyncClient) {
      return self.lastResponse;
    }
    return null;
  }
}
