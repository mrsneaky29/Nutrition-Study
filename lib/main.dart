import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'dart:async';

import 'l10n/app_localizations.dart';
import 'l10n/collector_language.dart';

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
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
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

class MyApp extends StatefulWidget {
  const MyApp({
    this.syncGateway,
    this.recordStore,
    this.cloudController,
    this.languageController,
    super.key,
  });

  final LocalRecordSyncGateway? syncGateway;
  final LocalRecordStore? recordStore;
  final CollectorCloudController? cloudController;
  final CollectorLanguageController? languageController;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final CollectorLanguageController _language =
      widget.languageController ?? CollectorLanguageController();

  @override
  void initState() {
    super.initState();
    unawaited(_language.load());
  }

  @override
  void dispose() {
    if (widget.languageController == null) _language.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CollectorLanguageScope(
      controller: _language,
      child: AnimatedBuilder(
        animation: _language,
        builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Vivayu',
          locale: _language.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: PresentationTheme.materialTheme(),
          builder: (context, child) => Column(
            children: [
              const CollectorLanguageBar(),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: child!,
                ),
              ),
            ],
          ),
          home: LocalDemoApp(
            syncGateway: widget.syncGateway,
            recordStore: widget.recordStore,
            cloudController: widget.cloudController,
          ),
        ),
      ),
    );
  }
}
