import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Durable boundary for collector-owned records waiting to be synchronized.
///
/// Keeping this interface independent from the UI makes the encrypted pilot
/// store replaceable by a database without changing the collector workflow.
abstract interface class LocalRecordStore {
  Future<List<Map<String, Object?>>> readAll();

  Future<void> writeAll(List<Map<String, Object?>> records);
}

class SecureLocalRecordStore implements LocalRecordStore {
  SecureLocalRecordStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _recordsKey = 'collector_records_v1';

  final FlutterSecureStorage _storage;

  @override
  Future<List<Map<String, Object?>>> readAll() async {
    final encoded = await _storage.read(key: _recordsKey);
    if (encoded == null || encoded.isEmpty) return [];

    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw const FormatException('Stored collector records are not a list.');
    }
    return decoded
        .map((item) {
          if (item is! Map) {
            throw const FormatException(
              'A stored collector record is invalid.',
            );
          }
          return item.map((key, value) => MapEntry(key.toString(), value));
        })
        .toList(growable: false);
  }

  @override
  Future<void> writeAll(List<Map<String, Object?>> records) =>
      _storage.write(key: _recordsKey, value: jsonEncode(records));
}
