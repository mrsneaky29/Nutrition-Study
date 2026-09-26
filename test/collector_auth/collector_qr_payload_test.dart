import 'package:flutter_test/flutter_test.dart';
import 'package:project2/collector_auth/collector_qr_payload.dart';

void main() {
  group('CollectorQrPayload Parser & Security Tests', () {
    const validKey = 'collector_key_valid_secret_12345';
    const preconfiguredServer = 'https://api.nutrition.achantalabs.com';

    test('parses valid standard JSON payload successfully', () {
      final json = CollectorQrPayload.generateJson(
        collectorNumber: 5,
        collectorKey: validKey,
      );

      final payload = CollectorQrPayload.parse(
        json,
        expectedServerUrl: preconfiguredServer,
      );

      expect(payload.version, equals(1));
      expect(payload.collectorNumber, equals(5));
      expect(payload.collectorCode, equals('C005'));
      expect(payload.collectorKey, equals(validKey));
      expect(payload.resolveServerUrl(preconfiguredServer), equals(preconfiguredServer));
    });

    test('parses payload with string collector numbers and variations', () {
      // numeric string "1"
      final payload1 = CollectorQrPayload.parse(
        '{"type":"nutrition_study_collector_setup","v":1,"collectorNumber":"1","key":"$validKey"}',
      );
      expect(payload1.collectorNumber, equals(1));
      expect(payload1.collectorCode, equals('C001'));

      // prefixed string "C042"
      final payload2 = CollectorQrPayload.parse(
        '{"type":"collector_setup","v":1,"collectorCode":"C042","collector_key":"$validKey"}',
      );
      expect(payload2.collectorNumber, equals(42));
      expect(payload2.collectorCode, equals('C042'));

      // large number "105"
      final payload3 = CollectorQrPayload.parse(
        '{"type":"nutrition_study_collector_setup","v":1,"collectorId":"105","accessKey":"$validKey"}',
      );
      expect(payload3.collectorNumber, equals(105));
      expect(payload3.collectorCode, equals('C105'));
    });

    test('rejects empty or whitespace-only payloads', () {
      expect(
        () => CollectorQrPayload.parse(''),
        throwsA(isA<QrEmptyPayloadException>()),
      );
      expect(
        () => CollectorQrPayload.parse('   \n  \t '),
        throwsA(isA<QrEmptyPayloadException>()),
      );
    });

    test('rejects malformed JSON encoding', () {
      expect(
        () => CollectorQrPayload.parse('{not_json}'),
        throwsA(isA<QrMalformedEncodingException>()),
      );
      expect(
        () => CollectorQrPayload.parse('["not_an_object"]'),
        throwsA(isA<QrMalformedEncodingException>()),
      );
      expect(
        () => CollectorQrPayload.parse('just a random string'),
        throwsA(isA<QrMalformedEncodingException>()),
      );
    });

    test('rejects unrecognized payload types', () {
      expect(
        () => CollectorQrPayload.parse(
          '{"type":"attacker_malicious_setup","v":1,"collectorNumber":1,"key":"$validKey"}',
        ),
        throwsA(isA<QrInvalidTypeException>()),
      );

      expect(
        () => CollectorQrPayload.parse(
          '{"v":1,"collectorNumber":1,"key":"$validKey"}',
        ),
        throwsA(isA<QrInvalidTypeException>()),
      );
    });

    test('rejects unsupported versions', () {
      expect(
        () => CollectorQrPayload.parse(
          '{"type":"nutrition_study_collector_setup","v":2,"collectorNumber":1,"key":"$validKey"}',
        ),
        throwsA(isA<QrUnsupportedVersionException>()),
      );

      expect(
        () => CollectorQrPayload.parse(
          '{"type":"nutrition_study_collector_setup","v":0,"collectorNumber":1,"key":"$validKey"}',
        ),
        throwsA(isA<QrUnsupportedVersionException>()),
      );

      expect(
        () => CollectorQrPayload.parse(
          '{"type":"nutrition_study_collector_setup","collectorNumber":1,"key":"$validKey"}',
        ),
        throwsA(isA<QrUnsupportedVersionException>()),
      );
    });

    test('rejects invalid or non-positive collector numbers', () {
      // 0 is not positive
      expect(
        () => CollectorQrPayload.parse(
          '{"type":"nutrition_study_collector_setup","v":1,"collectorNumber":0,"key":"$validKey"}',
        ),
        throwsA(isA<QrInvalidCollectorNumberException>()),
      );

      // negative number
      expect(
        () => CollectorQrPayload.parse(
          '{"type":"nutrition_study_collector_setup","v":1,"collectorNumber":-5,"key":"$validKey"}',
        ),
        throwsA(isA<QrInvalidCollectorNumberException>()),
      );

      // non-numeric string
      expect(
        () => CollectorQrPayload.parse(
          '{"type":"nutrition_study_collector_setup","v":1,"collectorNumber":"admin","key":"$validKey"}',
        ),
        throwsA(isA<QrInvalidCollectorNumberException>()),
      );
    });

    test('rejects invalid, short, or whitespace access keys', () {
      // too short (< 16 chars)
      expect(
        () => CollectorQrPayload.parse(
          '{"type":"nutrition_study_collector_setup","v":1,"collectorNumber":1,"key":"short_key"}',
        ),
        throwsA(isA<QrInvalidKeyException>()),
      );

      // contains whitespace
      expect(
        () => CollectorQrPayload.parse(
          '{"type":"nutrition_study_collector_setup","v":1,"collectorNumber":1,"key":"key with whitespace in between"}',
        ),
        throwsA(isA<QrInvalidKeyException>()),
      );

      // missing key
      expect(
        () => CollectorQrPayload.parse(
          '{"type":"nutrition_study_collector_setup","v":1,"collectorNumber":1}',
        ),
        throwsA(isA<QrInvalidKeyException>()),
      );
    });

    group('Server Redirection & HTTPS Protection', () {
      test('permits payload when server matches preconfigured HTTPS server', () {
        final json = CollectorQrPayload.generateJson(
          collectorNumber: 1,
          collectorKey: validKey,
          serverUrl: preconfiguredServer,
        );

        final payload = CollectorQrPayload.parse(
          json,
          expectedServerUrl: preconfiguredServer,
        );

        expect(payload.serverUrl, equals(preconfiguredServer));
        expect(payload.resolveServerUrl(preconfiguredServer), equals(preconfiguredServer));
      });

      test('forbids QR payload from redirecting to another server', () {
        const rogueServer = 'https://rogue-hacker-api.com';
        final json = CollectorQrPayload.generateJson(
          collectorNumber: 1,
          collectorKey: validKey,
          serverUrl: rogueServer,
        );

        expect(
          () => CollectorQrPayload.parse(
            json,
            expectedServerUrl: preconfiguredServer,
          ),
          throwsA(
            isA<QrUnauthorizedServerException>().having(
              (e) => e.attemptedServer,
              'attemptedServer',
              equals(rogueServer),
            ),
          ),
        );
      });

      test('rejects insecure HTTP server when HTTPS is required', () {
        const insecureHttpServer = 'http://api.nutrition.achantalabs.com';
        final json = CollectorQrPayload.generateJson(
          collectorNumber: 1,
          collectorKey: validKey,
          serverUrl: insecureHttpServer,
        );

        expect(
          () => CollectorQrPayload.parse(
            json,
            expectedServerUrl: preconfiguredServer,
            requireHttps: true,
          ),
          throwsA(isA<QrInsecureServerException>()),
        );
      });

      test('rejects server URLs with queries or fragments', () {
        const dirtyServer = 'https://api.nutrition.achantalabs.com/path?query=1';
        final json = CollectorQrPayload.generateJson(
          collectorNumber: 1,
          collectorKey: validKey,
          serverUrl: dirtyServer,
        );

        expect(
          () => CollectorQrPayload.parse(json),
          throwsA(isA<QrMalformedEncodingException>()),
        );
      });
    });

    group('URI Scheme Support', () {
      test('parses valid nutritionstudy:// URI', () {
        final uriString = CollectorQrPayload.generateUri(
          collectorNumber: 7,
          collectorKey: validKey,
        );

        final payload = CollectorQrPayload.parse(
          uriString,
          expectedServerUrl: preconfiguredServer,
        );

        expect(payload.collectorNumber, equals(7));
        expect(payload.collectorCode, equals('C007'));
        expect(payload.collectorKey, equals(validKey));
      });

      test('rejects unknown URI schemes', () {
        expect(
          () => CollectorQrPayload.parse(
            'http://attacker.com/qr?v=1&num=1&key=$validKey',
          ),
          throwsA(isA<QrInvalidTypeException>()),
        );
      });
    });

    group('Security & Credential Redaction', () {
      test('toString() never prints secret collectorKey', () {
        final payload = CollectorQrPayload(
          version: 1,
          collectorNumber: 3,
          collectorKey: validKey,
          serverUrl: preconfiguredServer,
        );

        final stringRepresentation = payload.toString();
        expect(stringRepresentation, isNot(contains(validKey)));
        expect(stringRepresentation, contains('C003'));
        expect(stringRepresentation, contains(preconfiguredServer));
      });

      test('tryParse returns clean error message on invalid input without throwing', () {
        final result = CollectorQrPayload.tryParse('invalid_gibberish');
        expect(result.payload, isNull);
        expect(result.error, isNotNull);
        expect(result.error, contains('malformed'));
      });
    });
  });
}
