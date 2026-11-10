import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../tool/local_sync_server.dart' as api;
import '../../tool/ihds_research_risk.dart';
import '../../tool/public_research_inputs.dart';

Map<String, dynamic> model() => {
  'age': 45,
  'sex': 'female',
  'education': 'secondary',
  'tobaccoUse': 'never',
  'walkingOneKm': 'no_difficulty',
  'drinksAlcohol': 'no',
  'workedPastYear': 'yes',
  'hypertensionDiagnosis': 'no',
  'diabetesDiagnosis': 'no',
  'heartDiseaseDiagnosis': 'no',
};
Map<String, dynamic> questionnaire() => {
  ...model(),
  'studySite': 'other_site',
  'employment': 'employed',
  for (final key in [
    'fruitFrequency',
    'vegetableFrequency',
    'sugaryDrinkFrequency',
    'processedFoodFrequency',
  ])
    key: 'daily',
  'activeDaysPerWeek': 3,
  'activeMinutesPerDay': 30,
  'sleepHours': 7,
  'heightCm': 160,
  'weightKg': 64,
  'waistCm': 80,
  'hipCm': 100,
  'bpOneSystolic': 120,
  'bpOneDiastolic': 80,
  'bpTwoSystolic': 124,
  'bpTwoDiastolic': 82,
};
Map<String, dynamic> submission() => {
  'consent': {'agreed': true, 'version': publicSurveyConsentVersion},
  'participant': {'name': 'Synthetic Web Test', 'indianPhone': '+919000000009'},
  'confirmation': {
    'name': 'Synthetic Web Test',
    'indianPhone': '+919000000009',
  },
  'questionnaire': questionnaire(),
  'installationKey': 'a' * 64,
  'submissionId': 'b' * 32,
};
void main() {
  late Directory directory;
  late api.LocalRecordStore store;
  late HttpServer listener;
  late http.Client client;
  late String base;
  const keys = api.AccessKeys(
    collectorKeys: {'synthetic-staff-key-1234567890123456'},
    admin: 'synthetic-admin-key-1234567890123456',
    publicMode: true,
    allowedOrigins: {'https://admin.nutrition.achantalabs.com'},
  );
  setUp(() async {
    api.resetAuthLimiterForTesting();
    directory = await Directory.systemTemp.createTemp('vivayu-web-test-');
    store = api.LocalRecordStore(directory);
    await store.load();
    listener = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    listener.listen((r) => api.handleRequest(r, store, keys));
    client = http.Client();
    base = 'http://127.0.0.1:${listener.port}';
  });
  tearDown(() async {
    client.close();
    await listener.close(force: true);
    await directory.delete(recursive: true);
  });
  Future<http.Response> post(
    String path,
    Object body, {
    String? origin = 'https://achantalabs.com',
    bool tls = true,
    String type = 'application/json',
  }) => client.post(
    Uri.parse('$base$path'),
    headers: {
      'content-type': type,
      if (tls) 'x-forwarded-proto': 'https',
      ...(origin == null ? <String, String>{} : {'origin': origin}),
    },
    body: jsonEncode(body),
  );
  Future<Map<String, String>> snapshot() async => {
    for (final f
        in await directory
            .list(recursive: true)
            .where((e) => e is File)
            .cast<File>()
            .toList())
      f.path: await f.readAsString(),
  };
  test('estimate matches shared scorer and never writes accounts, sessions or records', () async {
    final before = await snapshot();
    final response = await post('/public/research-estimate', {
      'answers': model(),
    });
    expect(response.statusCode, 200, reason: response.body);
    expect(response.headers['cache-control'], 'no-store');
    final result = jsonDecode(response.body) as Map;
    expect(result['saved'], false);
    result.remove('saved');
    expect(result, scoreIhdsResearchRisk(normalizePublicModelAnswers(model())));
    expect(await snapshot(), before);
    expect(store.length, 0);
    expect(store.listCollectorAccounts(), isEmpty);
  });
  test('prior diagnosis, unknown history and unsupported sex never become misleading zeroes', () async {
    for (final answers in [
      {...model(), 'diabetesDiagnosis': 'yes'},
      {...model(), 'diabetesDiagnosis': 'dont_know'},
      {...model(), 'sex': 'other'},
      {...model(), 'age': 110},
    ]) {
      final response = await post('/public/research-estimate', {
        'answers': answers,
      });
      expect(response.statusCode, 200);
      final item = jsonDecode(response.body)['outcomes']['diabetes'] as Map;
      expect(item.containsKey('probability'), false);
      expect(item['status'], isNot('estimated'));
    }
  });
  test('public CORS stays scoped; TLS, type, body size and identifier exclusions enforced', () async {
    expect(
      (await post('/public/research-estimate', {
        'answers': model(),
      }, tls: false)).statusCode,
      403,
    );
    expect(
      (await post('/public/research-estimate', {
        'answers': model(),
      }, origin: 'https://untrusted.example')).statusCode,
      403,
    );
    expect(
      (await post(
        '/records',
        {},
        origin: 'https://achantalabs.com',
      )).statusCode,
      403,
    );
    expect(
      (await post('/public/research-estimate', {
        'answers': model(),
      }, type: 'text/plain')).statusCode,
      415,
    );
    expect(
      (await post('/public/research-estimate', {
        'answers': {...model(), 'name': 'secret'},
      })).statusCode,
      400,
    );
    expect(
      (await post('/public/research-estimate', {
        'answers': 'x' * 5000,
      })).statusCode,
      413,
    );
    expect(store.length, 0);
    expect(store.listCollectorAccounts(), isEmpty);
  });
  test('missing consent, invalid identity, measurements or codes produce no writes', () async {
    final before = await snapshot();
    for (final body in [
      {
        ...submission(),
        'consent': {'agreed': false, 'version': publicSurveyConsentVersion},
      },
      {
        ...submission(),
        'participant': {'name': 'Synthetic', 'indianPhone': 'bad'},
      },
      {
        ...submission(),
        'questionnaire': {...questionnaire(), 'heightCm': null},
      },
      {
        ...submission(),
        'questionnaire': {...questionnaire(), 'employment': 'invented'},
      },
      {
        ...submission(),
        'questionnaire': {...questionnaire(), 'bpOneSystolic': 70},
      },
    ]) {
      final response = await post('/public/survey', body);
      expect(response.statusCode, 400, reason: response.body);
    }
    expect(await snapshot(), before);
    expect(store.listCollectorAccounts(), isEmpty);
  });
  test('complete consented survey persists as Volunteer; calculations, receipt and retry are safe', () async {
    final body = submission();
    final first = await post('/public/survey', body);
    expect(first.statusCode, 200, reason: first.body);
    expect(jsonDecode(first.body)['saved'], true);
    expect(first.body, isNot(contains('installationKey')));
    expect(first.body, isNot(contains('Synthetic Web Test')));
    final second = await post('/public/survey', body);
    expect(second.body, first.body);
    expect(store.length, 1);
    final record = store.records(includeResearchRisk: true).single;
    expect(record['collectorDisplayName'], 'Volunteer');
    expect(record['questionnaire']['bmi'], closeTo(25, 0.00001));
    expect(record['questionnaire']['waistHipRatio'], 0.8);
    expect(record['questionnaire']['averageSystolic'], 122);
    expect(record['questionnaire']['weeklyActiveMinutes'], 90);
    expect(
      record['stepTwoPlaceholderNote'],
      contains(publicSurveyConsentVersion),
    );
    final changed = {
      ...body,
      'questionnaire': {...questionnaire(), 'age': 46},
    };
    expect((await post('/public/survey', changed)).statusCode, 409);
    expect(
      (await post('/public/survey', {
        ...body,
        'installationKey': 'c' * 64,
      })).statusCode,
      409,
    );
    final restarted = api.LocalRecordStore(directory);
    await restarted.load();
    expect(restarted.length, 1);
    expect(
      restarted
          .records(includeResearchRisk: true)
          .single['collectorDisplayName'],
      'Volunteer',
    );
  });
  test(
    'missing reasons are explicit and retained; calculated values remain null',
    () async {
      final q = questionnaire();
      q['weightKg'] = null;
      q['weightMissingReason'] = 'declined';
      q['bpTwoSystolic'] = null;
      q['bpTwoDiastolic'] = null;
      q['bpTwoMissingReason'] = 'unable';
      final response = await post('/public/survey', {
        ...submission(),
        'questionnaire': q,
      });
      expect(response.statusCode, 200, reason: response.body);
      final saved = store.records().single['questionnaire'];
      expect(saved['bmi'], null);
      expect(saved['weightMissingReason'], 'declined');
      expect(saved['averageSystolic'], null);
    },
  );
  test('save request rate limit prevents further registration', () async {
    for (var i = 0; i < 10; i++) {
      expect((await post('/public/survey', {})).statusCode, 400);
    }
    expect((await post('/public/survey', submission())).statusCode, 429);
    expect(store.length, 0);
    expect(store.listCollectorAccounts(), isEmpty);
  });
}
