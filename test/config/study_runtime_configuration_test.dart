import 'package:flutter_test/flutter_test.dart';
import 'package:project2/config/study_runtime_configuration.dart';

void main() {
  test('local demo is an explicit mode without Firebase values', () {
    final configuration = StudyRuntimeConfiguration.fromValues(
      runtimeMode: 'local-demo',
    );

    expect(configuration.isLocalDemo, isTrue);
    expect(configuration.isFirebaseProduction, isFalse);
    expect(configuration.requireFirebase, throwsStateError);
  });

  test('production requires every Firebase deployment value', () {
    expect(
      () => StudyRuntimeConfiguration.fromValues(
        runtimeMode: 'firebase-production',
        apiKey: 'api-key',
        appId: 'app-id',
        messagingSenderId: 'sender-id',
        projectId: 'project-id',
        authDomain: 'project.firebaseapp.com',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('FIREBASE_FUNCTIONS_REGION'),
        ),
      ),
    );
  });

  test('production exposes only complete validated Firebase values', () {
    final configuration = StudyRuntimeConfiguration.fromValues(
      runtimeMode: 'firebase-production',
      apiKey: 'api-key',
      appId: 'app-id',
      messagingSenderId: 'sender-id',
      projectId: 'project-id',
      authDomain: 'project.firebaseapp.com',
      functionsRegion: 'asia-south1',
      studyId: 'nutrition-study-2026',
    );

    expect(configuration.isFirebaseProduction, isTrue);
    expect(configuration.requireFirebase().projectId, 'project-id');
    expect(configuration.requireFirebase().functionsRegion, 'asia-south1');
    expect(configuration.requireFirebase().studyId, 'nutrition-study-2026');
  });

  test('unknown modes fail closed', () {
    expect(
      () => StudyRuntimeConfiguration.fromValues(runtimeMode: 'firebase'),
      throwsStateError,
    );
  });
}
