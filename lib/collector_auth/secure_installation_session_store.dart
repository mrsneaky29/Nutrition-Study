import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'collector_access.dart';

/// Small seam around the package API, allowing the secure persistence contract
/// to be tested without a platform channel.
abstract interface class SecureInstallationSessionStorage {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class FlutterSecureInstallationSessionStorage
    implements SecureInstallationSessionStorage {
  FlutterSecureInstallationSessionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);
}

/// Stores a collector installation session in encrypted platform storage.
///
/// Invalid or incomplete persisted data is rejected, never converted into a
/// usable session. Callers can clear it and require a fresh code claim.
class SecureInstallationSessionStore implements InstallationSessionStore {
  SecureInstallationSessionStore({
    SecureInstallationSessionStorage? storage,
  }) : _storage = storage ?? FlutterSecureInstallationSessionStorage();

  static const storageKey = 'collector_installation_session_v1';

  final SecureInstallationSessionStorage _storage;

  @override
  Future<void> clear() => _storage.delete(key: storageKey);

  @override
  Future<CollectorInstallationSession?> read() async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('Session is not an object.');
      final values = Map<String, Object?>.from(decoded);
      _requireExactKeys(values);
      final issuedAt = DateTime.tryParse(_text(values, 'issuedAt'));
      if (issuedAt == null) {
        throw const FormatException('Session issuedAt is invalid.');
      }
      return CollectorInstallationSession(
        collectorId: _text(values, 'collectorId'),
        collectorCode: CollectorCode(_text(values, 'collectorCode')),
        installationId: _text(values, 'installationId'),
        accessToken: _text(values, 'accessToken'),
        issuedAt: issuedAt.toUtc(),
      );
    } on FormatException {
      rethrow;
    } on ArgumentError catch (error) {
      throw FormatException('Stored collector session is invalid: $error');
    } on Object catch (error) {
      throw FormatException('Stored collector session cannot be read: $error');
    }
  }

  @override
  Future<void> write(CollectorInstallationSession session) => _storage.write(
    key: storageKey,
    value: jsonEncode({
      'collectorId': session.collectorId,
      'collectorCode': session.collectorCode.value,
      'installationId': session.installationId,
      'accessToken': session.accessToken,
      'issuedAt': session.issuedAt.toUtc().toIso8601String(),
    }),
  );

  static void _requireExactKeys(Map<String, Object?> values) {
    const expected = {
      'collectorId',
      'collectorCode',
      'installationId',
      'accessToken',
      'issuedAt',
    };
    if (values.length != expected.length || !values.keys.toSet().containsAll(expected)) {
      throw const FormatException('Session has an unsupported shape.');
    }
  }

  static String _text(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Session $key is missing.');
    }
    return value;
  }
}
