/// The build-time runtime choice. Local demo is deliberately a separate mode
/// from a production Firebase deployment; the two adapters must not be mixed.
enum StudyRuntimeMode { localDemo, firebaseProduction }

/// Firebase values supplied through `--dart-define` in a production build.
///
/// This class is dependency-free so app startup can validate its deployment
/// contract before importing or initializing a Firebase SDK.
class FirebaseRuntimeConfiguration {
  const FirebaseRuntimeConfiguration({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    required this.authDomain,
    required this.functionsRegion,
    required this.studyId,
  });

  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  final String authDomain;
  final String functionsRegion;
  final String studyId;
}

/// Selects a local-only demo or a Firebase production deployment.
///
/// Supported `--dart-define` keys for a production build are:
/// `STUDY_RUNTIME_MODE=firebase-production`, `FIREBASE_API_KEY`,
/// `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`,
/// `FIREBASE_PROJECT_ID`, `FIREBASE_AUTH_DOMAIN`, and
/// `FIREBASE_FUNCTIONS_REGION`, plus `STUDY_ID`. Omitting any production value throws during
/// startup instead of silently sending data to a demo or LAN adapter.
class StudyRuntimeConfiguration {
  const StudyRuntimeConfiguration._({required this.mode, this.firebase});

  factory StudyRuntimeConfiguration.localDemo() =>
      const StudyRuntimeConfiguration._(mode: StudyRuntimeMode.localDemo);

  factory StudyRuntimeConfiguration.firebaseProduction(
    FirebaseRuntimeConfiguration firebase,
  ) => StudyRuntimeConfiguration._(
    mode: StudyRuntimeMode.firebaseProduction,
    firebase: firebase,
  );

  final StudyRuntimeMode mode;
  final FirebaseRuntimeConfiguration? firebase;

  bool get isLocalDemo => mode == StudyRuntimeMode.localDemo;
  bool get isFirebaseProduction => mode == StudyRuntimeMode.firebaseProduction;

  /// Provides the validated production values, rejecting demo-mode use.
  FirebaseRuntimeConfiguration requireFirebase() {
    final configured = firebase;
    if (!isFirebaseProduction || configured == null) {
      throw StateError(
        'Firebase configuration is unavailable in local-demo mode. '
        'Build with STUDY_RUNTIME_MODE=firebase-production.',
      );
    }
    return configured;
  }

  /// Reads compile-time values supplied by Flutter `--dart-define` flags.
  factory StudyRuntimeConfiguration.fromEnvironment() =>
      StudyRuntimeConfiguration.fromValues(
        runtimeMode: _runtimeMode,
        apiKey: _apiKey,
        appId: _appId,
        messagingSenderId: _messagingSenderId,
        projectId: _projectId,
        authDomain: _authDomain,
        functionsRegion: _functionsRegion,
        studyId: _studyId,
      );

  /// Creates configuration from values so startup behaviour is fully testable.
  factory StudyRuntimeConfiguration.fromValues({
    required String runtimeMode,
    String? apiKey,
    String? appId,
    String? messagingSenderId,
    String? projectId,
    String? authDomain,
    String? functionsRegion,
    String? studyId,
  }) {
    switch (runtimeMode.trim().toLowerCase()) {
      case 'local-demo':
        return StudyRuntimeConfiguration.localDemo();
      case 'firebase-production':
        return StudyRuntimeConfiguration.firebaseProduction(
          FirebaseRuntimeConfiguration(
            apiKey: _required(apiKey, 'FIREBASE_API_KEY'),
            appId: _required(appId, 'FIREBASE_APP_ID'),
            messagingSenderId: _required(
              messagingSenderId,
              'FIREBASE_MESSAGING_SENDER_ID',
            ),
            projectId: _required(projectId, 'FIREBASE_PROJECT_ID'),
            authDomain: _required(authDomain, 'FIREBASE_AUTH_DOMAIN'),
            functionsRegion: _required(
              functionsRegion,
              'FIREBASE_FUNCTIONS_REGION',
            ),
            studyId: _required(studyId, 'STUDY_ID'),
          ),
        );
      default:
        throw StateError(
          'STUDY_RUNTIME_MODE must be local-demo or firebase-production.',
        );
    }
  }

  static String _required(String? value, String defineName) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      throw StateError(
        'Production build is missing required --dart-define=$defineName.',
      );
    }
    return normalized;
  }

  static const _runtimeMode = String.fromEnvironment(
    'STUDY_RUNTIME_MODE',
    defaultValue: 'local-demo',
  );
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const _functionsRegion = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_REGION',
  );
  static const _studyId = String.fromEnvironment('STUDY_ID');
}
