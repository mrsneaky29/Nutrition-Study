import 'package:flutter_test/flutter_test.dart';
import 'package:project2/collector_auth/collector_access.dart';

void main() {
  test('collector codes normalize and reject malformed values', () {
    expect(CollectorCode(' c001 ').value, 'C001');
    expect(() => CollectorCode('collector-1'), throwsArgumentError);
  });

  test(
    'in-memory session store retains and clears its opaque session',
    () async {
      final store = InMemoryInstallationSessionStore();
      final session = CollectorInstallationSession(
        collectorId: 'collector-1',
        collectorCode: CollectorCode('C001'),
        installationId: 'install-1',
        accessToken: 'secret',
        issuedAt: DateTime.utc(2026),
      );

      await store.write(session);
      expect((await store.read())?.accessToken, 'secret');
      await store.clear();
      expect(await store.read(), isNull);
    },
  );
}
