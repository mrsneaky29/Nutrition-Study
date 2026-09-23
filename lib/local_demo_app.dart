import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'collector/collector_cloud_controller.dart';
import 'collector_auth/collector_access.dart';
import 'cloud/study_cloud_gateway.dart' hide ParticipantLookupResult;
import 'domain/participant_id.dart';
import 'domain/participant_profile.dart';
import 'domain/study_configuration.dart';
import 'domain/visit_record.dart';
import 'domain/ncd_questionnaire.dart';
import 'local_sync/http_local_record_sync_client.dart';
import 'local_sync/local_record_sync_gateway.dart';
import 'local_storage/local_record_store.dart';
import 'presentation/presentation.dart' as ui;
import 'presentation/presentation_widgets.dart' as ui;

bool get _isTestEnvironment {
  try {
    return Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

class LocalDemoApp extends StatefulWidget {
  const LocalDemoApp({
    this.syncGateway,
    this.recordStore,
    this.cloudController,
    this.secureStorage,
    this.localHttpClient,
    super.key,
  });

  final LocalRecordSyncGateway? syncGateway;
  final LocalRecordStore? recordStore;
  final CollectorCloudController? cloudController;
  final FlutterSecureStorage? secureStorage;

  /// Optional transport override for deterministic local-server tests.
  final http.Client? localHttpClient;

  @override
  State<LocalDemoApp> createState() => _LocalDemoAppState();
}

class _LocalRecord {
  _LocalRecord({
    required this.id,
    required this.participant,
    required this.visitNumber,
    required this.collector,
    required this.submittedAt,
    this.stepTwoNote,
    this.questionnaire,
    String? idempotencyKey,
    this.syncState = ui.SyncState.pending,
    this.syncConflict = false,
    this.conflictId,
    this.conflictMessage,
  }) : idempotencyKey = idempotencyKey ?? 'upload_$id';

  final String id;
  final ui.ParticipantDraft participant;
  final int visitNumber;
  final String collector;
  final DateTime submittedAt;
  final String? stepTwoNote;
  final NcdQuestionnaire? questionnaire;
  final String idempotencyKey;
  ui.SyncState syncState;
  bool syncConflict;
  String? conflictId;
  String? conflictMessage;

  factory _LocalRecord.fromStorageJson(Map<String, Object?> json) {
    final participantValue = json['participant'];
    if (participantValue is! Map) {
      throw const FormatException('Stored participant details are invalid.');
    }
    final participant = participantValue.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final syncName = json['syncState']?.toString();
    final syncState = ui.SyncState.values.cast<ui.SyncState?>().firstWhere(
      (state) => state?.name == syncName,
      orElse: () => ui.SyncState.pending,
    )!;
    return _LocalRecord(
      id:
          json['id']?.toString() ??
          (throw const FormatException('Stored record ID is missing.')),
      participant: ui.ParticipantDraft(
        studyId:
            participant['studyId']?.toString() ??
            (throw const FormatException('Stored Study ID is missing.')),
        name:
            participant['name']?.toString() ??
            (throw const FormatException(
              'Stored participant name is missing.',
            )),
        phone:
            participant['indianPhone']?.toString() ??
            (throw const FormatException('Stored phone number is missing.')),
      ),
      visitNumber: json['visitNumber'] is int
          ? json['visitNumber']! as int
          : int.parse(json['visitNumber'].toString()),
      collector:
          json['collectorId']?.toString() ??
          (throw const FormatException('Stored collector is missing.')),
      submittedAt: DateTime.parse(json['submittedAt'].toString()),
      stepTwoNote: json['stepTwoPlaceholderNote']?.toString(),
      questionnaire: NcdQuestionnaire.fromMap(json['questionnaire']),
      idempotencyKey: json['idempotencyKey']?.toString(),
      syncState: syncState,
      syncConflict: json['syncConflict'] == true,
      conflictId: json['conflictId']?.toString(),
      conflictMessage: json['conflictMessage']?.toString(),
    );
  }

  Map<String, Object?> toVisitRecordJson({
    ui.SyncState? syncState,
    bool includeLocalMetadata = false,
  }) => {
    'id': id,
    'participant': {
      'studyId': participant.studyId,
      'name': participant.name,
      'indianPhone': participant.phone,
    },
    'visitNumber': visitNumber,
    'collectorId': collector,
    'createdAt': submittedAt.toUtc().toIso8601String(),
    'updatedAt': submittedAt.toUtc().toIso8601String(),
    'status': 'submitted',
    'syncState': (syncState ?? this.syncState).name,
    'reviewState': 'pending',
    'revision': 1,
    'confirmation': {
      'name': participant.name,
      'indianPhone': participant.phone,
      'visitNumber': visitNumber,
      'confirmedAt': submittedAt.toUtc().toIso8601String(),
    },
    'stepTwoMeasurement': null,
    // Retained as null for compatibility with submissions made before the
    // questionnaire replaced the temporary Step 2 placeholder.
    'stepTwoPlaceholderNote': stepTwoNote,
    'questionnaire': questionnaire?.toMap(),
    'idempotencyKey': idempotencyKey,
    'submittedAt': submittedAt.toUtc().toIso8601String(),
    if (includeLocalMetadata) ...{
      'syncConflict': syncConflict,
      if (conflictId != null) 'conflictId': conflictId,
      if (conflictMessage != null) 'conflictMessage': conflictMessage,
    },
  };
}

class _LocalDemoAppState extends State<LocalDemoApp>
    with WidgetsBindingObserver {
  static const _genericRelease = bool.fromEnvironment('LOCAL_GENERIC_RELEASE');
  static const _envCollectorId = String.fromEnvironment('LOCAL_COLLECTOR_ID');
  static const _envCollectorNumber = String.fromEnvironment(
    'LOCAL_COLLECTOR_NUMBER',
  );

  static final Map<LocalRecordStore, String> _storeProvisioning = {};

  static String? _resolveConfiguredCollectorCode() {
    if (_envCollectorId.isNotEmpty) {
      final raw = _envCollectorId.trim().toUpperCase();
      final match = RegExp(r'^C?(\d+)$').firstMatch(raw);
      if (match != null) {
        final num = int.tryParse(match.group(1)!);
        if (num != null && num >= 1 && num <= 99) {
          return 'C${num.toString().padLeft(3, '0')}';
        }
      }
    }
    if (_envCollectorNumber.isNotEmpty) {
      final num = int.tryParse(_envCollectorNumber.trim());
      if (num != null && num >= 1 && num <= 99) {
        return 'C${num.toString().padLeft(3, '0')}';
      }
    }
    return null;
  }

  static const _demoCollectorCode = 'C001';
  static const _retryInterval = Duration(seconds: 30);
  final List<_LocalRecord> _records = [];
  bool _isSignedIn = false;
  bool _isSigningIn = false;
  String _collectorCode = _demoCollectorCode;
  String? _provisionedCollectorCode;
  String _savedServerUrl = '';
  String _savedApiKey = '';
  bool _isRetrying = false;
  bool _isLoadingRecords = true;
  String? _recordLoadError;
  Future<void> _writeTail = Future<void>.value();
  late LocalRecordSyncGateway _syncGateway;
  late final LocalRecordStore _recordStore;
  Timer? _retryTimer;
  bool _isAppActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncGateway = widget.syncGateway ?? HttpLocalRecordSyncClient();
    _recordStore = widget.recordStore ?? SecureLocalRecordStore();
    if (_genericRelease) {
      _savedServerUrl = HttpLocalRecordSyncClient.configuredApiBaseUrl;
    }
    final envCode = _resolveConfiguredCollectorCode();
    if (envCode != null && !_genericRelease) {
      _collectorCode = envCode;
      _provisionedCollectorCode = envCode;
      _isSignedIn = true;
      _startRetryTimer();
      unawaited(_persistProvisionedCollectorCode(envCode));
    }
    unawaited(_restoreRecords());
  }

  Future<void> _persistProvisionedCollectorCode(String code) async {
    _provisionedCollectorCode = code;
    if (widget.recordStore != null) {
      _storeProvisioning[widget.recordStore!] = code;
    }
    if (widget.secureStorage != null) {
      try {
        await widget.secureStorage!.write(
          key: 'provisioned_collector_code',
          value: code,
        );
      } catch (_) {}
    } else if (!_isTestEnvironment) {
      try {
        const storage = FlutterSecureStorage();
        await storage.write(key: 'provisioned_collector_code', value: code);
      } catch (_) {
        // Secure storage might be unavailable in unit test environment.
      }
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppActive = state == AppLifecycleState.resumed;
    if (_isAppActive && _isSignedIn) {
      unawaited(_retryPendingSubmissions(onlyPending: true));
    }
  }

  void _startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(_retryInterval, (_) {
      if (mounted && _isAppActive && _isSignedIn) {
        unawaited(_retryPendingSubmissions(onlyPending: true));
      }
    });
  }

  Future<void> _signIn(ui.CollectorAccessInput credentials) async {
    final rawCode = credentials.collectorCode.trim().toUpperCase();
    final numberMatch = RegExp(r'^C?(\d+)$').firstMatch(rawCode);
    final number = numberMatch != null
        ? int.tryParse(numberMatch.group(1)!)
        : null;

    if (number == null || number < 1 || number > 99) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Collector number must be between 1 and 99.'),
        ),
      );
      return;
    }

    final formattedCode = 'C${number.toString().padLeft(3, '0')}';

    if (_genericRelease && widget.cloudController == null) {
      setState(() => _isSigningIn = true);
      try {
        final client = HttpLocalRecordSyncClient(
          client: widget.localHttpClient,
          apiBaseUrl: credentials.serverUrl,
          apiKey: credentials.accessKey,
        );
        final token = await client.startSession(formattedCode);
        final storage = widget.secureStorage ?? const FlutterSecureStorage();
        await storage.write(
          key: 'local_server_url',
          value: credentials.serverUrl,
        );
        await storage.write(
          key: 'local_collector_key',
          value: credentials.accessKey,
        );
        await storage.write(key: 'local_session_token', value: token);
        await storage.write(key: 'local_collector_code', value: formattedCode);
        if (!mounted) return;
        _syncGateway = client;
        _savedServerUrl = credentials.serverUrl;
        _savedApiKey = credentials.accessKey;
        setState(() {
          _collectorCode = formattedCode;
          _isSignedIn = true;
        });
        _startRetryTimer();
        unawaited(_retryPendingSubmissions());
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Sign-in failed: $error')));
      } finally {
        if (mounted) setState(() => _isSigningIn = false);
      }
      return;
    }

    // Lock check: Once provisioned, lock the collector number to this phone
    if (_provisionedCollectorCode != null &&
        _provisionedCollectorCode != formattedCode) {
      final lockedNum =
          int.tryParse(
            _provisionedCollectorCode!.replaceAll(RegExp(r'\D'), ''),
          ) ??
          _provisionedCollectorCode;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This phone is locked to Collector $lockedNum. You cannot switch collector accounts.',
          ),
        ),
      );
      return;
    }

    final cloud = widget.cloudController;
    if (cloud != null) {
      setState(() => _isSigningIn = true);
      try {
        final resolution = await cloud.restoreOrClaim(
          collectorCode: CollectorCode(formattedCode),
        );
        if (resolution.session.collectorCode.value != formattedCode) {
          throw const CollectorAccessException(
            CollectorAccessFailure.boundToAnotherDevice,
          );
        }
      } on CollectorAccessException catch (error) {
        if (!mounted) return;
        final message = switch (error.failure) {
          CollectorAccessFailure.unknownCode => 'Collector number not found.',
          CollectorAccessFailure.disabledCollector =>
            'This collector number is disabled.',
          CollectorAccessFailure.boundToAnotherDevice =>
            'This collector number is assigned to another phone.',
          CollectorAccessFailure.invalidSession =>
            'Collector access could not be verified. Try again.',
        };
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        return;
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not connect. Check the internet and try again.',
            ),
          ),
        );
        return;
      } finally {
        if (mounted) setState(() => _isSigningIn = false);
      }
    }
    if (!mounted) return;
    await _persistProvisionedCollectorCode(formattedCode);
    setState(() {
      _collectorCode = formattedCode;
      _isSignedIn = true;
    });
    _startRetryTimer();
    unawaited(_retryPendingSubmissions());
  }

  Future<void> _clearLocalSession() async {
    _retryTimer?.cancel();
    if (mounted) {
      setState(() {
        _isSignedIn = false;
        _savedApiKey = '';
      });
    }
    if (_genericRelease && widget.cloudController == null) {
      final storage = widget.secureStorage ?? const FlutterSecureStorage();
      await storage.delete(key: 'local_collector_key');
      await storage.delete(key: 'local_session_token');
    }
  }

  void _signOut() {
    unawaited(_clearLocalSession());
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingRecords) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_recordLoadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.phonelink_erase_outlined, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Saved submissions could not be opened',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The app has not discarded or replaced the saved data.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _restoreRecords,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!_isSignedIn) {
      return Stack(
        children: [
          ui.SignInScreen(
            key: ValueKey('sign-in-$_collectorCode-$_savedServerUrl'),
            onSignIn: _signIn,
            showLocalSetup: _genericRelease && widget.cloudController == null,
            initialCollectorNumber: _genericRelease
                ? (int.tryParse(_collectorCode.replaceAll(RegExp(r'\D'), '')) ??
                          1)
                      .toString()
                : '',
            initialServerUrl: _savedServerUrl,
            initialAccessKey: _genericRelease ? '' : _savedApiKey,
          ),
          if (_isSigningIn)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (widget.cloudController == null && !_genericRelease)
            const Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                minimum: EdgeInsets.all(12),
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      'LOCAL DEMO · collector numbers: 1 to 99',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }
    return _collectorHome();
  }

  Future<void> _restoreRecords() async {
    if (mounted) {
      setState(() {
        _isLoadingRecords = true;
        _recordLoadError = null;
      });
    }
    try {
      final stored = await _recordStore.readAll();
      final restored = stored.map(_LocalRecord.fromStorageJson).toList();
      if (_provisionedCollectorCode == null) {
        if (widget.recordStore != null &&
            _storeProvisioning.containsKey(widget.recordStore!)) {
          _provisionedCollectorCode = _storeProvisioning[widget.recordStore!];
        }
      }
      if (_provisionedCollectorCode == null) {
        if (widget.secureStorage != null) {
          try {
            final code = await widget.secureStorage!.read(
              key: 'provisioned_collector_code',
            );
            if (code != null && code.isNotEmpty) {
              _provisionedCollectorCode = code;
            }
          } catch (_) {}
        } else if (!_isTestEnvironment) {
          try {
            const storage = FlutterSecureStorage();
            final code = await storage.read(key: 'provisioned_collector_code');
            if (code != null && code.isNotEmpty) {
              _provisionedCollectorCode = code;
            }
          } catch (_) {}
        }
      }
      if (_provisionedCollectorCode == null && restored.isNotEmpty) {
        _provisionedCollectorCode = restored.first.collector;
      }
      if (_genericRelease && widget.cloudController == null) {
        final storage = widget.secureStorage ?? const FlutterSecureStorage();
        _savedServerUrl =
            await storage.read(key: 'local_server_url') ?? _savedServerUrl;
        _savedApiKey = await storage.read(key: 'local_collector_key') ?? '';
        final token = await storage.read(key: 'local_session_token');
        final code = await storage.read(key: 'local_collector_code');
        if (_savedServerUrl.isNotEmpty &&
            _savedApiKey.isNotEmpty &&
            token != null &&
            token.isNotEmpty &&
            code != null &&
            code.isNotEmpty) {
          _syncGateway = HttpLocalRecordSyncClient(
            client: widget.localHttpClient,
            apiBaseUrl: _savedServerUrl,
            apiKey: _savedApiKey,
            sessionToken: token,
          );
          _collectorCode = code;
          _isSignedIn = true;
          _startRetryTimer();
        }
      }
      if (!mounted) return;
      setState(() {
        _records
          ..clear()
          ..addAll(restored);
        _isLoadingRecords = false;
      });
      if (_isSignedIn) {
        unawaited(_retryPendingSubmissions());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recordLoadError = 'unavailable';
        _isLoadingRecords = false;
      });
    }
  }

  Future<void> _persistRecords() {
    final snapshot = _records
        .map((record) => record.toVisitRecordJson(includeLocalMetadata: true))
        .toList(growable: false);
    _writeTail = _writeTail.then(
      (_) => _recordStore.writeAll(snapshot),
      onError: (_) => _recordStore.writeAll(snapshot),
    );
    return _writeTail;
  }

  Future<void> _persistSubmittedRecord(_LocalRecord record) async {
    final index = _records.indexWhere((existing) => existing.id == record.id);
    final previous = index == -1 ? null : _records[index];
    if (index == -1) {
      _records.add(record);
    } else {
      _records[index] = record;
    }
    try {
      await _persistRecords();
    } catch (_) {
      if (index == -1) {
        _records.remove(record);
      } else {
        _records[index] = previous!;
      }
      rethrow;
    }
  }

  Widget _collectorHome() {
    final submissions = _records
        .where((record) => record.collector == _collectorCode)
        .map(_summary)
        .toList()
        .reversed
        .toList();
    return ui.CollectorHomeScreen(
      collectorName:
          'Collector ${int.tryParse(_collectorCode.replaceAll(RegExp(r'\D'), '')) ?? 1}',
      pendingCount: _records
          .where(
            (record) =>
                record.collector == _collectorCode &&
                !record.syncConflict &&
                (record.syncState == ui.SyncState.pending ||
                    record.syncState == ui.SyncState.failed),
          )
          .length,
      recentSubmissions: submissions.take(5).toList(),
      onStartEntry: _startEntry,
      onOpenSubmissions: () => _openSubmissions(submissions),
      onOpenSubmission: _openSubmission,
      onRetryPending: _retryPendingSubmissions,
      isRetrying: _isRetrying,
      onSignOut: _signOut,
    );
  }

  Future<void> _startEntry() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (screenContext) => ui.ParticipantLookupScreen(
          onCancel: () => Navigator.pop(screenContext),
          onSubmit: (participant) =>
              _checkParticipant(screenContext, participant),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _checkParticipant(
    BuildContext screenContext,
    ui.ParticipantDraft participant,
  ) async {
    final phone = participant.phone.replaceAll(RegExp(r'\D'), '');
    final validPhone = RegExp(r'^(?:91)?[6-9]\d{9}$').hasMatch(phone);
    if (!validPhone) {
      ScaffoldMessenger.of(screenContext).showSnackBar(
        const SnackBar(content: Text('Enter a valid Indian mobile number.')),
      );
      return;
    }

    final canonicalPhone = phone.length == 12 ? '+$phone' : '+91$phone';
    final matchingPhone = _records
        .where(
          (record) =>
              record.collector == _collectorCode &&
              record.participant.phone == canonicalPhone,
        )
        .toList();
    final localCandidates = <String, ParticipantLookupCandidate>{};
    for (final record in matchingPhone) {
      final id = normalizeParticipantStudyId(record.participant.studyId);
      if (id == null) continue;
      final previous = localCandidates[id];
      final nextVisit = record.visitNumber + 1;
      localCandidates[id] = ParticipantLookupCandidate(
        studyId: id,
        name: record.participant.name,
        nextVisitNumber:
            previous == null || nextVisit > previous.nextVisitNumber
            ? nextVisit
            : previous.nextVisitNumber,
      );
    }
    String? participantNumber;
    var visitNumber = 1;
    String? allocatedVisitId;
    var assignedName = participant.name.trim();
    var assignedPhone = canonicalPhone;
    final cloud = widget.cloudController;
    if (cloud != null) {
      try {
        final allocation = await cloud.allocateNewOrRepeatVisit(
          participant: NewParticipantDetails(
            name: participant.name.trim(),
            indianPhone: canonicalPhone,
          ),
        );
        participantNumber = allocation.allocation.participant.studyId;
        visitNumber = allocation.allocation.visitNumber;
        allocatedVisitId = allocation.allocation.visitId;
        assignedName = allocation.allocation.participant.name;
        assignedPhone = allocation.allocation.participant.indianPhone;
      } catch (_) {
        if (!screenContext.mounted) return;
        ScaffoldMessenger.of(screenContext).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not reserve the visit. Check the internet and try again.',
            ),
          ),
        );
        return;
      }
    } else {
      // Consult both sources: the phone may have one local Study ID and a
      // different Study ID on the PC. A local match alone is not conclusive.
      ParticipantLookupResult? lookup;
      try {
        lookup = await _syncGateway
            .lookupParticipant(canonicalPhone)
            .timeout(const Duration(seconds: 3));
      } on CollectorSessionExpiredException {
        await _clearLocalSession();
        if (!screenContext.mounted) return;
        ScaffoldMessenger.of(screenContext).showSnackBar(
          const SnackBar(
            content: Text(
              'This collector number signed in on another phone. Sign in again here to take over.',
            ),
          ),
        );
        return;
      } catch (_) {
        lookup = null;
      }
      if (!screenContext.mounted) return;
      final candidatesById = Map<String, ParticipantLookupCandidate>.of(
        localCandidates,
      );
      final remoteCandidates = lookup?.isAmbiguous == true
          ? lookup!.candidates
          : lookup?.found == true && lookup?.studyId != null
          ? [
              ParticipantLookupCandidate(
                studyId: lookup!.studyId!,
                name: lookup.name?.trim().isNotEmpty == true
                    ? lookup.name!.trim()
                    : assignedName,
                nextVisitNumber: lookup.nextVisitNumber ?? 2,
              ),
            ]
          : <ParticipantLookupCandidate>[];
      for (final remote in remoteCandidates) {
        final id = normalizeParticipantStudyId(remote.studyId);
        if (id == null) continue;
        final local = candidatesById[id];
        candidatesById[id] = ParticipantLookupCandidate(
          studyId: id,
          name: remote.name,
          nextVisitNumber:
              local == null || remote.nextVisitNumber > local.nextVisitNumber
              ? remote.nextVisitNumber
              : local.nextVisitNumber,
        );
      }
      final candidates = candidatesById.values.toList();
      ParticipantLookupCandidate? selected;
      if (candidates.length == 1 &&
          candidates.single.name.trim().toLowerCase() ==
              assignedName.toLowerCase()) {
        selected = candidates.single;
      } else if (candidates.isNotEmpty) {
        final choice = await _chooseParticipantForPhone(
          screenContext,
          candidates,
        );
        if (choice == null) return;
        selected = choice.candidate;
      }
      participantNumber = selected?.studyId ?? _nextParticipantNumber();
      assignedName = selected?.name ?? assignedName;
      visitNumber = selected?.nextVisitNumber ?? 1;
    }
    if (!screenContext.mounted) return;
    final normalized = ui.ParticipantDraft(
      studyId: participantNumber,
      name: assignedName,
      phone: assignedPhone,
    );
    final prior = _records
        .where(
          (record) =>
              record.collector == _collectorCode &&
              record.participant.studyId == participantNumber,
        )
        .toList();
    if (prior.isNotEmpty) {
      final previous = prior.last.participant;
      if (previous.name.toLowerCase() != normalized.name.toLowerCase() ||
          previous.phone != normalized.phone) {
        final confirmed = await showDialog<bool>(
          context: screenContext,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Details do not match'),
            content: const Text(
              'This Study ID already has a different name or phone number. '
              'Please confirm the details with the participant.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Go back'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Details confirmed'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
    }

    if (cloud == null && prior.isNotEmpty) {
      visitNumber =
          prior.fold<int>(
            0,
            (max, record) =>
                record.visitNumber > max ? record.visitNumber : max,
          ) +
          1;
    }
    if (!screenContext.mounted) return;
    final record = await Navigator.of(screenContext).push<_LocalRecord>(
      MaterialPageRoute(
        builder: (_) => _LocalVisitFlow(
          participant: normalized,
          visitNumber: visitNumber,
          collectorCode: _collectorCode,
          visitId: allocatedVisitId,
          onSync: _syncRecord,
          onPersist: _persistSubmittedRecord,
          onLookupPriorRecords: (studyId) => _records
              .where(
                (r) =>
                    r.collector == _collectorCode &&
                    r.participant.studyId == studyId,
              )
              .toList(),
        ),
      ),
    );
    if (record != null) {
      await _persistSubmittedRecord(record);
      unawaited(_retryPendingSubmissions());
    }
    if (screenContext.mounted) Navigator.pop(screenContext);
  }

  Future<_ParticipantSelection?> _chooseParticipantForPhone(
    BuildContext context,
    List<ParticipantLookupCandidate> candidates,
  ) => showDialog<_ParticipantSelection>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Choose participant'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text(
              'This phone number may be shared. Check the participant’s '
              'study card or logbook before choosing a Study ID.',
            ),
            const SizedBox(height: 12),
            for (final candidate in candidates)
              ListTile(
                title: Text('${candidate.name} · ${candidate.studyId}'),
                subtitle: Text('Next visit ${candidate.nextVisitNumber}'),
                onTap: () => Navigator.pop(
                  dialogContext,
                  _ParticipantSelection(candidate),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(dialogContext, const _ParticipantSelection(null)),
          child: const Text('New participant'),
        ),
      ],
    ),
  );

  int _collectorNumber() {
    final digits = _collectorCode.replaceAll(RegExp(r'\D'), '');
    return int.tryParse(digits) ?? 1;
  }

  String _nextParticipantNumber() {
    final collectorNum = _collectorNumber();
    if (_genericRelease) {
      final random = Random.secure();
      String candidate;
      do {
        final upper = 10000000 + random.nextInt(90000000);
        final lower = random.nextInt(100000000);
        candidate = formatCollectorParticipantStudyId(
          collectorNum,
          upper * 100000000 + lower,
        );
      } while (_records.any(
        (record) => record.participant.studyId == candidate,
      ));
      return candidate;
    }
    final prefix = collectorParticipantPrefix(collectorNum);
    var maxSeq = 0;
    for (final record in _records) {
      final studyId = normalizeParticipantStudyId(record.participant.studyId);
      if (studyId != null && studyId.startsWith(prefix)) {
        final seqPart = studyId.substring(prefix.length);
        final seq = int.tryParse(seqPart);
        if (seq != null && seq > maxSeq) {
          maxSeq = seq;
        }
      }
    }
    return formatCollectorParticipantStudyId(collectorNum, maxSeq + 1);
  }

  void _openSubmissions(List<ui.SubmissionSummary> submissions) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (screenContext) => _LocalSubmissionsScreen(
          records: _records
              .where((record) => record.collector == _collectorCode)
              .toList()
              .reversed
              .toList(),
          onBack: () => Navigator.pop(screenContext),
          onOpen: _openSubmissionRecord,
        ),
      ),
    );
  }

  void _openSubmissionRecord(_LocalRecord record) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (screenContext) => _LocalSubmissionDetailScreen(
          record: record,
          onBack: () => Navigator.pop(screenContext),
          onRetry: _manualRetryRecord,
        ),
      ),
    );
  }

  void _openSubmission(ui.SubmissionSummary summary) {
    final record = _records.cast<_LocalRecord?>().firstWhere(
      (r) => r?.id == summary.id,
      orElse: () => null,
    );
    if (record != null) {
      _openSubmissionRecord(record);
    }
  }

  Future<void> _manualRetryRecord(_LocalRecord record) async {
    setState(() => _isRetrying = true);
    try {
      await _syncRecord(record);
      await _persistRecords();
      if (mounted) {
        if (record.syncState == ui.SyncState.synced) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Record synced successfully.')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isRetrying = false);
    }
  }

  ui.SubmissionSummary _summary(_LocalRecord record) => ui.SubmissionSummary(
    id: record.id,
    participantName: record.participant.name,
    studyId: record.participant.studyId,
    visitNumber: record.visitNumber,
    submittedAt: record.submittedAt,
    syncState: record.syncState,
  );

  Future<void> _retryPendingSubmissions({bool onlyPending = false}) async {
    if (_isRetrying) return;
    final pending = _records
        .where(
          (record) =>
              record.collector == _collectorCode &&
              !record.syncConflict &&
              (record.syncState == ui.SyncState.pending ||
                  (!onlyPending && record.syncState == ui.SyncState.failed)),
        )
        .toList();
    if (pending.isEmpty) return;

    if (!mounted) return;
    setState(() => _isRetrying = true);
    try {
      for (final record in pending) {
        await _syncRecord(record);
        try {
          await _persistRecords();
        } catch (_) {
          // A previously saved pending record remains durable, even if the
          // server accepted it but saving the new sync marker failed.
          record.syncState = record.syncConflict
              ? ui.SyncState.failed
              : ui.SyncState.pending;
          break;
        }
        if (!_isSignedIn) break;
      }
    } finally {
      if (mounted) setState(() => _isRetrying = false);
    }
  }

  Future<void> _syncRecord(_LocalRecord record) async {
    final cloud = widget.cloudController;
    if (cloud != null) {
      try {
        await cloud.uploadIdempotently(
          record: _domainRecord(record),
          idempotencyKey: record.idempotencyKey,
        );
        record.syncState = ui.SyncState.synced;
        record.syncConflict = false;
        record.conflictId = null;
        record.conflictMessage = null;
      } on CollectorSessionRequiredException {
        record.syncState = ui.SyncState.failed;
      } catch (_) {
        record.syncState = ui.SyncState.pending;
      }
      return;
    }
    try {
      final syncPayload = record.toVisitRecordJson(
        syncState: ui.SyncState.synced,
      );
      SyncResponse response;
      if (_syncGateway is HttpLocalRecordSyncClient) {
        response = await _syncGateway.sendRecordDetailed(syncPayload);
      } else {
        try {
          final dynamic dynGw = _syncGateway;
          final dynamic res = await dynGw.sendRecordDetailed(syncPayload);
          if (res is SyncResponse) {
            response = res;
          } else {
            response = await _syncGateway.sendRecordDetailed(syncPayload);
          }
        } catch (_) {
          response = await _syncGateway.sendRecordDetailed(syncPayload);
        }
      }
      switch (response.result) {
        case LocalRecordSyncResult.synced:
          record.syncState = ui.SyncState.synced;
          record.syncConflict = false;
          record.conflictId = null;
          record.conflictMessage = null;
        case LocalRecordSyncResult.pending:
          // Keep a known conflict out of automatic retry loops if the next
          // manual attempt happens while the server is unavailable.
          record.syncState = record.syncConflict
              ? ui.SyncState.failed
              : ui.SyncState.pending;
        case LocalRecordSyncResult.failed:
          record.syncState = ui.SyncState.failed;
          if (_genericRelease &&
              response.statusCode == HttpStatus.unauthorized) {
            await _clearLocalSession();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'This collector number signed in on another phone. Sign in again here to take over.',
                  ),
                ),
              );
            }
          }
        case LocalRecordSyncResult.conflict:
          record.syncState = ui.SyncState.failed;
          record.syncConflict = true;
          final lastResp = _syncGateway.lastResponse;
          record.conflictId =
              response.conflictId ??
              lastResp?.conflictId ??
              'CONFLICT-${record.id}';
          record.conflictMessage = response.message ?? lastResp?.message ?? 'HTTP 409 Conflict: A conflicting record already exists on the server.';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Sync conflict: entry is saved on this phone and needs admin review.',
                ),
              ),
            );
          }
      }
    } catch (_) {
      record.syncState = record.syncConflict
          ? ui.SyncState.failed
          : ui.SyncState.pending;
    }
  }
}

class _ParticipantSelection {
  const _ParticipantSelection(this.candidate);
  final ParticipantLookupCandidate? candidate;
}

VisitRecord _domainRecord(_LocalRecord record) {
  final match = RegExp(r'^(.*?)(\d+)$').firstMatch(record.participant.studyId);
  if (match == null || match.group(1)!.isEmpty) {
    throw StateError('The participant number is invalid.');
  }
  final digits = match.group(2)!;
  final number = int.parse(digits);
  final participant = ParticipantProfile(
    studyId: record.participant.studyId,
    name: record.participant.name,
    indianPhone: record.participant.phone,
    idPolicy: ParticipantIdPolicy(
      prefix: match.group(1)!,
      firstNumber: number,
      lastNumber: number,
      padding: digits.length,
    ),
  );
  return VisitRecord(
    id: record.id,
    participant: participant,
    visitNumber: record.visitNumber,
    collectorId: record.collector,
    createdAt: record.submittedAt,
    updatedAt: record.submittedAt,
    submittedAt: record.submittedAt,
    status: VisitStatus.submitted,
    syncState: SyncState.pending,
    reviewState: NeutralReviewState.pending,
    revision: 1,
    confirmation: VisitConfirmation(
      name: participant.name,
      indianPhone: participant.indianPhone,
      visitNumber: record.visitNumber,
      confirmedAt: record.submittedAt,
    ),
    questionnaire: record.questionnaire,
    stepTwoPlaceholderNote: record.stepTwoNote,
  );
}

class _LocalVisitFlow extends StatefulWidget {
  const _LocalVisitFlow({
    required this.participant,
    required this.visitNumber,
    required this.collectorCode,
    required this.onSync,
    required this.onPersist,
    this.visitId,
    this.onLookupPriorRecords,
  });

  final ui.ParticipantDraft participant;
  final int visitNumber;
  final String collectorCode;
  final String? visitId;
  final Future<void> Function(_LocalRecord record) onSync;
  final Future<void> Function(_LocalRecord record) onPersist;
  final List<_LocalRecord> Function(String studyId)? onLookupPriorRecords;

  @override
  State<_LocalVisitFlow> createState() => _LocalVisitFlowState();
}

class _LocalVisitFlowState extends State<_LocalVisitFlow> {
  int _step = 0;
  late ui.ParticipantDraft _participant;
  late int _visitNumber;
  NcdQuestionnaire? _questionnaire;
  String? _stepTwoNote;
  _LocalRecord? _record;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _participant = widget.participant;
    _visitNumber = widget.visitNumber;
  }

  void _specifyExistingStudyId(String newStudyId, int? visitNum) {
    final normalizedId =
        normalizeParticipantStudyId(newStudyId) ??
        _normalizeStudyId(newStudyId);
    final prior = widget.onLookupPriorRecords?.call(normalizedId) ?? [];
    final resolvedVisit =
        visitNum ??
        (prior.isNotEmpty
            ? prior.fold<int>(
                    0,
                    (max, r) => r.visitNumber > max ? r.visitNumber : max,
                  ) +
                  1
            : 2);
    setState(() {
      _participant = ui.ParticipantDraft(
        studyId: normalizedId,
        name: _participant.name,
        phone: _participant.phone,
      );
      _visitNumber = resolvedVisit;
    });
  }

  @override
  Widget build(BuildContext context) => switch (_step) {
    0 => _LocalVisitConfirmationScreen(
      participant: _participant,
      proposedVisitNumber: _visitNumber,
      onBack: () => Navigator.pop(context),
      onConfirm: () => setState(() => _step = 1),
      onSpecifyExistingId: _specifyExistingStudyId,
    ),
    1 => ui.NcdQuestionnaireScreen(
      onBack: () => setState(() => _step = 0),
      onComplete: (questionnaire) => setState(() {
        _questionnaire = questionnaire;
        _step = 2;
      }),
    ),
    2 => ui.OptionalStepTwoScreen(
      onBack: () => setState(() => _step = 1),
      onSkip: () => setState(() {
        _stepTwoNote = null;
        _step = 3;
      }),
      onContinue: (note) => setState(() {
        _stepTwoNote = note;
        _step = 3;
      }),
    ),
    3 => ui.ReviewScreen(
      participant: _participant,
      visitNumber: _visitNumber,
      questionnaire: _questionnaire,
      optionalNote: _stepTwoNote,
      onBack: () => setState(() => _step = 2),
      onSubmit: _isSubmitting ? null : _submit,
      isSubmitting: _isSubmitting,
    ),
    _ => ui.ReceiptScreen(
      submission: ui.SubmissionSummary(
        id: _record!.id,
        participantName: _participant.name,
        studyId: _participant.studyId,
        visitNumber: _visitNumber,
        submittedAt: _record!.submittedAt,
        syncState: _record!.syncState,
      ),
      questionnaire: _record!.questionnaire,
      onDone: () => Navigator.pop(context, _record),
      onViewSubmission: _openSubmission,
    ),
  };

  void _openSubmission() {
    final record = _record;
    if (record == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (screenContext) => _LocalSubmissionDetailScreen(
          record: record,
          onBack: () => Navigator.pop(screenContext),
          onRetry: (r) async {
            await widget.onSync(r);
            await widget.onPersist(r);
          },
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final now = DateTime.now();
    final record = _LocalRecord(
      id:
          widget.visitId ??
          'LOCAL-${now.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
      participant: _participant,
      visitNumber: _visitNumber,
      collector: widget.collectorCode,
      submittedAt: now,
      stepTwoNote: _stepTwoNote,
      questionnaire: _questionnaire,
    );
    setState(() {
      _record = record;
      _isSubmitting = true;
    });
    try {
      // A completed visit must be durable on the phone before any network
      // request can succeed. The server can then be unavailable indefinitely.
      await widget.onPersist(record);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _record = null;
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save on this phone. Entry was not sent. Try again.',
          ),
        ),
      );
      return;
    }
    try {
      await widget.onSync(record);
      await widget.onPersist(record);
    } catch (_) {
      // The first write succeeded, so a pending copy is still on the phone.
      record.syncState = record.syncConflict
          ? ui.SyncState.failed
          : ui.SyncState.pending;
    }
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _step = 4;
    });
  }
}

String _normalizeStudyId(String input) {
  final trimmed = input.trim().toUpperCase();
  if (trimmed.startsWith('P')) {
    final numPart = int.tryParse(trimmed.substring(1));
    if (numPart != null) {
      return 'P${numPart.toString().padLeft(3, '0')}';
    }
  } else {
    final numPart = int.tryParse(trimmed);
    if (numPart != null) {
      return 'P${numPart.toString().padLeft(3, '0')}';
    }
  }
  return trimmed;
}

class _ConflictBadge extends StatelessWidget {
  const _ConflictBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.error, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Sync Conflict - Review Required',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.error,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalVisitConfirmationScreen extends StatelessWidget {
  const _LocalVisitConfirmationScreen({
    required this.participant,
    required this.proposedVisitNumber,
    required this.onConfirm,
    required this.onBack,
    required this.onSpecifyExistingId,
  });

  final ui.ParticipantDraft participant;
  final int proposedVisitNumber;
  final VoidCallback onConfirm;
  final VoidCallback onBack;
  final void Function(String studyId, int? visitNum) onSpecifyExistingId;

  void _showSpecifyDialog(BuildContext context) {
    final idController = TextEditingController();
    final visitController = TextEditingController(
      text: proposedVisitNumber == 1 ? '2' : '$proposedVisitNumber',
    );
    String? errorMessage;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Specify Study ID from card/logbook'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'If this participant was enrolled on another collector\'s phone, '
                'enter their existing Study ID from their study card or logbook:',
              ),
              const SizedBox(height: 16),
              if (errorMessage != null) ...[
                Text(
                  errorMessage!,
                  style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: idController,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Study ID from card/logbook',
                  hintText: 'e.g. P001',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: visitController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Visit number',
                  hintText: '2',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final text = idController.text.trim();
                final normalized = normalizeParticipantStudyId(text);
                if (normalized == null || !isValidParticipantStudyId(text)) {
                  setDialogState(() {
                    errorMessage = 'Invalid Study ID format. Must be like C01-000001 or P001.';
                  });
                  return;
                }
                final visitText = visitController.text.trim();
                final isInteger = RegExp(r'^\d+$').hasMatch(visitText);
                final visit = isInteger ? int.tryParse(visitText) : null;
                if (visit == null || visit < 2) {
                  setDialogState(() {
                    errorMessage =
                        'Visit number must be an integer of 2 or greater.';
                  });
                  return;
                }
                onSpecifyExistingId(normalized, visit);
                Navigator.pop(dialogContext);
              },
              child: const Text('Confirm Study ID'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ui.ResponsivePage(
    appBar: AppBar(leading: BackButton(onPressed: onBack)),
    child: ListView(
      children: [
        const ui.PageHeading(
          title: 'Confirm visit',
          subtitle:
              'Check the automatically assigned participant and visit numbers.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DetailRow(
                  label: 'Participant number',
                  value: participant.studyId,
                ),
                _DetailRow(label: 'Participant name', value: participant.name),
                _DetailRow(label: 'Phone number', value: participant.phone),
                const Divider(height: 32),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                    child: Text('$proposedVisitNumber'),
                  ),
                  title: Text(
                    proposedVisitNumber == 1
                        ? 'First visit'
                        : 'Visit $proposedVisitNumber',
                  ),
                  subtitle: Text(
                    proposedVisitNumber == 1
                        ? 'A new participant number has been assigned.'
                        : 'Updated automatically from this participant’s history.',
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _showSpecifyDialog(context),
                  icon: const Icon(Icons.badge_outlined),
                  label: const Text(
                    'Specify existing Study ID (from card/logbook)',
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onConfirm,
                  child: const Text('Confirm and continue'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}

class _LocalSubmissionsScreen extends StatefulWidget {
  const _LocalSubmissionsScreen({
    required this.records,
    required this.onOpen,
    this.onBack,
  });

  final List<_LocalRecord> records;
  final ValueChanged<_LocalRecord> onOpen;
  final VoidCallback? onBack;

  @override
  State<_LocalSubmissionsScreen> createState() =>
      _LocalSubmissionsScreenState();
}

class _LocalSubmissionsScreenState extends State<_LocalSubmissionsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final visible = widget.records.where((item) {
      final query = _query.toLowerCase();
      return item.participant.name.toLowerCase().contains(query) ||
          item.participant.studyId.toLowerCase().contains(query);
    }).toList();

    return ui.ResponsivePage(
      appBar: AppBar(leading: BackButton(onPressed: widget.onBack)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ui.PageHeading(
            title: 'My submissions',
            subtitle: 'Entries created by your account.',
          ),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by name or Study ID',
            ),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: visible.isEmpty
                ? const ui.EmptyState(
                    icon: Icons.search_off_outlined,
                    title: 'No matching submissions',
                    message: 'Try a different search or create a new participant entry.',
                  )
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      return Card(
                        child: InkWell(
                          onTap: () => widget.onOpen(item),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.participant.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${item.participant.studyId} · Visit ${item.visitNumber}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 8),
                                item.syncConflict
                                    ? const _ConflictBadge()
                                    : ui.StatusChip(state: item.syncState),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LocalSubmissionDetailScreen extends StatefulWidget {
  const _LocalSubmissionDetailScreen({
    required this.record,
    required this.onRetry,
    this.onBack,
  });

  final _LocalRecord record;
  final Future<void> Function(_LocalRecord record) onRetry;
  final VoidCallback? onBack;

  @override
  State<_LocalSubmissionDetailScreen> createState() =>
      _LocalSubmissionDetailScreenState();
}

class _LocalSubmissionDetailScreenState
    extends State<_LocalSubmissionDetailScreen> {
  bool _isRetrying = false;

  void _showConflictReviewDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        title: const Text('Conflict Review'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A conflict (HTTP 409) occurred while uploading this submission to the study server.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('Submission ID: ${widget.record.id}'),
            if (widget.record.conflictId != null)
              Text('Conflict Reference: ${widget.record.conflictId}'),
            if (widget.record.conflictMessage != null)
              Text('Conflict Details: ${widget.record.conflictMessage}'),
            Text(
              'Participant: ${widget.record.participant.name} (${widget.record.participant.studyId})',
            ),
            Text('Visit: ${widget.record.visitNumber}'),
            Text('Recorded: ${widget.record.submittedAt.toLocal()}'),
            const SizedBox(height: 12),
            const Text(
              'The entry remains safely stored locally on this phone. You can manually retry uploading once server-side conflicts are addressed.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Retry Upload'),
            onPressed: () {
              Navigator.pop(dialogContext);
              _retry();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _retry() async {
    setState(() => _isRetrying = true);
    try {
      await widget.onRetry(widget.record);
    } finally {
      if (mounted) setState(() => _isRetrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final isConflicted = record.syncConflict;

    return ui.ResponsivePage(
      appBar: AppBar(
        leading: BackButton(onPressed: widget.onBack),
        actions: [
          TextButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Editing submitted entries is not available in this demo.',
                ),
              ),
            ),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit'),
          ),
        ],
      ),
      child: ListView(
        children: [
          ui.PageHeading(
            title: record.participant.name,
            subtitle:
                '${record.participant.studyId} · Visit ${record.visitNumber}',
          ),
          if (isConflicted) ...[
            Card(
              color: Theme.of(context).colorScheme.errorContainer
                  .withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Theme.of(context).colorScheme.error,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Sync Conflict - Review Required',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      record.conflictMessage != null
                          ? 'HTTP 409 Conflict: ${record.conflictMessage}\n\n'
                                'Conflict Reference: ${record.conflictId ?? record.id}\n'
                                'Your data is safely preserved on this device and will NOT be overwritten or discarded. '
                                'Automatic sync is paused for this record until you review and manually retry.'
                          : 'HTTP 409 Conflict: This record conflicts with an existing entry on the server. '
                                'Your data is safely preserved on this device and will NOT be overwritten or discarded. '
                                'Automatic sync is paused for this record until you review and manually retry.',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _showConflictReviewDialog(context),
                          icon: const Icon(Icons.rate_review_outlined),
                          label: const Text('Review Conflict'),
                        ),
                        FilledButton.icon(
                          onPressed: _isRetrying ? null : _retry,
                          icon: _isRetrying
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.cloud_upload_outlined),
                          label: const Text('Retry Upload'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Submission details',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  _DetailLine('Submission ID', record.id),
                  if (record.conflictId != null)
                    _DetailLine('Conflict Ref', record.conflictId!),
                  _DetailLine('Recorded', '${record.submittedAt.toLocal()}'),
                  _DetailLine('Study ID', record.participant.studyId),
                  _DetailLine('Phone number', record.participant.phone),
                  const Divider(height: 32),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      const Text('Sync status'),
                      if (isConflicted)
                        const _ConflictBadge()
                      else
                        ui.StatusChip(state: record.syncState),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Editing submitted entries is not available in this demo.',
                ),
              ),
            ),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit submission'),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
