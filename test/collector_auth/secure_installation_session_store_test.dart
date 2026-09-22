import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:project2/collector_auth/collector_access.dart';
import 'package:project2/collector_auth/secure_installation_session_store.dart';

void main() {
  test('writes and restores every session property', () async {
    final storage = _MemoryStorage();
    final store = SecureInstallationSessionStore(storage: storage);
    final session = CollectorInstallationSession(
      collectorId: 'collector-C001',
      collectorCode: CollectorCode('c001'),
      installationId: 'installation-123',
      accessToken: 'opaque-secret',
      issuedAt: DateTime.utc(2026, 9, 14, 8, 30),
    );

    await store.write(session);
    final restored = await store.read();

    expect(restored?.collectorId, session.collectorId);
    expect(restored?.collectorCode.value, 'C001');
    expect(restored?.installationId, session.installationId);
    expect(restored?.accessToken, session.accessToken);
    expect(restored?.issuedAt, session.issuedAt);
    expect(jsonDecode(storage.values[SecureInstallationSessionStore.storageKey]!),
        isA<Map<String, dynamic>>());
  });

  test('clearing removes the encrypted session value', () async {
    final storage = _MemoryStorage();
    final store = SecureInstallationSessionStore(storage: storage);

    await store.write(_session());
    await store.clear();

    expect(await store.read(), isNull);
    expect(storage.values, isEmpty);
  });

  test('malformed storage is rejected instead of becoming a session', () async {
    final storage = _MemoryStorage()
      ..values[SecureInstallationSessionStore.storageKey] = jsonEncode({
        'collectorId': 'collector-C001',
        'collectorCode': 'not-a-code',
        'installationId': 'installation-123',
        'accessToken': 'opaque-secret',
        'issuedAt': '2026-09-14T08:30:00.000Z',
      });
    final store = SecureInstallationSessionStore(storage: storage);

    await expectLater(store.read(), throwsFormatException);
  });

  test('unknown serialized fields are rejected', () async {
    final storage = _MemoryStorage()
      ..values[SecureInstallationSessionStore.storageKey] = jsonEncode({
        'collectorId': 'collector-C001',
        'collectorCode': 'C001',
        'installationId': 'installation-123',
        'accessToken': 'opaque-secret',
        'issuedAt': '2026-09-14T08:30:00.000Z',
        'admin': true,
      });

    await expectLater(
      SecureInstallationSessionStore(storage: storage).read(),
      throwsFormatException,
    );
  });
}

CollectorInstallationSession _session() => CollectorInstallationSession(
  collectorId: 'collector-C001',
  collectorCode: CollectorCode('C001'),
  installationId: 'installation-123',
  accessToken: 'opaque-secret',
  issuedAt: DateTime.utc(2026, 9, 14, 8, 30),
);

class _MemoryStorage implements SecureInstallationSessionStorage {
  final Map<String, String> values = {};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}
