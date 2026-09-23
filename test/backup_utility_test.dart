import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/backup_utility.dart';

void main() {
  late Directory tempBaseDir;
  late Directory sourceDir;
  late Directory destinationDir;
  late Directory targetDir;
  late BackupEngine engine;
  late IntegrityVerifier verifier;

  // Locate project root containing tool/backup_utility.dart
  Directory findProjectRoot() {
    var dir = Directory.current;
    while (!File(
      '${dir.path}${Platform.pathSeparator}tool${Platform.pathSeparator}backup_utility.dart',
    ).existsSync()) {
      final parent = dir.parent;
      if (parent.path == dir.path) {
        throw StateError(
          'Could not find project root containing tool/backup_utility.dart',
        );
      }
      dir = parent;
    }
    return dir;
  }

  // Locate the actual dart CLI executable (handling flutter_tester runner)
  String findDartExecutable() {
    final exec = Platform.executable.toLowerCase();
    if (!exec.contains('flutter_tester')) {
      return Platform.resolvedExecutable;
    }

    final flutterTester = File(Platform.resolvedExecutable);
    var dir = flutterTester.parent;
    for (int i = 0; i < 8; i++) {
      final dartExe = File(
        '${dir.path}${Platform.pathSeparator}bin${Platform.pathSeparator}cache${Platform.pathSeparator}dart-sdk${Platform.pathSeparator}bin${Platform.pathSeparator}dart${Platform.isWindows ? '.exe' : ''}',
      );
      if (dartExe.existsSync()) {
        return dartExe.path;
      }
      final dartBin = File(
        '${dir.path}${Platform.pathSeparator}bin${Platform.pathSeparator}dart${Platform.isWindows ? '.bat' : ''}',
      );
      if (dartBin.existsSync()) {
        return dartBin.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }

    final candidates = [
      'C:\\Users\\LENOVO\\flutter\\bin\\cache\\dart-sdk\\bin\\dart.exe',
      'C:\\Users\\LENOVO\\flutter\\bin\\dart.bat',
      if (Platform.isWindows) 'dart.bat' else 'dart',
    ];
    for (final cand in candidates) {
      if (File(cand).existsSync()) {
        return cand;
      }
    }
    return Platform.isWindows ? 'dart.bat' : 'dart';
  }

  final projectRoot = findProjectRoot();
  final dartExecutable = findDartExecutable();

  // Synthetic data generators
  Map<String, dynamic> makeSyntheticRecord({
    required String id,
    String studyId = 'C01-100001',
    String name = 'Synthetic Participant Alpha',
    String phone = '+919876543210',
    int visitNumber = 1,
    String collectorId = 'collector-01',
    String status = 'submitted',
    String syncState = 'synced',
    String reviewState = 'pending',
    int revision = 1,
    String? idempotencyKey,
  }) {
    return {
      'id': id,
      'participant': {
        'studyId': studyId,
        'name': name,
        'indianPhone': phone,
      },
      'visitNumber': visitNumber,
      'collectorId': collectorId,
      'createdAt': '2026-09-23T08:00:00.000Z',
      'updatedAt': '2026-09-23T08:00:00.000Z',
      'status': status,
      'syncState': syncState,
      'reviewState': reviewState,
      'revision': revision,
      'idempotencyKey': idempotencyKey ?? 'idem_$id',
    };
  }

  Map<String, dynamic> makeSyntheticConflict({
    required String id,
    String conflictType = 'duplicate_visit',
    String message = 'Visit number is already recorded for this participant.',
    String collectorId = 'collector-01',
    String status = 'pending',
    Map<String, dynamic>? rejectedRecord,
  }) {
    return {
      'id': id,
      'conflictType': conflictType,
      'message': message,
      'createdAt': '2026-09-23T08:30:00.000Z',
      'collectorId': collectorId,
      'status': status,
      'rejectedRecord': rejectedRecord ??
          makeSyntheticRecord(
            id: 'rec_conflict_rej',
            status: 'draft',
            syncState: 'pending',
          ),
    };
  }

  Future<void> populateSourceDir({
    required Directory dir,
    List<Map<String, dynamic>>? records,
    List<Map<String, dynamic>>? conflicts,
    bool writeConflicts = true,
  }) async {
    await dir.create(recursive: true);
    final recList = records ??
        [
          makeSyntheticRecord(id: 'rec_001', studyId: 'C01-100001'),
          makeSyntheticRecord(id: 'rec_002', studyId: 'C01-100002'),
        ];
    final recordsFile = File('${dir.path}${Platform.pathSeparator}$recordsFileName');
    await recordsFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(recList)}\n',
      flush: true,
    );

    if (writeConflicts) {
      final confList = conflicts ??
          [
            makeSyntheticConflict(id: 'conf_001'),
          ];
      final conflictsFile = File(
        '${dir.path}${Platform.pathSeparator}$conflictsFileName',
      );
      await conflictsFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(confList)}\n',
        flush: true,
      );
    }
  }

  setUp(() async {
    tempBaseDir = await Directory.systemTemp.createTemp('backup_util_test_');
    sourceDir = Directory('${tempBaseDir.path}${Platform.pathSeparator}source');
    destinationDir = Directory(
      '${tempBaseDir.path}${Platform.pathSeparator}destination',
    );
    targetDir = Directory('${tempBaseDir.path}${Platform.pathSeparator}target');

    await sourceDir.create(recursive: true);
    await destinationDir.create(recursive: true);

    verifier = const IntegrityVerifier();
    engine = BackupEngine(verifier: verifier);
  });

  tearDown(() async {
    if (await tempBaseDir.exists()) {
      try {
        await tempBaseDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  // ==========================================================================
  // Group 1: Backup Creation
  // ==========================================================================
  group('Backup Creation', () {
    test(
      'generates timestamped folder with records, conflicts, manifest, and SHA256SUMS',
      () async {
        await populateSourceDir(dir: sourceDir);

        final result = await engine.backup(
          destination: destinationDir,
          source: sourceDir,
        );

        final backupDir = result.backupDirectory;
        expect(await backupDir.exists(), isTrue);
        expect(
          RegExp(r'^backup_\d{8}_\d{6}$').hasMatch(
            backupDir.uri.pathSegments.where((s) => s.isNotEmpty).last,
          ),
          isTrue,
        );

        // Required backup files
        final recordsFile = File(
          '${backupDir.path}${Platform.pathSeparator}$recordsFileName',
        );
        final conflictsFile = File(
          '${backupDir.path}${Platform.pathSeparator}$conflictsFileName',
        );
        final manifestFile = File(
          '${backupDir.path}${Platform.pathSeparator}$manifestFileName',
        );
        final sumsFile = File(
          '${backupDir.path}${Platform.pathSeparator}$sha256SumsFileName',
        );

        expect(await recordsFile.exists(), isTrue);
        expect(await conflictsFile.exists(), isTrue);
        expect(await manifestFile.exists(), isTrue);
        expect(await sumsFile.exists(), isTrue);

        // Verify SHA256SUMS file format (<sha256>  <filename>)
        final sumsContent = await sumsFile.readAsString();
        expect(sumsContent, contains(recordsFileName));
        expect(sumsContent, contains(conflictsFileName));
        expect(sumsContent, contains(manifestFileName));

        for (final line in sumsContent.trim().split(RegExp(r'\r?\n'))) {
          final parts = line.split(RegExp(r'\s+'));
          expect(parts.length, equals(2));
          expect(parts[0].length, equals(64)); // SHA-256 hex string length
        }
      },
    );

    test(
      'manifest contains correct record counts, file sizes, and SHA-256 hashes',
      () async {
        final records = [
          makeSyntheticRecord(id: 'r1', studyId: 'C01-100001'),
          makeSyntheticRecord(id: 'r2', studyId: 'C01-100002'),
          makeSyntheticRecord(id: 'r3', studyId: 'C01-100003'),
        ];
        final conflicts = [
          makeSyntheticConflict(id: 'c1'),
          makeSyntheticConflict(id: 'c2'),
        ];

        await populateSourceDir(
          dir: sourceDir,
          records: records,
          conflicts: conflicts,
        );

        final result = await engine.backup(
          destination: destinationDir,
          source: sourceDir,
        );

        final manifest = result.manifest;
        expect(manifest.version, equals(1));
        expect(manifest.source, equals(sourceDir.path));
        expect(DateTime.tryParse(manifest.createdAt), isNotNull);

        // Check records entry in manifest
        final recEntry = manifest.files[recordsFileName]!;
        expect(recEntry.recordCount, equals(3));
        final actualRecFile = File(
          '${result.backupDirectory.path}${Platform.pathSeparator}$recordsFileName',
        );
        expect(recEntry.sizeBytes, equals(await actualRecFile.length()));
        expect(
          recEntry.sha256,
          equals(Sha256.hashBytes(await actualRecFile.readAsBytes())),
        );

        // Check conflicts entry in manifest
        final confEntry = manifest.files[conflictsFileName]!;
        expect(confEntry.recordCount, equals(2));
        final actualConfFile = File(
          '${result.backupDirectory.path}${Platform.pathSeparator}$conflictsFileName',
        );
        expect(confEntry.sizeBytes, equals(await actualConfFile.length()));
        expect(
          confEntry.sha256,
          equals(Sha256.hashBytes(await actualConfFile.readAsBytes())),
        );
      },
    );

    test(
      'missing conflicts.json in source is handled gracefully with empty conflicts list',
      () async {
        await populateSourceDir(dir: sourceDir, writeConflicts: false);
        final srcConfFile = File(
          '${sourceDir.path}${Platform.pathSeparator}$conflictsFileName',
        );
        expect(await srcConfFile.exists(), isFalse);

        final result = await engine.backup(
          destination: destinationDir,
          source: sourceDir,
        );

        final destConfFile = File(
          '${result.backupDirectory.path}${Platform.pathSeparator}$conflictsFileName',
        );
        expect(await destConfFile.exists(), isTrue);

        final decoded = jsonDecode(await destConfFile.readAsString());
        expect(decoded, isA<List>());
        expect((decoded as List).isEmpty, isTrue);

        final confEntry = result.manifest.files[conflictsFileName]!;
        expect(confEntry.recordCount, equals(0));
        expect(confEntry.sizeBytes, equals(await destConfFile.length()));
        expect(
          confEntry.sha256,
          equals(Sha256.hashBytes(await destConfFile.readAsBytes())),
        );

        // Verification must pass on the backup with empty conflicts
        final verification = await verifier.verifyBackup(
          result.backupDirectory,
        );
        expect(verification.passed, isTrue);
      },
    );

    test(
      'rejects missing source directory with BackupValidationException',
      () async {
        final missingSource = Directory(
          '${tempBaseDir.path}${Platform.pathSeparator}non_existent_source',
        );
        expect(
          () => engine.backup(
            destination: destinationDir,
            source: missingSource,
          ),
          throwsA(isA<BackupValidationException>()),
        );
      },
    );

    test(
      'rejects missing records.json in source directory with BackupValidationException',
      () async {
        // source directory exists but records.json is not present
        await sourceDir.create(recursive: true);
        final recFile = File(
          '${sourceDir.path}${Platform.pathSeparator}$recordsFileName',
        );
        expect(await recFile.exists(), isFalse);

        expect(
          () => engine.backup(
            destination: destinationDir,
            source: sourceDir,
          ),
          throwsA(
            isA<BackupValidationException>().having(
              (e) => e.message,
              'message',
              contains(recordsFileName),
            ),
          ),
        );
      },
    );

    test(
      'rejects unparseable/corrupted JSON in source records.json',
      () async {
        await sourceDir.create(recursive: true);
        final recFile = File(
          '${sourceDir.path}${Platform.pathSeparator}$recordsFileName',
        );
        await recFile.writeAsString('[{ "id": "rec_01", broken json content');

        expect(
          () => engine.backup(
            destination: destinationDir,
            source: sourceDir,
          ),
          throwsA(isA<BackupValidationException>()),
        );
      },
    );

    test(
      'rejects non-list JSON in source records.json',
      () async {
        await sourceDir.create(recursive: true);
        final recFile = File(
          '${sourceDir.path}${Platform.pathSeparator}$recordsFileName',
        );
        await recFile.writeAsString('{"error": "not a list"}');

        expect(
          () => engine.backup(
            destination: destinationDir,
            source: sourceDir,
          ),
          throwsA(isA<BackupValidationException>()),
        );
      },
    );

    test(
      'rejects unparseable JSON in source conflicts.json',
      () async {
        await populateSourceDir(dir: sourceDir, writeConflicts: false);
        final confFile = File(
          '${sourceDir.path}${Platform.pathSeparator}$conflictsFileName',
        );
        await confFile.writeAsString('Corrupt conflicts content');

        expect(
          () => engine.backup(
            destination: destinationDir,
            source: sourceDir,
          ),
          throwsA(isA<BackupValidationException>()),
        );
      },
    );

    test(
      'never overwrites existing backup folder if the same timestamp is hit',
      () async {
        await populateSourceDir(dir: sourceDir);

        // Pre-create a colliding backup directory with a distinct canary file
        final timestamp = BackupEngine.formatTimestamp(DateTime.now().toUtc());
        final collidingDir = Directory(
          '${destinationDir.path}${Platform.pathSeparator}backup_$timestamp',
        );
        await collidingDir.create(recursive: true);
        final canaryFile = File(
          '${collidingDir.path}${Platform.pathSeparator}pre_existing_canary.txt',
        );
        await canaryFile.writeAsString('MUST_NOT_BE_OVERWRITTEN');

        final result = await engine.backup(
          destination: destinationDir,
          source: sourceDir,
        );

        // Colliding directory must be preserved untouched
        expect(await collidingDir.exists(), isTrue);
        expect(await canaryFile.exists(), isTrue);
        expect(await canaryFile.readAsString(), equals('MUST_NOT_BE_OVERWRITTEN'));

        // New backup must have an appended suffix like _1
        expect(result.backupDirectory.path, isNot(equals(collidingDir.path)));
        expect(await result.backupDirectory.exists(), isTrue);
        expect(
          result.backupDirectory.path,
          contains('${collidingDir.path}_'),
        );
      },
    );

    test(
      'appends sanitized label to folder name when label is provided',
      () async {
        await populateSourceDir(dir: sourceDir);

        final result = await engine.backup(
          destination: destinationDir,
          source: sourceDir,
          label: 'weekly-archive-site01',
        );

        final folderName =
            result.backupDirectory.uri.pathSegments.where((s) => s.isNotEmpty).last;
        expect(folderName, contains('weekly-archive-site01'));
      },
    );
  });

  // ==========================================================================
  // Group 2: Integrity Verification
  // ==========================================================================
  group('Integrity Verification', () {
    test('verifies valid backup passes', () async {
      await populateSourceDir(dir: sourceDir);
      final backup = await engine.backup(
        destination: destinationDir,
        source: sourceDir,
      );

      final result = await verifier.verifyBackup(backup.backupDirectory);
      expect(result.passed, isTrue);
      expect(result.errors, isEmpty);
      expect(result.manifest, isNotNull);
      expect(result.sha256SumsMatched, isTrue);
      expect(result.fileResults[recordsFileName]!.passed, isTrue);
      expect(result.fileResults[conflictsFileName]!.passed, isTrue);
    });

    test(
      'detects tampered content (modifying a single character in records.json fails with hash mismatch)',
      () async {
        await populateSourceDir(dir: sourceDir);
        final backup = await engine.backup(
          destination: destinationDir,
          source: sourceDir,
        );

        final recordsFile = File(
          '${backup.backupDirectory.path}${Platform.pathSeparator}$recordsFileName',
        );
        final bytes = await recordsFile.readAsBytes();

        // Mutate a single byte in records.json payload
        bytes[bytes.length ~/ 2] ^= 0x01;
        await recordsFile.writeAsBytes(bytes, flush: true);

        final result = await verifier.verifyBackup(backup.backupDirectory);
        expect(result.passed, isFalse);
        expect(result.errors.isNotEmpty, isTrue);
        expect(
          result.errors.any(
            (e) => e.contains('hash mismatch') || e.contains('SHA-256'),
          ),
          isTrue,
        );
        expect(result.fileResults[recordsFileName]!.passed, isFalse);
      },
    );

    test('detects tampered content in conflicts.json', () async {
      await populateSourceDir(dir: sourceDir);
      final backup = await engine.backup(
        destination: destinationDir,
        source: sourceDir,
      );

      final conflictsFile = File(
        '${backup.backupDirectory.path}${Platform.pathSeparator}$conflictsFileName',
      );
      final bytes = await conflictsFile.readAsBytes();

      // Mutate a byte in conflicts.json
      bytes[bytes.length ~/ 2] ^= 0x01;
      await conflictsFile.writeAsBytes(bytes, flush: true);

      final result = await verifier.verifyBackup(backup.backupDirectory);
      expect(result.passed, isFalse);
      expect(
        result.errors.any((e) => e.contains('conflicts.json')),
        isTrue,
      );
      expect(result.fileResults[conflictsFileName]!.passed, isFalse);
    });

    test('detects missing manifest.json', () async {
      await populateSourceDir(dir: sourceDir);
      final backup = await engine.backup(
        destination: destinationDir,
        source: sourceDir,
      );

      final manifestFile = File(
        '${backup.backupDirectory.path}${Platform.pathSeparator}$manifestFileName',
      );
      await manifestFile.delete();

      final result = await verifier.verifyBackup(backup.backupDirectory);
      expect(result.passed, isFalse);
      expect(
        result.errors.any((e) => e.contains('Missing manifest file')),
        isTrue,
      );
    });

    test('detects missing records.json file in backup directory', () async {
      await populateSourceDir(dir: sourceDir);
      final backup = await engine.backup(
        destination: destinationDir,
        source: sourceDir,
      );

      final recordsFile = File(
        '${backup.backupDirectory.path}${Platform.pathSeparator}$recordsFileName',
      );
      await recordsFile.delete();

      final result = await verifier.verifyBackup(backup.backupDirectory);
      expect(result.passed, isFalse);
      expect(result.fileResults[recordsFileName]!.passed, isFalse);
      expect(
        result.fileResults[recordsFileName]!.errors.any(
          (e) => e.contains('File not found: records.json'),
        ),
        isTrue,
      );
    });

    test('detects missing conflicts.json file in backup directory', () async {
      await populateSourceDir(dir: sourceDir);
      final backup = await engine.backup(
        destination: destinationDir,
        source: sourceDir,
      );

      final conflictsFile = File(
        '${backup.backupDirectory.path}${Platform.pathSeparator}$conflictsFileName',
      );
      await conflictsFile.delete();

      final result = await verifier.verifyBackup(backup.backupDirectory);
      expect(result.passed, isFalse);
      expect(result.fileResults[conflictsFileName]!.passed, isFalse);
      expect(
        result.fileResults[conflictsFileName]!.errors.any(
          (e) => e.contains('File not found: conflicts.json'),
        ),
        isTrue,
      );
    });

    test('detects size mismatch when extra bytes are appended', () async {
      await populateSourceDir(dir: sourceDir);
      final backup = await engine.backup(
        destination: destinationDir,
        source: sourceDir,
      );

      final recordsFile = File(
        '${backup.backupDirectory.path}${Platform.pathSeparator}$recordsFileName',
      );
      // Append whitespace / newlines
      await recordsFile.writeAsString('\n\n\n', mode: FileMode.append);

      final result = await verifier.verifyBackup(backup.backupDirectory);
      expect(result.passed, isFalse);
      expect(
        result.errors.any((e) => e.contains('Size mismatch')),
        isTrue,
      );
    });

    test('detects tampered SHA256SUMS file', () async {
      await populateSourceDir(dir: sourceDir);
      final backup = await engine.backup(
        destination: destinationDir,
        source: sourceDir,
      );

      final sumsFile = File(
        '${backup.backupDirectory.path}${Platform.pathSeparator}$sha256SumsFileName',
      );
      // Replace hash in SHA256SUMS with forged string
      await sumsFile.writeAsString(
        '0000000000000000000000000000000000000000000000000000000000000000  records.json\n',
      );

      final result = await verifier.verifyBackup(backup.backupDirectory);
      expect(result.passed, isFalse);
      expect(result.sha256SumsMatched, isFalse);
      expect(
        result.errors.any((e) => e.contains(sha256SumsFileName)),
        isTrue,
      );
    });

    test('detects record item missing required string id', () async {
      await populateSourceDir(dir: sourceDir);
      final backup = await engine.backup(
        destination: destinationDir,
        source: sourceDir,
      );

      final recordsFile = File(
        '${backup.backupDirectory.path}${Platform.pathSeparator}$recordsFileName',
      );
      // Write list containing item with missing id
      final invalidList = [
        {'noId': 'missing_id_field'},
      ];
      await recordsFile.writeAsString(jsonEncode(invalidList));

      final result = await verifier.verifyBackup(backup.backupDirectory);
      expect(result.passed, isFalse);
      expect(
        result.errors.any((e) => e.contains('missing required string id')),
        isTrue,
      );
    });
  });

  // ==========================================================================
  // Group 3: Safe Restore
  // ==========================================================================
  group('Safe Restore', () {
    test(
      'rejects restore from tampered backup and aborts before touching target',
      () async {
        await populateSourceDir(dir: sourceDir);
        final backup = await engine.backup(
          destination: destinationDir,
          source: sourceDir,
        );

        // Pre-populate target with canary data
        await targetDir.create(recursive: true);
        final targetRecords = File(
          '${targetDir.path}${Platform.pathSeparator}$recordsFileName',
        );
        await targetRecords.writeAsString('CANARY_DATA_DO_NOT_TOUCH');

        // Tamper backup
        final backupRecords = File(
          '${backup.backupDirectory.path}${Platform.pathSeparator}$recordsFileName',
        );
        final bytes = await backupRecords.readAsBytes();
        bytes[bytes.length ~/ 2] ^= 0x01;
        await backupRecords.writeAsBytes(bytes, flush: true);

        // Restore must throw BackupIntegrityException
        expect(
          () => engine.restore(
            backupDir: backup.backupDirectory,
            target: targetDir,
            confirmOverwrite: true,
          ),
          throwsA(isA<BackupIntegrityException>()),
        );

        // Target canary data must be completely preserved
        expect(await targetRecords.readAsString(), equals('CANARY_DATA_DO_NOT_TOUCH'));
      },
    );

    test(
      'refuses to overwrite existing live target data without --confirm-overwrite',
      () async {
        await populateSourceDir(dir: sourceDir);
        final backup = await engine.backup(
          destination: destinationDir,
          source: sourceDir,
        );

        // Target already has existing live records
        await targetDir.create(recursive: true);
        final targetRecords = File(
          '${targetDir.path}${Platform.pathSeparator}$recordsFileName',
        );
        await targetRecords.writeAsString(
          jsonEncode([{'id': 'live_rec_prior'}]),
        );

        expect(
          () => engine.restore(
            backupDir: backup.backupDirectory,
            target: targetDir,
            confirmOverwrite: false,
          ),
          throwsA(
            isA<BackupOverwriteException>().having(
              (e) => e.message,
              'message',
              contains('--confirm-overwrite'),
            ),
          ),
        );

        // Live records in target must not have changed
        final content = await targetRecords.readAsString();
        expect(content, contains('live_rec_prior'));
      },
    );

    test(
      'when --confirm-overwrite is passed, creates pre-restore safety snapshot before replacing',
      () async {
        await populateSourceDir(dir: sourceDir);
        final backup = await engine.backup(
          destination: destinationDir,
          source: sourceDir,
        );

        // Live target records and conflicts to be replaced
        await targetDir.create(recursive: true);
        final targetRecords = File(
          '${targetDir.path}${Platform.pathSeparator}$recordsFileName',
        );
        final targetConflicts = File(
          '${targetDir.path}${Platform.pathSeparator}$conflictsFileName',
        );
        await targetRecords.writeAsString(
          jsonEncode([{'id': 'live_canary_rec_123'}]),
        );
        await targetConflicts.writeAsString(
          jsonEncode([{'id': 'live_canary_conf_456'}]),
        );

        final result = await engine.restore(
          backupDir: backup.backupDirectory,
          target: targetDir,
          confirmOverwrite: true,
        );

        expect(result.safetySnapshotDirectory, isNotNull);
        final snapshotDir = result.safetySnapshotDirectory!;
        expect(await snapshotDir.exists(), isTrue);
        expect(snapshotDir.path, contains(safetyBackupPrefix));

        // Snapshot directory contains archived live files
        final archivedRecords = File(
          '${snapshotDir.path}${Platform.pathSeparator}$recordsFileName',
        );
        final archivedConflicts = File(
          '${snapshotDir.path}${Platform.pathSeparator}$conflictsFileName',
        );
        final safetyManifest = File(
          '${snapshotDir.path}${Platform.pathSeparator}safety_manifest.json',
        );
        final safetySums = File(
          '${snapshotDir.path}${Platform.pathSeparator}$sha256SumsFileName',
        );

        expect(await archivedRecords.exists(), isTrue);
        expect(await archivedConflicts.exists(), isTrue);
        expect(await safetyManifest.exists(), isTrue);
        expect(await safetySums.exists(), isTrue);

        expect(
          await archivedRecords.readAsString(),
          contains('live_canary_rec_123'),
        );
        expect(
          await archivedConflicts.readAsString(),
          contains('live_canary_conf_456'),
        );

        // Live target directory is now replaced with restored backup data
        final restoredRecordsContent = await targetRecords.readAsString();
        expect(restoredRecordsContent, contains('rec_001'));
        expect(restoredRecordsContent, isNot(contains('live_canary_rec_123')));
      },
    );

    test('restores to an empty or non-existent target cleanly', () async {
      await populateSourceDir(dir: sourceDir);
      final backup = await engine.backup(
        destination: destinationDir,
        source: sourceDir,
      );

      final freshTarget = Directory(
        '${tempBaseDir.path}${Platform.pathSeparator}brand_new_target',
      );
      expect(await freshTarget.exists(), isFalse);

      final result = await engine.restore(
        backupDir: backup.backupDirectory,
        target: freshTarget,
      );

      expect(await freshTarget.exists(), isTrue);
      expect(result.safetySnapshotDirectory, isNull);
      expect(result.restoredRecordCount, equals(2));
      expect(result.restoredConflictCount, equals(1));

      final restoredRecords = File(
        '${freshTarget.path}${Platform.pathSeparator}$recordsFileName',
      );
      final restoredConflicts = File(
        '${freshTarget.path}${Platform.pathSeparator}$conflictsFileName',
      );
      expect(await restoredRecords.exists(), isTrue);
      expect(await restoredConflicts.exists(), isTrue);
    });

    test('restored content is identical to the original source', () async {
      final origRecords = [
        makeSyntheticRecord(
          id: 'rec_exact_1',
          studyId: 'C01-100010',
          name: 'Original Participant 1',
        ),
        makeSyntheticRecord(
          id: 'rec_exact_2',
          studyId: 'C01-100020',
          name: 'Original Participant 2',
        ),
      ];
      final origConflicts = [
        makeSyntheticConflict(id: 'conf_exact_1'),
      ];

      await populateSourceDir(
        dir: sourceDir,
        records: origRecords,
        conflicts: origConflicts,
      );

      final backup = await engine.backup(
        destination: destinationDir,
        source: sourceDir,
      );

      await engine.restore(
        backupDir: backup.backupDirectory,
        target: targetDir,
      );

      final restoredRecList = jsonDecode(
        await File('${targetDir.path}${Platform.pathSeparator}$recordsFileName')
            .readAsString(),
      );
      final restoredConfList = jsonDecode(
        await File('${targetDir.path}${Platform.pathSeparator}$conflictsFileName')
            .readAsString(),
      );

      expect(restoredRecList, equals(origRecords));
      expect(restoredConfList, equals(origConflicts));
    });
  });

  // ==========================================================================
  // Group 4: CLI Execution via Process.run
  // ==========================================================================
  group('CLI execution via Process.run', () {
    test(
      'dart run tool/backup_utility.dart test runs synthetic suite to success',
      () async {
        final proc = await Process.run(
          dartExecutable,
          ['run', 'tool/backup_utility.dart', 'test'],
          workingDirectory: projectRoot.path,
        );

        expect(
          proc.exitCode,
          equals(0),
          reason: 'STDOUT:\n${proc.stdout}\nSTDERR:\n${proc.stderr}',
        );
        expect(
          proc.stdout.toString(),
          contains('ALL 7/7 SYNTHETIC VERIFICATION TESTS PASSED SUCCESSFULLY'),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'dart run tool/backup_utility.dart backup creates verified backup',
      () async {
        await populateSourceDir(dir: sourceDir);

        final proc = await Process.run(
          dartExecutable,
          [
            'run',
            'tool/backup_utility.dart',
            'backup',
            '--destination=${destinationDir.path}',
            '--source=${sourceDir.path}',
            '--label=cli-test',
          ],
          workingDirectory: projectRoot.path,
        );

        expect(
          proc.exitCode,
          equals(0),
          reason: 'STDOUT:\n${proc.stdout}\nSTDERR:\n${proc.stderr}',
        );
        expect(
          proc.stdout.toString(),
          contains('BACKUP COMPLETED SUCCESSFULLY'),
        );

        // Verify backup exists on disk
        final backups = destinationDir
            .listSync()
            .whereType<Directory>()
            .where((d) => d.path.contains('cli-test'))
            .toList();
        expect(backups.length, equals(1));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'dart run tool/backup_utility.dart verify validates backup integrity',
      () async {
        await populateSourceDir(dir: sourceDir);
        final backup = await engine.backup(
          destination: destinationDir,
          source: sourceDir,
        );

        // 1. Verify valid backup
        final verifyProc = await Process.run(
          dartExecutable,
          [
            'run',
            'tool/backup_utility.dart',
            'verify',
            '--backup=${backup.backupDirectory.path}',
          ],
          workingDirectory: projectRoot.path,
        );

        expect(
          verifyProc.exitCode,
          equals(0),
          reason: 'STDOUT:\n${verifyProc.stdout}\nSTDERR:\n${verifyProc.stderr}',
        );
        expect(verifyProc.stdout.toString(), contains('VERIFY RESULT: PASS'));

        // 2. Tamper 1 byte and verify it fails with exit code 1
        final recFile = File(
          '${backup.backupDirectory.path}${Platform.pathSeparator}$recordsFileName',
        );
        final bytes = await recFile.readAsBytes();
        bytes[bytes.length ~/ 2] ^= 0x01;
        await recFile.writeAsBytes(bytes, flush: true);

        final failProc = await Process.run(
          dartExecutable,
          [
            'run',
            'tool/backup_utility.dart',
            'verify',
            '--backup=${backup.backupDirectory.path}',
          ],
          workingDirectory: projectRoot.path,
        );

        expect(failProc.exitCode, equals(1));
        expect(failProc.stderr.toString(), contains('VERIFY RESULT: FAIL'));
        expect(
          failProc.stderr.toString(),
          contains('hash mismatch'),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'dart run tool/backup_utility.dart restore safeguards live data and restores cleanly',
      () async {
        await populateSourceDir(dir: sourceDir);
        final backup = await engine.backup(
          destination: destinationDir,
          source: sourceDir,
        );

        // Pre-create target with live data
        await targetDir.create(recursive: true);
        final targetRec = File(
          '${targetDir.path}${Platform.pathSeparator}$recordsFileName',
        );
        await targetRec.writeAsString(jsonEncode([{'id': 'live_rec_prior'}]));

        // 1. Attempt restore without --confirm-overwrite -> should fail exit code 1
        final blockedProc = await Process.run(
          dartExecutable,
          [
            'run',
            'tool/backup_utility.dart',
            'restore',
            '--backup=${backup.backupDirectory.path}',
            '--target=${targetDir.path}',
          ],
          workingDirectory: projectRoot.path,
        );

        expect(blockedProc.exitCode, equals(1));
        expect(
          blockedProc.stderr.toString(),
          contains('Restore was blocked to prevent data loss'),
        );
        expect(await targetRec.readAsString(), contains('live_rec_prior'));

        // 2. Restore with --confirm-overwrite -> should succeed exit code 0
        final okProc = await Process.run(
          dartExecutable,
          [
            'run',
            'tool/backup_utility.dart',
            'restore',
            '--backup=${backup.backupDirectory.path}',
            '--target=${targetDir.path}',
            '--confirm-overwrite',
          ],
          workingDirectory: projectRoot.path,
        );

        expect(
          okProc.exitCode,
          equals(0),
          reason: 'STDOUT:\n${okProc.stdout}\nSTDERR:\n${okProc.stderr}',
        );
        expect(
          okProc.stdout.toString(),
          contains('RESTORE COMPLETED SUCCESSFULLY'),
        );
        expect(
          okProc.stdout.toString(),
          contains('Pre-Restore Snapshot:'),
        );

        // Live file was replaced with restored backup data
        final restoredContent = await targetRec.readAsString();
        expect(restoredContent, contains('rec_001'));
        expect(restoredContent, isNot(contains('live_rec_prior')));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'CLI handles usage errors and prints help correctly',
      () async {
        // help subcommand -> exit 0 with usage
        final helpSubcmd = await Process.run(
          dartExecutable,
          ['run', 'tool/backup_utility.dart', 'help'],
          workingDirectory: projectRoot.path,
        );
        expect(helpSubcmd.exitCode, equals(0));
        expect(helpSubcmd.stdout.toString(), contains('Available Subcommands:'));

        // --help -> exit 0 with usage
        final helpProc = await Process.run(
          dartExecutable,
          ['run', 'tool/backup_utility.dart', '--help'],
          workingDirectory: projectRoot.path,
        );
        expect(helpProc.exitCode, equals(0));
        expect(helpProc.stdout.toString(), contains('Available Subcommands:'));

        // Unknown subcommand -> exit 64
        final unknownProc = await Process.run(
          dartExecutable,
          ['run', 'tool/backup_utility.dart', 'bogus-command'],
          workingDirectory: projectRoot.path,
        );
        expect(unknownProc.exitCode, equals(64));
        expect(unknownProc.stderr.toString(), contains('Unknown subcommand'));

        // backup without --destination -> exit 64
        final missingDest = await Process.run(
          dartExecutable,
          ['run', 'tool/backup_utility.dart', 'backup'],
          workingDirectory: projectRoot.path,
        );
        expect(missingDest.exitCode, equals(64));
        expect(
          missingDest.stderr.toString(),
          contains('Missing required argument: --destination'),
        );

        // verify without --backup -> exit 64
        final missingBackup = await Process.run(
          dartExecutable,
          ['run', 'tool/backup_utility.dart', 'verify'],
          workingDirectory: projectRoot.path,
        );
        expect(missingBackup.exitCode, equals(64));
        expect(
          missingBackup.stderr.toString(),
          contains('Missing required argument: --backup'),
        );

        // restore without --backup -> exit 64
        final missingRestoreBackup = await Process.run(
          dartExecutable,
          ['run', 'tool/backup_utility.dart', 'restore'],
          workingDirectory: projectRoot.path,
        );
        expect(missingRestoreBackup.exitCode, equals(64));
        expect(
          missingRestoreBackup.stderr.toString(),
          contains('Missing required argument: --backup'),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
