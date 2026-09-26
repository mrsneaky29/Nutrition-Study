import 'package:flutter_test/flutter_test.dart';
import 'package:project2/collector_auth/collector_qr_payload.dart';

void main() {
  test('oversized payload is rejected before parsing', () {
    expect(
      () => CollectorQrPayload.parse('x' * 4097),
      throwsA(isA<QrMalformedEncodingException>()),
    );
  });
  test('malformed JSON does not echo a credential substring', () {
    const secret = 'SYNTHETIC-SECRET-MARKER';
    final result = CollectorQrPayload.tryParse('{"collectorKey":"$secret');
    expect(result.payload, isNull);
    expect(result.error, isNot(contains(secret)));
  });
  test('key rejects control characters unicode and excessive length', () {
    for (final key in [
      'abcdefghijklmnop\u0000',
      'abcdefghijklmnopé',
      'x' * 257,
    ]) {
      expect(
        () => CollectorQrPayload(
          version: 1,
          collectorNumber: 1,
          collectorKey: key,
        ),
        throwsA(isA<QrInvalidKeyException>()),
      );
    }
  });
}
