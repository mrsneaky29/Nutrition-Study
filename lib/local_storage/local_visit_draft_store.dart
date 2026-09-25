import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Durable storage for unfinished collector visits, separate from submissions.
abstract interface class LocalVisitDraftStore {
  Future<List<Map<String, Object?>>> readAll();

  Future<void> writeAll(List<Map<String, Object?>> drafts);
}

class SecureLocalVisitDraftStore implements LocalVisitDraftStore {
  SecureLocalVisitDraftStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _draftsKey = 'collector_visit_drafts_v1';

  final FlutterSecureStorage _storage;

  @override
  Future<List<Map<String, Object?>>> readAll() async {
    final encoded = await _storage.read(key: _draftsKey);
    if (encoded == null || encoded.isEmpty) return [];

    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw const FormatException('Stored visit drafts are not a list.');
    }
    return decoded
        .map(
          (item) => item is Map
              ? item.map((key, value) => MapEntry(key.toString(), value))
              : <String, Object?>{'_invalidStoredVisitDraftEntry': true},
        )
        .toList(growable: false);
  }

  @override
  Future<void> writeAll(List<Map<String, Object?>> drafts) =>
      _storage.write(key: _draftsKey, value: jsonEncode(drafts));
}

/// Test-only fallback when a widget test injects records but no secure store.
class InMemoryLocalVisitDraftStore implements LocalVisitDraftStore {
  List<Map<String, Object?>> _drafts = [];

  @override
  Future<List<Map<String, Object?>>> readAll() async => _copy(_drafts);

  @override
  Future<void> writeAll(List<Map<String, Object?>> drafts) async {
    _drafts = _copy(drafts);
  }

  static List<Map<String, Object?>> _copy(List<Map<String, Object?>> drafts) =>
      (jsonDecode(jsonEncode(drafts)) as List)
          .map(
            (item) => (item as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
          .toList(growable: false);
}
