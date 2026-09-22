import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../config/study_runtime_configuration.dart';

/// Firebase services initialized entirely from validated build-time values.
///
/// This avoids committing platform configuration files containing deployment
/// identifiers and keeps local-demo and hosted-production builds explicit.
class StudyFirebaseServices {
  const StudyFirebaseServices({
    required this.auth,
    required this.firestore,
    required this.functions,
  });

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;

  static Future<StudyFirebaseServices> initialize(
    FirebaseRuntimeConfiguration configuration,
  ) async {
    final app = await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: configuration.apiKey,
        appId: configuration.appId,
        messagingSenderId: configuration.messagingSenderId,
        projectId: configuration.projectId,
        authDomain: configuration.authDomain,
      ),
    );
    return StudyFirebaseServices(
      auth: FirebaseAuth.instanceFor(app: app),
      firestore: FirebaseFirestore.instanceFor(app: app),
      functions: FirebaseFunctions.instanceFor(
        app: app,
        region: configuration.functionsRegion,
      ),
    );
  }
}
