import 'dart:async';

import 'package:flutter/material.dart';

import 'collector/collector_cloud_controller.dart';
import 'collector_auth/collector_access.dart';
import 'cloud/study_cloud_gateway.dart';
import 'domain/participant_profile.dart';
import 'domain/study_configuration.dart';
import 'domain/visit_record.dart';
import 'domain/ncd_questionnaire.dart';
import 'local_sync/http_local_record_sync_client.dart';
import 'local_sync/local_record_sync_gateway.dart';
import 'local_storage/local_record_store.dart';
import 'presentation/presentation.dart' as ui;

class LocalDemoApp extends StatefulWidget {
  const LocalDemoApp({
    this.syncGateway,
    this.recordStore,
    this.cloudController,
    super.key,
  });

  final LocalRecordSyncGateway? syncGateway;
  final LocalRecordStore? recordStore;
  final CollectorCloudController? cloudController;

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
    );
  }

  Map<String, Object?> toVisitRecordJson({ui.SyncState? syncState}) => {
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
  };
}

class _LocalDemoAppState extends State<LocalDemoApp> {
  static const _demoCollectorCode = 'C001';
  final List<_LocalRecord> _records = [];
  bool _isSignedIn = false;
  bool _isSigningIn = false;
  String _collectorCode = _demoCollectorCode;
  bool _isRetrying = false;
  bool _isLoadingRecords = true;
  String? _recordLoadError;
  Future<void> _writeTail = Future<void>.value();
  late final LocalRecordSyncGateway _syncGateway;
  late final LocalRecordStore _recordStore;

  @override
  void initState() {
    super.initState();
    _syncGateway = widget.syncGateway ?? HttpLocalRecordSyncClient();
    _recordStore = widget.recordStore ?? SecureLocalRecordStore();
    unawaited(_restoreRecords());
  }

  Future<void> _signIn(ui.CollectorAccessInput credentials) async {
    final cloud = widget.cloudController;
    if (cloud == null && credentials.collectorCode != _demoCollectorCode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use the local demo code shown below.')),
      );
      return;
    }
    if (cloud != null) {
      setState(() => _isSigningIn = true);
      try {
        final resolution = await cloud.restoreOrClaim(
          collectorCode: CollectorCode(credentials.collectorCode),
        );
        if (resolution.session.collectorCode.value !=
            credentials.collectorCode) {
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
    setState(() {
      _collectorCode = credentials.collectorCode;
      _isSignedIn = true;
    });
    unawaited(_retryPendingSubmissions());
  }

  void _signOut() => setState(() => _isSignedIn = false);

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
          ui.SignInScreen(onSignIn: _signIn),
          if (_isSigningIn)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (widget.cloudController == null)
            const Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                minimum: EdgeInsets.all(12),
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      'LOCAL DEMO · collector number: 1',
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
      if (!mounted) return;
      setState(() {
        _records
          ..clear()
          ..addAll(restored);
        _isLoadingRecords = false;
      });
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
        .map((record) => record.toVisitRecordJson())
        .toList(growable: false);
    _writeTail = _writeTail.then(
      (_) => _recordStore.writeAll(snapshot),
      onError: (_) => _recordStore.writeAll(snapshot),
    );
    return _writeTail;
  }

  Future<void> _persistSubmittedRecord(_LocalRecord record) async {
    final index = _records.indexWhere((existing) => existing.id == record.id);
    if (index == -1) {
      _records.add(record);
    } else {
      _records[index] = record;
    }
    await _persistRecords();
  }

  Widget _collectorHome() {
    final submissions = _records
        .where((record) => record.collector == _collectorCode)
        .map(_summary)
        .toList()
        .reversed
        .toList();
    return ui.CollectorHomeScreen(
      collectorName: 'Collector ${int.parse(_collectorCode.substring(1))}',
      pendingCount: _records
          .where(
            (record) =>
                record.syncState == ui.SyncState.pending ||
                record.syncState == ui.SyncState.failed,
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
        .where((record) => record.participant.phone == canonicalPhone)
        .toList();
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
      participantNumber = matchingPhone.isNotEmpty
          ? matchingPhone.last.participant.studyId
          : _nextParticipantNumber();
    }
    if (!screenContext.mounted) return;
    if (participantNumber == null) {
      ScaffoldMessenger.of(screenContext).showSnackBar(
        const SnackBar(
          content: Text('The configured participant range is full.'),
        ),
      );
      return;
    }
    final normalized = ui.ParticipantDraft(
      studyId: participantNumber,
      name: assignedName,
      phone: assignedPhone,
    );
    final prior = _records
        .where((record) => record.participant.studyId == participantNumber)
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

    if (cloud == null) {
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
        ),
      ),
    );
    if (record != null) {
      await _persistSubmittedRecord(record);
      unawaited(_retryPendingSubmissions());
    }
    if (screenContext.mounted) Navigator.pop(screenContext);
  }

  String? _nextParticipantNumber() {
    final usedNumbers = _records
        .map(
          (record) =>
              int.tryParse(record.participant.studyId.substring(1)) ?? 0,
        )
        .toSet();
    for (var number = 1; number <= 200; number++) {
      if (!usedNumbers.contains(number)) {
        return 'P${number.toString().padLeft(3, '0')}';
      }
    }
    return null;
  }

  void _openSubmissions(List<ui.SubmissionSummary> submissions) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (screenContext) => ui.MySubmissionsScreen(
          submissions: submissions,
          onBack: () => Navigator.pop(screenContext),
          onOpen: _openSubmission,
        ),
      ),
    );
  }

  void _openSubmission(ui.SubmissionSummary summary) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (screenContext) => ui.SubmissionDetailScreen(
          submission: summary,
          onBack: () => Navigator.pop(screenContext),
          onEdit: () => ScaffoldMessenger.of(screenContext).showSnackBar(
            const SnackBar(
              content: Text(
                'Editing submitted entries is not available in this demo.',
              ),
            ),
          ),
        ),
      ),
    );
  }

  ui.SubmissionSummary _summary(_LocalRecord record) => ui.SubmissionSummary(
    id: record.id,
    participantName: record.participant.name,
    studyId: record.participant.studyId,
    visitNumber: record.visitNumber,
    submittedAt: record.submittedAt,
    syncState: record.syncState,
  );

  Future<void> _retryPendingSubmissions() async {
    if (_isRetrying) return;
    final pending = _records
        .where(
          (record) =>
              record.syncState == ui.SyncState.pending ||
              record.syncState == ui.SyncState.failed,
        )
        .toList();
    if (pending.isEmpty) return;

    if (!mounted) return;
    setState(() => _isRetrying = true);
    await Future.wait(pending.map(_syncRecord));
    await _persistRecords();
    if (mounted) setState(() => _isRetrying = false);
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
      } on CollectorSessionRequiredException {
        record.syncState = ui.SyncState.failed;
      } catch (_) {
        record.syncState = ui.SyncState.pending;
      }
      return;
    }
    final result = await _syncGateway.sendRecord(
      record.toVisitRecordJson(syncState: ui.SyncState.synced),
    );
    record.syncState = switch (result) {
      LocalRecordSyncResult.synced => ui.SyncState.synced,
      LocalRecordSyncResult.pending => ui.SyncState.pending,
      LocalRecordSyncResult.failed => ui.SyncState.failed,
    };
  }
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
  });

  final ui.ParticipantDraft participant;
  final int visitNumber;
  final String collectorCode;
  final String? visitId;
  final Future<void> Function(_LocalRecord record) onSync;
  final Future<void> Function(_LocalRecord record) onPersist;

  @override
  State<_LocalVisitFlow> createState() => _LocalVisitFlowState();
}

class _LocalVisitFlowState extends State<_LocalVisitFlow> {
  int _step = 0;
  NcdQuestionnaire? _questionnaire;
  String? _stepTwoNote;
  _LocalRecord? _record;
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) => switch (_step) {
    0 => ui.VisitConfirmationScreen(
      participant: widget.participant,
      proposedVisitNumber: widget.visitNumber,
      onBack: () => Navigator.pop(context),
      onConfirm: () => setState(() => _step = 1),
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
      participant: widget.participant,
      visitNumber: widget.visitNumber,
      questionnaire: _questionnaire,
      optionalNote: _stepTwoNote,
      onBack: () => setState(() => _step = 2),
      onSubmit: _isSubmitting ? null : _submit,
      isSubmitting: _isSubmitting,
    ),
    _ => ui.ReceiptScreen(
      submission: ui.SubmissionSummary(
        id: _record!.id,
        participantName: widget.participant.name,
        studyId: widget.participant.studyId,
        visitNumber: widget.visitNumber,
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
        builder: (screenContext) => ui.SubmissionDetailScreen(
          submission: ui.SubmissionSummary(
            id: record.id,
            participantName: record.participant.name,
            studyId: record.participant.studyId,
            visitNumber: record.visitNumber,
            submittedAt: record.submittedAt,
            syncState: record.syncState,
          ),
          onBack: () => Navigator.pop(screenContext),
          onEdit: () => ScaffoldMessenger.of(screenContext).showSnackBar(
            const SnackBar(
              content: Text(
                'Editing submitted entries is not available in this demo.',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final now = DateTime.now();
    final record = _LocalRecord(
      id: widget.visitId ?? 'LOCAL-${now.microsecondsSinceEpoch}',
      participant: widget.participant,
      visitNumber: widget.visitNumber,
      collector: widget.collectorCode,
      submittedAt: now,
      stepTwoNote: _stepTwoNote,
      questionnaire: _questionnaire,
    );
    setState(() {
      _record = record;
      _isSubmitting = true;
    });
    await widget.onSync(record);
    await widget.onPersist(record);
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _step = 4;
    });
  }
}
