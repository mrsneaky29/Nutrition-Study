import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'local_record_sync_gateway.dart';

/// HTTP implementation for the optional collector-to-PC LAN connection.
///
/// Configure it only for a physical LAN build, for example with
/// `--dart-define=LOCAL_API_BASE_URL=http://192.168.1.20:8787`. Without that
/// value, records intentionally remain local and pending for synchronization.
class HttpLocalRecordSyncClient implements LocalRecordSyncGateway {
  HttpLocalRecordSyncClient({
    http.Client? client,
    String? apiBaseUrl,
    this.timeout = const Duration(seconds: 5),
  }) : _client = client ?? http.Client(),
       _apiBaseUrl = apiBaseUrl ?? configuredApiBaseUrl;

  static const configuredApiBaseUrl = String.fromEnvironment(
    'LOCAL_API_BASE_URL',
    defaultValue: '',
  );
  static const configuredApiKey = String.fromEnvironment('LOCAL_API_KEY');

  final http.Client _client;
  final String _apiBaseUrl;
  final Duration timeout;

  @override
  Future<LocalRecordSyncResult> sendRecord(Map<String, Object?> record) async {
    final endpoint = _recordsEndpoint;
    if (endpoint == null) return LocalRecordSyncResult.pending;

    try {
      final response = await _client
          .post(
            endpoint,
            headers: const {
              'content-type': 'application/json',
              'x-local-sync-key': configuredApiKey,
            },
            body: jsonEncode(record),
          )
          .timeout(timeout);
      return response.statusCode >= 200 && response.statusCode < 300
          ? LocalRecordSyncResult.synced
          : LocalRecordSyncResult.failed;
    } on TimeoutException {
      return LocalRecordSyncResult.pending;
    } on http.ClientException {
      return LocalRecordSyncResult.pending;
    } on FormatException {
      return LocalRecordSyncResult.pending;
    } catch (_) {
      // Network availability must never prevent a collector from retaining a
      // completed visit locally. The next home/manual retry can try again.
      return LocalRecordSyncResult.pending;
    }
  }

  Uri? get _recordsEndpoint {
    final base = _apiBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (base.isEmpty) return null;
    final uri = Uri.tryParse(base);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return Uri.tryParse('$base/records');
  }
}
