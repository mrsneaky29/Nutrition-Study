import 'dart:convert';

/// Exception thrown when a QR setup payload is invalid or cannot be parsed.
sealed class QrPayloadException implements Exception {
  const QrPayloadException(this.message);

  final String message;

  @override
  String toString() => 'QrPayloadException: $message';
}

/// Thrown when the scanned QR data is empty or only whitespace.
class QrEmptyPayloadException extends QrPayloadException {
  const QrEmptyPayloadException() : super('Scanned QR code is empty.');
}

/// Thrown when the scanned QR data cannot be decoded as JSON or URI.
class QrMalformedEncodingException extends QrPayloadException {
  const QrMalformedEncodingException(String reason)
    : super('Scanned QR code is malformed: $reason');
}

/// Thrown when the payload type is missing or unrecognized.
class QrInvalidTypeException extends QrPayloadException {
  const QrInvalidTypeException(String foundType)
    : super(
        'Unrecognized QR payload type "$foundType". '
        'This is not a valid Nutrition Study setup code.',
      );
}

/// Thrown when the payload version is unsupported.
class QrUnsupportedVersionException extends QrPayloadException {
  const QrUnsupportedVersionException(Object? version)
    : super(
        'Unsupported QR payload version "$version". '
        'The application supports version 1.',
      );
}

/// Thrown when the collector number is invalid or not positive.
class QrInvalidCollectorNumberException extends QrPayloadException {
  const QrInvalidCollectorNumberException(String reason)
    : super('Invalid collector number: $reason');
}

/// Thrown when the collector access key is empty, too short, or malformed.
class QrInvalidKeyException extends QrPayloadException {
  const QrInvalidKeyException(String reason)
    : super('Invalid collector access key: $reason');
}

/// Thrown when the QR payload attempts to redirect the app to an unauthorized server.
class QrUnauthorizedServerException extends QrPayloadException {
  const QrUnauthorizedServerException({
    required this.attemptedServer,
    required this.expectedServer,
  }) : super(
         'QR code specifies server "$attemptedServer", which does not match '
         'the preconfigured server "$expectedServer". Redirection is forbidden.',
       );

  final String attemptedServer;
  final String expectedServer;
}

/// Thrown when a non-HTTPS server is specified in production mode.
class QrInsecureServerException extends QrPayloadException {
  const QrInsecureServerException(String server)
    : super(
        'Insecure HTTP server "$server" rejected. Production requires HTTPS.',
      );
}

/// Validated setup data extracted from a collector onboarding QR code.
///
/// Contains the collector's numeric ID and secret access key.
/// Never exposes [collectorKey] in [toString] or default serialization.
class CollectorQrPayload {
  CollectorQrPayload({
    required this.version,
    required this.collectorNumber,
    required String collectorKey,
    this.serverUrl,
  }) : _collectorKey = _validateKey(collectorKey) {
    if (version != currentVersion) {
      throw QrUnsupportedVersionException(version);
    }
    if (collectorNumber < 1) {
      throw const QrInvalidCollectorNumberException(
        'Collector number must be a positive integer.',
      );
    }
  }

  /// Current supported payload format version.
  static const int currentVersion = 1;

  /// Expected payload type identifier.
  static const String expectedType = 'nutrition_study_collector_setup';

  /// Alternative acceptable type identifier.
  static const String aliasType = 'collector_setup';

  /// Supported URI scheme for QR codes.
  static const String uriScheme = 'nutritionstudy';

  /// Supported URI host for QR setup.
  static const String uriHost = 'collector-setup';

  /// Minimum acceptable length for a collector access key.
  static const int minKeyLength = 16;

  /// The payload schema version.
  final int version;

  /// The positive integer identifier for the collector (e.g. 1, 5, 42).
  final int collectorNumber;

  /// The normalized collector code (e.g. 'C001', 'C005', 'C042').
  String get collectorCode => 'C${collectorNumber.toString().padLeft(3, '0')}';

  /// Opaque secret access key issued by the study administrator.
  final String _collectorKey;

  /// Sensitive collector access credential.
  ///
  /// Keep this secret: never include in UI, logs, exports, or error messages.
  String get collectorKey => _collectorKey;

  /// Optional server URL embedded in the QR code.
  final String? serverUrl;

  /// Resolves the effective server URL to connect to.
  ///
  /// Strictly requires that [preconfiguredServerUrl] is used unless null/empty.
  /// If [serverUrl] was present in the QR, it was already verified to match
  /// [preconfiguredServerUrl] during parsing.
  String resolveServerUrl(String preconfiguredServerUrl) {
    final trimmedPreconfigured = preconfiguredServerUrl.trim();
    if (trimmedPreconfigured.isNotEmpty) {
      return trimmedPreconfigured;
    }
    return serverUrl ?? '';
  }

  /// Parses a raw QR code string, validating payload type, version,
  /// collector number, access key, and server restrictions.
  ///
  /// If [expectedServerUrl] is non-empty, any server specified in the QR
  /// must match it exactly, preventing malicious server redirection.
  ///
  /// If [requireHttps] is true, plain HTTP server URLs are rejected.
  factory CollectorQrPayload.parse(
    String rawData, {
    String? expectedServerUrl,
    bool requireHttps = true,
  }) {
    if (rawData.length > 4096) {
      throw const QrMalformedEncodingException('Payload is too large.');
    }
    final trimmed = rawData.trim();
    if (trimmed.isEmpty) {
      throw const QrEmptyPayloadException();
    }

    if (trimmed.startsWith('{')) {
      return _parseJson(
        trimmed,
        expectedServerUrl: expectedServerUrl,
        requireHttps: requireHttps,
      );
    }

    if (trimmed.contains('://') || trimmed.startsWith('$uriScheme:')) {
      return _parseUri(
        trimmed,
        expectedServerUrl: expectedServerUrl,
        requireHttps: requireHttps,
      );
    }

    throw const QrMalformedEncodingException(
      'Payload is neither a valid JSON object nor a supported setup URI.',
    );
  }

  /// Safely attempts to parse [rawData], returning a result without throwing.
  static ({CollectorQrPayload? payload, String? error}) tryParse(
    String rawData, {
    String? expectedServerUrl,
    bool requireHttps = true,
  }) {
    try {
      final payload = CollectorQrPayload.parse(
        rawData,
        expectedServerUrl: expectedServerUrl,
        requireHttps: requireHttps,
      );
      return (payload: payload, error: null);
    } on QrPayloadException catch (e) {
      return (payload: null, error: e.message);
    } catch (_) {
      return (payload: null, error: 'Failed to parse QR code.');
    }
  }

  /// Generates a valid JSON payload string for tests or admin QR generation.
  ///
  /// Note: Only use this for test fixtures or secure administrative tools.
  /// Never embed generated strings with real credentials into public source files.
  static String generateJson({
    required int collectorNumber,
    required String collectorKey,
    int version = currentVersion,
    String? serverUrl,
  }) {
    final map = <String, dynamic>{
      'type': expectedType,
      'v': version,
      'collectorNumber': collectorNumber,
      'collectorKey': collectorKey,
      if (serverUrl != null && serverUrl.isNotEmpty) 'serverUrl': serverUrl,
    };
    return jsonEncode(map);
  }

  /// Generates a valid setup URI string for tests or admin QR generation.
  static String generateUri({
    required int collectorNumber,
    required String collectorKey,
    int version = currentVersion,
    String? serverUrl,
  }) {
    final query = <String, String>{
      'v': version.toString(),
      'num': collectorNumber.toString(),
      'key': collectorKey,
      if (serverUrl != null && serverUrl.isNotEmpty) 'server': serverUrl,
    };
    return Uri(
      scheme: uriScheme,
      host: uriHost,
      queryParameters: query,
    ).toString();
  }

  static CollectorQrPayload _parseJson(
    String rawJson, {
    String? expectedServerUrl,
    required bool requireHttps,
  }) {
    dynamic decoded;
    try {
      decoded = jsonDecode(rawJson);
    } catch (_) {
      throw const QrMalformedEncodingException('Invalid JSON syntax.');
    }

    if (decoded is! Map) {
      throw const QrMalformedEncodingException('JSON root must be an object.');
    }

    final map = decoded.map((k, v) => MapEntry(k.toString(), v));

    // 1. Validate payload type
    final type = map['type'] ?? map['payloadType'];
    if (type == null) {
      throw const QrInvalidTypeException('(missing)');
    }
    if (type != expectedType && type != aliasType) {
      throw QrInvalidTypeException(type.toString());
    }

    // 2. Validate version
    final rawVersion = map['v'] ?? map['version'];
    if (rawVersion == null) {
      throw const QrUnsupportedVersionException('(missing)');
    }
    final int version;
    if (rawVersion is int) {
      version = rawVersion;
    } else if (rawVersion is String) {
      version = int.tryParse(rawVersion.trim()) ?? -1;
    } else {
      version = -1;
    }
    if (version != currentVersion) {
      throw QrUnsupportedVersionException(rawVersion);
    }

    // 3. Validate collector number
    final rawNumber =
        map['collectorNumber'] ??
        map['collector_number'] ??
        map['collectorCode'] ??
        map['collector_code'] ??
        map['collectorId'] ??
        map['collector_id'] ??
        map['num'];
    final collectorNumber = _extractPositiveCollectorNumber(rawNumber);

    // 4. Validate collector access key
    final rawKey =
        map['collectorKey'] ??
        map['collector_key'] ??
        map['accessKey'] ??
        map['access_key'] ??
        map['key'];
    final collectorKey = _validateKey(rawKey?.toString());

    // 5. Validate server URL against preconfigured server / HTTPS constraints
    final rawServer = map['serverUrl'] ?? map['server_url'] ?? map['server'];
    final serverUrl = _validateServerUrl(
      rawServer?.toString(),
      expectedServerUrl: expectedServerUrl,
      requireHttps: requireHttps,
    );

    return CollectorQrPayload(
      version: version,
      collectorNumber: collectorNumber,
      collectorKey: collectorKey,
      serverUrl: serverUrl,
    );
  }

  static CollectorQrPayload _parseUri(
    String rawUri, {
    String? expectedServerUrl,
    required bool requireHttps,
  }) {
    Uri uri;
    try {
      uri = Uri.parse(rawUri);
    } catch (_) {
      throw const QrMalformedEncodingException('Invalid URI syntax.');
    }

    if (uri.scheme != uriScheme && uri.scheme != 'https') {
      throw QrInvalidTypeException('uri-scheme:${uri.scheme}');
    }

    if (uri.scheme == uriScheme && uri.host.isNotEmpty && uri.host != uriHost) {
      throw QrInvalidTypeException('uri-host:${uri.host}');
    }

    final query = uri.queryParameters;

    // Version
    final rawVersion = query['v'] ?? query['version'];
    if (rawVersion == null) {
      throw const QrUnsupportedVersionException('(missing)');
    }
    final version = int.tryParse(rawVersion.trim()) ?? -1;
    if (version != currentVersion) {
      throw QrUnsupportedVersionException(rawVersion);
    }

    // Collector Number
    final rawNumber = query['num'] ?? query['collectorNumber'] ?? query['id'];
    final collectorNumber = _extractPositiveCollectorNumber(rawNumber);

    // Key
    final rawKey = query['key'] ?? query['accessKey'];
    final collectorKey = _validateKey(rawKey);

    // Server
    final rawServer = query['server'] ?? query['serverUrl'];
    final serverUrl = _validateServerUrl(
      rawServer,
      expectedServerUrl: expectedServerUrl,
      requireHttps: requireHttps,
    );

    return CollectorQrPayload(
      version: version,
      collectorNumber: collectorNumber,
      collectorKey: collectorKey,
      serverUrl: serverUrl,
    );
  }

  static int _extractPositiveCollectorNumber(dynamic raw) {
    if (raw == null) {
      throw const QrInvalidCollectorNumberException('Number is missing.');
    }
    if (raw is int) {
      if (raw >= 1) return raw;
      throw QrInvalidCollectorNumberException('Must be >= 1, got $raw.');
    }
    if (raw is String) {
      final trimmed = raw.trim().toUpperCase();
      final match = RegExp(r'^C?0*([1-9]\d*)$').firstMatch(trimmed);
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!);
        if (parsed != null && parsed >= 1) {
          return parsed;
        }
      }
    }
    throw QrInvalidCollectorNumberException(
      'Expected a positive integer (e.g. 1, 5, or C005), got "$raw".',
    );
  }

  static String _validateKey(String? key) {
    if (key == null || key.trim().isEmpty) {
      throw const QrInvalidKeyException('Access key is missing or empty.');
    }
    final trimmed = key.trim();
    if (trimmed.length < minKeyLength) {
      throw QrInvalidKeyException(
        'Access key is too short (${trimmed.length} chars, minimum $minKeyLength).',
      );
    }
    if (RegExp(r'\s').hasMatch(trimmed)) {
      throw const QrInvalidKeyException(
        'Access key must not contain whitespace.',
      );
    }
    if (!RegExp(r'^[\x21-\x7E]{16,256}$').hasMatch(trimmed)) {
      throw const QrInvalidKeyException(
        'Access key must be a bounded printable token.',
      );
    }
    return trimmed;
  }

  static String? _validateServerUrl(
    String? server, {
    String? expectedServerUrl,
    required bool requireHttps,
  }) {
    if (server == null || server.trim().isEmpty) {
      return null;
    }
    final trimmed = server.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw QrMalformedEncodingException('Invalid server URL "$server".');
    }

    if (requireHttps && uri.scheme != 'https') {
      throw QrInsecureServerException(trimmed);
    }

    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw QrMalformedEncodingException(
        'Server URL must not contain query parameters, user info, or fragments.',
      );
    }

    // Redirection check: If expectedServerUrl is configured, verify exact match
    if (expectedServerUrl != null && expectedServerUrl.trim().isNotEmpty) {
      final normalizedExpected = expectedServerUrl.trim().replaceFirst(
        RegExp(r'/+$'),
        '',
      );
      final expectedUri = Uri.tryParse(normalizedExpected);
      if (expectedUri != null) {
        final sameHost =
            uri.host.toLowerCase() == expectedUri.host.toLowerCase();
        final samePort = uri.port == expectedUri.port;
        final sameScheme =
            uri.scheme.toLowerCase() == expectedUri.scheme.toLowerCase();
        final samePath = uri.path == expectedUri.path;
        if (!sameHost || !samePort || !sameScheme || !samePath) {
          throw QrUnauthorizedServerException(
            attemptedServer: trimmed,
            expectedServer: normalizedExpected,
          );
        }
      }
    }

    return trimmed;
  }

  /// Never prints [collectorKey] in string representations.
  @override
  String toString() =>
      'CollectorQrPayload('
      'code: $collectorCode, '
      'version: $version, '
      'server: ${serverUrl ?? "(preconfigured)"})';
}
