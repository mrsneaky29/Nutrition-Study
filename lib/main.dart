import 'package:flutter/material.dart';

import 'collector/collector_cloud_controller.dart';
import 'collector_auth/secure_installation_session_store.dart';
import 'config/study_runtime_configuration.dart';
import 'firebase/firebase_bootstrap.dart';
import 'firebase/firebase_collector_access_gateway.dart';
import 'firebase/firebase_study_cloud_gateway.dart';
import 'local_demo_app.dart';
import 'local_sync/local_record_sync_gateway.dart';
import 'local_storage/local_record_store.dart';
import 'presentation/presentation_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configuration = StudyRuntimeConfiguration.fromEnvironment();
  if (configuration.isLocalDemo) {
    runApp(const MyApp());
    return;
  }

  final firebase = configuration.requireFirebase();
  final services = await StudyFirebaseServices.initialize(firebase);
  final access = FirebaseCollectorAccessGateway(
    auth: services.auth,
    functions: services.functions,
  );
  final gateway = FirebaseStudyCloudGateway(
    studyId: firebase.studyId,
    access: access,
    functions: services.functions,
    firestore: services.firestore,
  );
  runApp(
    MyApp(
      cloudController: CollectorCloudController(
        gateway: gateway,
        sessionStore: SecureInstallationSessionStore(),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({
    this.syncGateway,
    this.recordStore,
    this.cloudController,
    super.key,
  });

  final LocalRecordSyncGateway? syncGateway;
  final LocalRecordStore? recordStore;
  final CollectorCloudController? cloudController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Study Collector',
      theme: PresentationTheme.materialTheme(),
      home: LocalDemoApp(
        syncGateway: syncGateway,
        recordStore: recordStore,
        cloudController: cloudController,
      ),
    );
  }
}
