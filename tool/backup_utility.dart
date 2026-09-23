/// Production backup, verification, and restore utility for local sync records.
///
/// Designed with zero external dependencies (pure Dart stdlib), cross-platform
/// atomic filesystem operations, FIPS 180-4 SHA-256 cryptographic verification,
/// tamper detection, and pre-restore safety snapshot mechanisms.
///
/// Run from the project root:
///   `dart run tool/backup_utility.dart <subcommand> [options]`
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// ============================================================================
// Constants
// ============================================================================

const String recordsFileName = 'records.json';
const String conflictsFileName = 'conflicts.json';
const String manifestFileName = 'manifest.json';
const String sha256SumsFileName = 'SHA256SUMS';
const String safetyBackupPrefix = 'pre_restore_safety_backup_';
const String restoreMarkerFileName = 'restore_in_progress.json';

// ============================================================================
// Exceptions
// ============================================================================

/// Base exception for backup utility operations.
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);

  @override
  String toString() => message;
}

/// Thrown when source files, arguments, or structures fail validation.
class BackupValidationException extends BackupException {
  const BackupValidationException(super.message);
}

/// Thrown when hash integrity or manifest verification fails.
class BackupIntegrityException extends BackupException {
  const BackupIntegrityException(super.message);
}

/// Thrown when live data exists and overwrite confirmation was not provided.
class BackupOverwriteException extends BackupException {
  const BackupOverwriteException(super.message);
}

// ============================================================================
// Cryptography: Pure Dart SHA-256 (FIPS 180-4)
// ============================================================================

/// Self-contained FIPS 180-4 compliant SHA-256 implementation with streaming support.
class Sha256 {
  static const List<int> _k = [
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  static int _rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xFFFFFFFF;

  final Uint32List _h = Uint32List(8);
  final Uint8List _buffer = Uint8List(64);
  int _bufferLen = 0;
  int _totalBytes = 0;
  final Uint32List _w = Uint32List(64);

  Sha256() {
    reset();
  }

  void reset() {
    _h[0] = 0x6a09e667;
    _h[1] = 0xbb67ae85;
    _h[2] = 0x3c6ef372;
    _h[3] = 0xa54ff53a;
    _h[4] = 0x510e527f;
    _h[5] = 0x9b05688c;
    _h[6] = 0x1f83d9ab;
    _h[7] = 0x5be0cd19;
    _bufferLen = 0;
    _totalBytes = 0;
  }

  void update(List<int> data) {
    int offset = 0;
    int remaining = data.length;
    _totalBytes += remaining;

    if (_bufferLen > 0) {
      final toCopy = (64 - _bufferLen < remaining)
          ? 64 - _bufferLen
          : remaining;
      _buffer.setRange(_bufferLen, _bufferLen + toCopy, data, offset);
      _bufferLen += toCopy;
      offset += toCopy;
      remaining -= toCopy;
      if (_bufferLen == 64) {
        _processBlock(_buffer, 0);
        _bufferLen = 0;
      }
    }

    while (remaining >= 64) {
      if (data is Uint8List) {
        _processBlock(data, offset);
      } else {
        _buffer.setRange(0, 64, data, offset);
        _processBlock(_buffer, 0);
      }
      offset += 64;
      remaining -= 64;
    }

    if (remaining > 0) {
      _buffer.setRange(0, remaining, data, offset);
      _bufferLen = remaining;
    }
  }

  void _processBlock(List<int> block, int start) {
    final bd = ByteData.sublistView(
      block is Uint8List ? block : Uint8List.fromList(block),
      start,
      start + 64,
    );
    for (int i = 0; i < 16; i++) {
      _w[i] = bd.getUint32(i * 4, Endian.big);
    }
    for (int i = 16; i < 64; i++) {
      final s0 =
          _rotr(_w[i - 15], 7) ^ _rotr(_w[i - 15], 18) ^ (_w[i - 15] >>> 3);
      final s1 =
          _rotr(_w[i - 2], 17) ^ _rotr(_w[i - 2], 19) ^ (_w[i - 2] >>> 10);
      _w[i] = (_w[i - 16] + s0 + _w[i - 7] + s1) & 0xFFFFFFFF;
    }

    int a = _h[0];
    int b = _h[1];
    int c = _h[2];
    int d = _h[3];
    int e = _h[4];
    int f = _h[5];
    int g = _h[6];
    int h = _h[7];

    for (int i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e) & g);
      final temp1 = (h + s1 + ch + _k[i] + _w[i]) & 0xFFFFFFFF;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & 0xFFFFFFFF;

      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xFFFFFFFF;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xFFFFFFFF;
    }

    _h[0] = (_h[0] + a) & 0xFFFFFFFF;
    _h[1] = (_h[1] + b) & 0xFFFFFFFF;
    _h[2] = (_h[2] + c) & 0xFFFFFFFF;
    _h[3] = (_h[3] + d) & 0xFFFFFFFF;
    _h[4] = (_h[4] + e) & 0xFFFFFFFF;
    _h[5] = (_h[5] + f) & 0xFFFFFFFF;
    _h[6] = (_h[6] + g) & 0xFFFFFFFF;
    _h[7] = (_h[7] + h) & 0xFFFFFFFF;
  }

  String digestHex() {
    final bitLength = _totalBytes * 8;
    _buffer[_bufferLen++] = 0x80;

    if (_bufferLen > 56) {
      _buffer.fillRange(_bufferLen, 64, 0);
      _processBlock(_buffer, 0);
      _bufferLen = 0;
    }

    _buffer.fillRange(_bufferLen, 56, 0);
    final bd = ByteData.sublistView(_buffer);
    bd.setUint64(56, bitLength, Endian.big);
    _processBlock(_buffer, 0);

    final out = StringBuffer();
    for (int i = 0; i < 8; i++) {
      out.write(_h[i].toRadixString(16).padLeft(8, '0'));
    }
    return out.toString();
  }

  /// Computes SHA-256 for a byte list.
  static String hashBytes(List<int> bytes) {
    final hasher = Sha256();
    hasher.update(bytes);
    return hasher.digestHex();
  }

  /// Computes SHA-256 for a UTF-8 string.
  static String hashString(String input) => hashBytes(utf8.encode(input));

  /// Computes SHA-256 for a file by streaming its bytes.
  static Future<String> hashFile(File file) async {
    final hasher = Sha256();
    final stream = file.openRead();
    await for (final chunk in stream) {
      hasher.update(chunk);
    }
    return hasher.digestHex();
  }
}

// ============================================================================
// Manifest & Metadata Models
// ============================================================================

/// Metadata entry for a single file tracked in `manifest.json`.
class BackupFileEntry {
  final String sha256;
  final int sizeBytes;
  final int recordCount;

  const BackupFileEntry({
    required this.sha256,
    required this.sizeBytes,
    required this.recordCount,
  });

  Map<String, dynamic> toJson() => {
    'sha256': sha256,
    'sizeBytes': sizeBytes,
    'recordCount': recordCount,
  };

  factory BackupFileEntry.fromJson(Map<String, dynamic> json) {
    return BackupFileEntry(
      sha256: json['sha256'] as String,
      sizeBytes: json['sizeBytes'] as int,
      recordCount: json['recordCount'] as int,
    );
  }
}

/// Represents the `manifest.json` file in a backup package.
class BackupManifest {
  final int version;
  final String createdAt;
  final String timestamp;
  final String source;
  final Map<String, BackupFileEntry> files;

  const BackupManifest({
    this.version = 1,
    required this.createdAt,
    required this.timestamp,
    required this.source,
    required this.files,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'createdAt': createdAt,
    'timestamp': timestamp,
    'source': source,
    'files': files.map((k, v) => MapEntry(k, v.toJson())),
  };

  factory BackupManifest.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 1;
    final createdAt = json['createdAt'] as String;
    final timestamp = json['timestamp'] as String;
    final source = json['source'] as String;
    final rawFiles = json['files'] as Map<String, dynamic>? ?? {};
    final files = rawFiles.map(
      (k, v) => MapEntry(
        k,
        BackupFileEntry.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    );
    return BackupManifest(
      version: version,
      createdAt: createdAt,
      timestamp: timestamp,
      source: source,
      files: files,
    );
  }
}

// ============================================================================
// Verification Models
// ============================================================================

/// Verification details for a single file in a backup.
class FileVerificationResult {
  final String fileName;
  final bool passed;
  final String expectedSha256;
  final String? actualSha256;
  final int expectedSize;
  final int? actualSize;
  final int expectedRecordCount;
  final int? actualRecordCount;
  final List<String> errors;

  const FileVerificationResult({
    required this.fileName,
    required this.passed,
    required this.expectedSha256,
    this.actualSha256,
    required this.expectedSize,
    this.actualSize,
    required this.expectedRecordCount,
    this.actualRecordCount,
    this.errors = const [],
  });
}

/// Comprehensive result of a backup directory verification.
class VerificationResult {
  final bool passed;
  final BackupManifest? manifest;
  final Map<String, FileVerificationResult> fileResults;
  final bool sha256SumsMatched;
  final List<String> errors;
  final List<String> details;

  const VerificationResult({
    required this.passed,
    this.manifest,
    this.fileResults = const {},
    this.sha256SumsMatched = false,
    this.errors = const [],
    this.details = const [],
  });
}

// ============================================================================
// Integrity Verifier
// ============================================================================

/// Verifies cryptographic hashes, file sizes, JSON integrity, and checksum files.
class IntegrityVerifier {
  const IntegrityVerifier();

  /// Verifies a backup directory against its manifest and SHA256SUMS.
  Future<VerificationResult> verifyBackup(Directory backupDir) async {
    final errors = <String>[];
    final details = <String>[];
    final fileResults = <String, FileVerificationResult>{};

    if (!await backupDir.exists()) {
      return VerificationResult(
        passed: false,
        errors: ['Backup directory does not exist: ${backupDir.path}'],
      );
    }

    final manifestFile = File(
      '${backupDir.path}${Platform.pathSeparator}$manifestFileName',
    );
    if (!await manifestFile.exists()) {
      return VerificationResult(
        passed: false,
        errors: ['Missing manifest file: ${manifestFile.path}'],
      );
    }

    BackupManifest manifest;
    try {
      final manifestJson = jsonDecode(await manifestFile.readAsString());
      if (manifestJson is! Map<String, dynamic>) {
        throw const FormatException('manifest.json must be a JSON object.');
      }
      manifest = BackupManifest.fromJson(manifestJson);
      details.add(
        'Manifest v${manifest.version} loaded (created at ${manifest.createdAt} UTC)',
      );
    } catch (e) {
      return VerificationResult(
        passed: false,
        errors: ['Invalid manifest.json: $e'],
      );
    }

    bool allFilesPassed = true;

    // Check required files presence in manifest
    if (!manifest.files.containsKey(recordsFileName)) {
      errors.add(
        'Manifest is missing required file entry for "$recordsFileName".',
      );
      allFilesPassed = false;
    }

    for (final entry in manifest.files.entries) {
      final fileName = entry.key;
      final expected = entry.value;
      final targetFile = File(
        '${backupDir.path}${Platform.pathSeparator}$fileName',
      );
      final fileErrors = <String>[];

      if (!await targetFile.exists()) {
        fileErrors.add('File not found: $fileName');
        errors.addAll(fileErrors);
        allFilesPassed = false;
        fileResults[fileName] = FileVerificationResult(
          fileName: fileName,
          passed: false,
          expectedSha256: expected.sha256,
          expectedSize: expected.sizeBytes,
          expectedRecordCount: expected.recordCount,
          errors: fileErrors,
        );
        continue;
      }

      final actualSize = await targetFile.length();
      if (actualSize != expected.sizeBytes) {
        fileErrors.add(
          'Size mismatch for $fileName: expected ${expected.sizeBytes} bytes, found $actualSize bytes',
        );
        allFilesPassed = false;
      }

      final actualSha256 = await Sha256.hashFile(targetFile);
      if (actualSha256.toLowerCase() != expected.sha256.toLowerCase()) {
        fileErrors.add(
          'SHA-256 hash mismatch for $fileName: expected ${expected.sha256}, calculated $actualSha256',
        );
        allFilesPassed = false;
      }

      int actualRecordCount = 0;
      try {
        final content = await targetFile.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is! List) {
          fileErrors.add(
            'JSON validation failed for $fileName: root must be a JSON list.',
          );
          allFilesPassed = false;
        } else {
          actualRecordCount = decoded.length;
          if (actualRecordCount != expected.recordCount) {
            fileErrors.add(
              'Record count mismatch for $fileName: expected ${expected.recordCount}, found $actualRecordCount',
            );
            allFilesPassed = false;
          }
          // Validate individual records/conflicts
          for (int i = 0; i < decoded.length; i++) {
            final item = decoded[i];
            if (item is! Map) {
              fileErrors.add(
                'Item at index $i in $fileName is not a JSON object.',
              );
              allFilesPassed = false;
              break;
            }
            if (item['id'] == null ||
                item['id'] is! String ||
                (item['id'] as String).isEmpty) {
              fileErrors.add(
                'Item at index $i in $fileName missing required string id.',
              );
              allFilesPassed = false;
              break;
            }
          }
        }
      } catch (e) {
        fileErrors.add('Invalid JSON syntax in $fileName: $e');
        allFilesPassed = false;
      }

      final passed = fileErrors.isEmpty;
      if (passed) {
        details.add(
          'Verified $fileName: ${expected.recordCount} records, $actualSize bytes, SHA-256: $actualSha256 [PASS]',
        );
      } else {
        errors.addAll(fileErrors);
      }

      fileResults[fileName] = FileVerificationResult(
        fileName: fileName,
        passed: passed,
        expectedSha256: expected.sha256,
        actualSha256: actualSha256,
        expectedSize: expected.sizeBytes,
        actualSize: actualSize,
        expectedRecordCount: expected.recordCount,
        actualRecordCount: actualRecordCount,
        errors: fileErrors,
      );
    }

    // Verify SHA256SUMS file if present
    bool sha256SumsMatched = true;
    final sumsFile = File(
      '${backupDir.path}${Platform.pathSeparator}$sha256SumsFileName',
    );
    if (await sumsFile.exists()) {
      final lines = await sumsFile.readAsLines();
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          final expectedHash = parts[0].trim();
          var checkFileName = parts.sublist(1).join(' ').trim();
          if (checkFileName.startsWith('*')) {
            checkFileName = checkFileName.substring(1);
          }
          final f = File(
            '${backupDir.path}${Platform.pathSeparator}$checkFileName',
          );
          if (!await f.exists()) {
            errors.add(
              'File listed in $sha256SumsFileName not found: $checkFileName',
            );
            sha256SumsMatched = false;
          } else {
            final computed = await Sha256.hashFile(f);
            if (computed.toLowerCase() != expectedHash.toLowerCase()) {
              errors.add(
                '$sha256SumsFileName mismatch for $checkFileName: expected $expectedHash, got $computed',
              );
              sha256SumsMatched = false;
            }
          }
        }
      }
      if (sha256SumsMatched) {
        details.add('Verified checksums in $sha256SumsFileName [PASS]');
      }
    }

    final overallPassed = allFilesPassed && sha256SumsMatched && errors.isEmpty;
    return VerificationResult(
      passed: overallPassed,
      manifest: manifest,
      fileResults: fileResults,
      sha256SumsMatched: sha256SumsMatched,
      errors: errors,
      details: details,
    );
  }
}

// ============================================================================
// Operation Results
// ============================================================================

/// Outcome of a successful backup operation.
class BackupResult {
  final Directory backupDirectory;
  final BackupManifest manifest;
  final Map<String, String> hashes;
  final Map<String, int> recordCounts;
  final Map<String, int> sizes;

  const BackupResult({
    required this.backupDirectory,
    required this.manifest,
    required this.hashes,
    required this.recordCounts,
    required this.sizes,
  });
}

/// Outcome of a successful restore operation.
class RestoreResult {
  final Directory targetDirectory;
  final Directory? safetySnapshotDirectory;
  final int restoredRecordCount;
  final int restoredConflictCount;
  final Map<String, String> restoredHashes;

  const RestoreResult({
    required this.targetDirectory,
    this.safetySnapshotDirectory,
    required this.restoredRecordCount,
    required this.restoredConflictCount,
    required this.restoredHashes,
  });
}

// ============================================================================
// Backup Engine
// ============================================================================

/// Core engine orchestrating backup creation, verification, restore, and testing.
class BackupEngine {
  final IntegrityVerifier verifier;

  const BackupEngine({this.verifier = const IntegrityVerifier()});

  /// Formats UTC timestamp as `yyyyMMdd_HHmmss`.
  static String formatTimestamp(DateTime dt) {
    final utc = dt.toUtc();
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    final h = utc.hour.toString().padLeft(2, '0');
    final min = utc.minute.toString().padLeft(2, '0');
    final s = utc.second.toString().padLeft(2, '0');
    return '$y$m${d}_$h$min$s';
  }

  /// Atomically writes bytes to [destination] using temporary file + rename.
  /// Handles Windows filesystem rename constraints safely with rollbacks.
  static Future<void> atomicWriteFile(File destination, List<int> bytes) async {
    final parent = destination.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final rand = Random().nextInt(1 << 30);
    final tempFile = File('${destination.path}.tmp-$pid-$rand');
    await tempFile.writeAsBytes(bytes, flush: true);

    try {
      await tempFile.rename(destination.path);
    } on FileSystemException {
      // Windows cannot overwrite existing files via rename.
      final oldBackup = File('${destination.path}.old-$pid-$rand');
      bool movedOld = false;
      try {
        if (await destination.exists()) {
          await destination.rename(oldBackup.path);
          movedOld = true;
        }
        await tempFile.rename(destination.path);
        if (movedOld && await oldBackup.exists()) {
          await oldBackup.delete();
        }
      } catch (_) {
        if (movedOld &&
            !await destination.exists() &&
            await oldBackup.exists()) {
          await oldBackup.rename(destination.path);
        }
        rethrow;
      }
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  /// Atomically copies [source] to [destination].
  static Future<void> atomicCopyFile(File source, File destination) async {
    final bytes = await source.readAsBytes();
    await atomicWriteFile(destination, bytes);
  }

  /// Roll back an interrupted restore from its pre-restore snapshot. The
  /// marker remains in place if any verification or copy fails, so the server
  /// will continue refusing to open a potentially mixed database.
  Future<void> recoverInterruptedRestore(Directory targetDir) async {
    final markerFile = File(
      '${targetDir.path}${Platform.pathSeparator}$restoreMarkerFileName',
    );
    if (!await markerFile.exists()) {
      throw BackupValidationException(
        'No interrupted restore marker was found.',
      );
    }
    final marker = jsonDecode(await markerFile.readAsString());
    if (marker is! Map<String, dynamic> || marker['version'] != 1) {
      throw BackupIntegrityException(
        'Restore marker is invalid; manual recovery is required.',
      );
    }
    final snapshotName = marker['snapshotFolder'];
    final hadRecords = marker['hadRecords'];
    final hadConflicts = marker['hadConflicts'];
    if (hadRecords is! bool ||
        hadConflicts is! bool ||
        (snapshotName != null &&
            (snapshotName is! String ||
                !snapshotName.startsWith(safetyBackupPrefix) ||
                snapshotName.contains(RegExp(r'[/\\]'))))) {
      throw BackupIntegrityException('Restore marker contents are invalid.');
    }
    final snapshotDir = snapshotName == null
        ? null
        : Directory('${targetDir.path}${Platform.pathSeparator}$snapshotName');
    Map<String, dynamic>? snapshotFiles;
    if (hadRecords || hadConflicts) {
      if (snapshotDir == null || !await snapshotDir.exists()) {
        throw BackupIntegrityException(
          'Pre-restore safety snapshot is missing.',
        );
      }
      final manifestFile = File(
        '${snapshotDir.path}${Platform.pathSeparator}safety_manifest.json',
      );
      final manifest = jsonDecode(await manifestFile.readAsString());
      if (manifest is! Map<String, dynamic> ||
          manifest['files'] is! Map<String, dynamic>) {
        throw BackupIntegrityException('Safety snapshot manifest is invalid.');
      }
      snapshotFiles = manifest['files'] as Map<String, dynamic>;
    }

    // Validate every original before changing either live file.
    final originals = <String, List<int>>{};
    for (final entry in <String, bool>{
      recordsFileName: hadRecords,
      conflictsFileName: hadConflicts,
    }.entries) {
      if (!entry.value) continue;
      final saved = File(
        '${snapshotDir!.path}${Platform.pathSeparator}${entry.key}',
      );
      final details = snapshotFiles![entry.key];
      if (details is! Map<String, dynamic> || !await saved.exists()) {
        throw BackupIntegrityException(
          'Safety snapshot is missing ${entry.key}.',
        );
      }
      final bytes = await saved.readAsBytes();
      if (bytes.length != details['sizeBytes'] ||
          Sha256.hashBytes(bytes) != details['sha256']) {
        throw BackupIntegrityException(
          'Safety snapshot failed integrity verification for ${entry.key}.',
        );
      }
      originals[entry.key] = bytes;
    }

    for (final name in <String>[recordsFileName, conflictsFileName]) {
      final live = File('${targetDir.path}${Platform.pathSeparator}$name');
      final original = originals[name];
      if (original == null) {
        if (await live.exists()) await live.delete();
      } else {
        await atomicWriteFile(live, original);
      }
    }
    await markerFile.delete();
  }

  /// Creates a backup of records and conflicts from [source] into [destination].
  ///
  /// - [destination]: target directory where timestamped backup folder is created.
  /// - [source]: directory containing `records.json` (defaults to `.local_data`).
  /// - [label]: optional alphanumeric label appended to the backup folder name.
  Future<BackupResult> backup({
    required Directory destination,
    Directory? source,
    String? label,
  }) async {
    final srcDir = source ?? Directory('.local_data');
    if (!await srcDir.exists()) {
      throw BackupValidationException(
        'Source directory does not exist: ${srcDir.path}',
      );
    }

    final srcRecordsFile = File(
      '${srcDir.path}${Platform.pathSeparator}$recordsFileName',
    );
    if (!await srcRecordsFile.exists()) {
      throw BackupValidationException(
        'Required file "$recordsFileName" not found in source directory "${srcDir.path}".',
      );
    }

    // Validate JSON structure and count records
    final List<dynamic> recordsList;
    try {
      final decoded = jsonDecode(await srcRecordsFile.readAsString());
      if (decoded is! List) {
        throw const FormatException('records.json must contain a JSON list.');
      }
      recordsList = decoded;
    } catch (e) {
      throw BackupValidationException('Invalid records.json in source: $e');
    }

    // Check conflicts.json
    final srcConflictsFile = File(
      '${srcDir.path}${Platform.pathSeparator}$conflictsFileName',
    );
    final List<dynamic> conflictsList;
    final bool hasSourceConflicts = await srcConflictsFile.exists();
    if (hasSourceConflicts) {
      try {
        final decoded = jsonDecode(await srcConflictsFile.readAsString());
        if (decoded is! List) {
          throw const FormatException(
            'conflicts.json must contain a JSON list.',
          );
        }
        conflictsList = decoded;
      } catch (e) {
        throw BackupValidationException('Invalid conflicts.json in source: $e');
      }
    } else {
      conflictsList = const [];
    }

    // Generate unique timestamped backup directory
    final now = DateTime.now().toUtc();
    final timestamp = formatTimestamp(now);
    String folderName = 'backup_$timestamp';
    if (label != null && label.trim().isNotEmpty) {
      final sanitizedLabel = label.trim().replaceAll(RegExp(r'[^\w\-]'), '_');
      if (sanitizedLabel.isNotEmpty) {
        folderName = 'backup_${timestamp}_$sanitizedLabel';
      }
    }

    Directory backupDir = Directory(
      '${destination.path}${Platform.pathSeparator}$folderName',
    );
    if (await backupDir.exists()) {
      int counter = 1;
      while (await Directory(
        '${destination.path}${Platform.pathSeparator}${folderName}_$counter',
      ).exists()) {
        counter++;
      }
      backupDir = Directory(
        '${destination.path}${Platform.pathSeparator}${folderName}_$counter',
      );
    }

    await backupDir.create(recursive: true);

    try {
      // 1. Write records.json
      final destRecordsFile = File(
        '${backupDir.path}${Platform.pathSeparator}$recordsFileName',
      );
      final recordsBytes = await srcRecordsFile.readAsBytes();
      await atomicWriteFile(destRecordsFile, recordsBytes);

      // 2. Write conflicts.json
      final destConflictsFile = File(
        '${backupDir.path}${Platform.pathSeparator}$conflictsFileName',
      );
      final List<int> conflictsBytes;
      if (hasSourceConflicts) {
        conflictsBytes = await srcConflictsFile.readAsBytes();
      } else {
        conflictsBytes = utf8.encode('[]\n');
      }
      await atomicWriteFile(destConflictsFile, conflictsBytes);

      // Read back destination files immediately to compute hashes & sizes
      final verifiedRecordsBytes = await destRecordsFile.readAsBytes();
      final recordsSha256 = Sha256.hashBytes(verifiedRecordsBytes);
      final recordsSize = verifiedRecordsBytes.length;

      final verifiedConflictsBytes = await destConflictsFile.readAsBytes();
      final conflictsSha256 = Sha256.hashBytes(verifiedConflictsBytes);
      final conflictsSize = verifiedConflictsBytes.length;

      // 3. Write manifest.json
      final manifest = BackupManifest(
        version: 1,
        createdAt: now.toIso8601String(),
        timestamp: timestamp,
        source: srcDir.path,
        files: {
          recordsFileName: BackupFileEntry(
            sha256: recordsSha256,
            sizeBytes: recordsSize,
            recordCount: recordsList.length,
          ),
          conflictsFileName: BackupFileEntry(
            sha256: conflictsSha256,
            sizeBytes: conflictsSize,
            recordCount: conflictsList.length,
          ),
        },
      );

      const encoder = JsonEncoder.withIndent('  ');
      final manifestJsonStr = '${encoder.convert(manifest.toJson())}\n';
      final manifestFile = File(
        '${backupDir.path}${Platform.pathSeparator}$manifestFileName',
      );
      await atomicWriteFile(manifestFile, utf8.encode(manifestJsonStr));

      // 4. Write SHA256SUMS
      final manifestSha256 = Sha256.hashString(manifestJsonStr);
      final sha256SumsBuffer = StringBuffer()
        ..writeln('$recordsSha256  $recordsFileName')
        ..writeln('$conflictsSha256  $conflictsFileName')
        ..writeln('$manifestSha256  $manifestFileName');

      final sha256SumsFile = File(
        '${backupDir.path}${Platform.pathSeparator}$sha256SumsFileName',
      );
      await atomicWriteFile(
        sha256SumsFile,
        utf8.encode(sha256SumsBuffer.toString()),
      );

      // 5. Read back destination files to verify SHA-256 hashes immediately after writing
      final verification = await verifier.verifyBackup(backupDir);
      if (!verification.passed) {
        throw BackupIntegrityException(
          'Immediate readback verification failed:\n  ${verification.errors.join("\n  ")}',
        );
      }

      return BackupResult(
        backupDirectory: backupDir,
        manifest: manifest,
        hashes: {
          recordsFileName: recordsSha256,
          conflictsFileName: conflictsSha256,
          manifestFileName: manifestSha256,
        },
        recordCounts: {
          recordsFileName: recordsList.length,
          conflictsFileName: conflictsList.length,
        },
        sizes: {
          recordsFileName: recordsSize,
          conflictsFileName: conflictsSize,
          manifestFileName: utf8.encode(manifestJsonStr).length,
        },
      );
    } catch (e) {
      // Clean up partially written backup on error
      if (await backupDir.exists()) {
        try {
          await backupDir.delete(recursive: true);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Restores records and conflicts from [backupDir] to [target].
  ///
  /// - Verifies backup integrity with cryptographic hashes before touching target.
  /// - Prevents accidental overwrite of existing live data unless [confirmOverwrite] is true.
  /// - Creates a pre-restore safety snapshot in `<target>/pre_restore_safety_backup_<timestamp>/` if live data exists.
  /// - Atomically replaces target files and verifies restored files.
  Future<RestoreResult> restore({
    required Directory backupDir,
    Directory? target,
    bool confirmOverwrite = false,
  }) async {
    final targetDir = target ?? Directory('.local_data');
    final markerFile = File(
      '${targetDir.path}${Platform.pathSeparator}$restoreMarkerFileName',
    );
    if (await markerFile.exists()) {
      throw BackupValidationException(
        'An interrupted restore must be recovered before another restore. Run the recover command with --target=${targetDir.path}.',
      );
    }

    // Safety Check 1: Verify backup integrity with hashes FIRST
    final verification = await verifier.verifyBackup(backupDir);
    if (!verification.passed) {
      throw BackupIntegrityException(
        'Backup verification failed. Restore aborted to protect target data.\n'
        'Errors:\n  ${verification.errors.join("\n  ")}',
      );
    }

    final targetRecordsFile = File(
      '${targetDir.path}${Platform.pathSeparator}$recordsFileName',
    );
    final targetConflictsFile = File(
      '${targetDir.path}${Platform.pathSeparator}$conflictsFileName',
    );

    final hasExistingRecords = await targetRecordsFile.exists();
    final hasExistingConflicts = await targetConflictsFile.exists();
    final liveDataExists = hasExistingRecords || hasExistingConflicts;

    Directory? safetySnapshotDir;

    // Safety Check 2: Check for existing live data
    if (liveDataExists) {
      if (!confirmOverwrite) {
        throw BackupOverwriteException(
          'Target directory "${targetDir.path}" contains live data ($recordsFileName / $conflictsFileName).\n'
          'Restore was blocked to prevent data loss. Re-run with --confirm-overwrite to replace existing data.\n'
          'When confirmed, a safety backup will be automatically saved prior to replacement.',
        );
      }

      // Create pre-restore safety snapshot
      final snapshotTimestamp = formatTimestamp(DateTime.now().toUtc());
      String snapshotFolderName = '$safetyBackupPrefix$snapshotTimestamp';
      safetySnapshotDir = Directory(
        '${targetDir.path}${Platform.pathSeparator}$snapshotFolderName',
      );
      if (await safetySnapshotDir.exists()) {
        int suffix = 1;
        while (await Directory(
          '${targetDir.path}${Platform.pathSeparator}${snapshotFolderName}_$suffix',
        ).exists()) {
          suffix++;
        }
        safetySnapshotDir = Directory(
          '${targetDir.path}${Platform.pathSeparator}${snapshotFolderName}_$suffix',
        );
      }
      await safetySnapshotDir.create(recursive: true);

      // Snapshot existing files
      final filesToSnapshot = [
        targetRecordsFile,
        targetConflictsFile,
        File('${targetDir.path}${Platform.pathSeparator}$recordsFileName.bak'),
        File(
          '${targetDir.path}${Platform.pathSeparator}$conflictsFileName.bak',
        ),
      ];

      final snapshotMap = <String, dynamic>{};
      final snapshotSums = StringBuffer();

      for (final f in filesToSnapshot) {
        if (await f.exists()) {
          final baseName = f.uri.pathSegments.last;
          final snapDest = File(
            '${safetySnapshotDir.path}${Platform.pathSeparator}$baseName',
          );
          final bytes = await f.readAsBytes();
          await atomicWriteFile(snapDest, bytes);
          final hash = Sha256.hashBytes(bytes);
          snapshotMap[baseName] = {'sizeBytes': bytes.length, 'sha256': hash};
          snapshotSums.writeln('$hash  $baseName');
        }
      }

      // Write snapshot manifest & sums
      final snapshotManifest = {
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'timestamp': snapshotTimestamp,
        'targetPath': targetDir.path,
        'files': snapshotMap,
      };
      await atomicWriteFile(
        File(
          '${safetySnapshotDir.path}${Platform.pathSeparator}safety_manifest.json',
        ),
        utf8.encode(
          '${const JsonEncoder.withIndent('  ').convert(snapshotManifest)}\n',
        ),
      );
      await atomicWriteFile(
        File(
          '${safetySnapshotDir.path}${Platform.pathSeparator}$sha256SumsFileName',
        ),
        utf8.encode(snapshotSums.toString()),
      );
    }

    // Ensure target directory exists
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    // The two files cannot be replaced as one filesystem transaction. The
    // marker makes an interruption visible to the server and enables rollback.
    await atomicWriteFile(
      markerFile,
      utf8.encode(
        jsonEncode({
          'version': 1,
          'snapshotFolder': safetySnapshotDir?.uri.pathSegments
              .where((segment) => segment.isNotEmpty)
              .last,
          'hadRecords': hasExistingRecords,
          'hadConflicts': hasExistingConflicts,
        }),
      ),
    );

    final srcRecordsFile = File(
      '${backupDir.path}${Platform.pathSeparator}$recordsFileName',
    );
    final srcConflictsFile = File(
      '${backupDir.path}${Platform.pathSeparator}$conflictsFileName',
    );

    late final List<dynamic> restoredRecordsDecoded;
    late final List<dynamic> restoredConflictsDecoded;
    late final String restoredRecordsHash;
    late final String restoredConflictsHash;
    try {
      await atomicCopyFile(srcRecordsFile, targetRecordsFile);
      await atomicCopyFile(srcConflictsFile, targetConflictsFile);

      final restoredRecordsBytes = await targetRecordsFile.readAsBytes();
      final restoredConflictsBytes = await targetConflictsFile.readAsBytes();
      restoredRecordsHash = Sha256.hashBytes(restoredRecordsBytes);
      restoredConflictsHash = Sha256.hashBytes(restoredConflictsBytes);
      final expectedRecordsHash =
          verification.manifest!.files[recordsFileName]!.sha256;
      final expectedConflictsHash =
          verification.manifest!.files[conflictsFileName]!.sha256;
      if (restoredRecordsHash.toLowerCase() !=
              expectedRecordsHash.toLowerCase() ||
          restoredConflictsHash.toLowerCase() !=
              expectedConflictsHash.toLowerCase()) {
        throw BackupIntegrityException(
          'Restored files failed readback hash verification.',
        );
      }
      restoredRecordsDecoded =
          jsonDecode(utf8.decode(restoredRecordsBytes)) as List;
      restoredConflictsDecoded =
          jsonDecode(utf8.decode(restoredConflictsBytes)) as List;
      await markerFile.delete();
    } catch (error) {
      try {
        await recoverInterruptedRestore(targetDir);
      } catch (recoveryError) {
        throw BackupIntegrityException(
          'Restore failed ($error), and automatic rollback failed ($recoveryError). '
          'Do not start the server; recover from the safety snapshot.',
        );
      }
      rethrow;
    }

    return RestoreResult(
      targetDirectory: targetDir,
      safetySnapshotDirectory: safetySnapshotDir,
      restoredRecordCount: restoredRecordsDecoded.length,
      restoredConflictCount: restoredConflictsDecoded.length,
      restoredHashes: {
        recordsFileName: restoredRecordsHash,
        conflictsFileName: restoredConflictsHash,
      },
    );
  }

  /// Executes an end-to-end self-contained verification suite using synthetic data.
  Future<bool> runSyntheticTests({
    bool verbose = true,
    StringSink? outSink,
    StringSink? errSink,
  }) async {
    final out = outSink ?? stdout;
    final err = errSink ?? stderr;

    void log(String message) {
      if (verbose) out.writeln(message);
    }

    log('================================================================');
    log('   BACKUP UTILITY: SYNTHETIC DATA VERIFICATION SUITE');
    log('================================================================');

    final scratchDir = Directory.systemTemp.createTempSync(
      'backup_utility_test_',
    );

    try {
      final srcDir = Directory(
        '${scratchDir.path}${Platform.pathSeparator}source',
      );
      final destDir = Directory(
        '${scratchDir.path}${Platform.pathSeparator}dest',
      );
      final targetDir = Directory(
        '${scratchDir.path}${Platform.pathSeparator}target',
      );
      await srcDir.create(recursive: true);

      // 1. Generate synthetic source records and conflict
      log('1. Generating synthetic records and conflicts...');
      final syntheticRecords = [
        {
          'id': 'rec-syn-001',
          'participant': {
            'studyId': 'C01-100001',
            'name': 'Participant Alpha',
            'indianPhone': '9876543210',
          },
          'visitNumber': 1,
          'collectorId': 'collector-01',
          'createdAt': '2026-09-23T08:00:00.000Z',
          'updatedAt': '2026-09-23T08:00:00.000Z',
          'status': 'submitted',
          'syncState': 'synced',
          'reviewState': 'pending',
          'revision': 1,
        },
        {
          'id': 'rec-syn-002',
          'participant': {
            'studyId': 'C01-100002',
            'name': 'Participant Beta',
            'indianPhone': '9876543211',
          },
          'visitNumber': 1,
          'collectorId': 'collector-01',
          'createdAt': '2026-09-23T08:15:00.000Z',
          'updatedAt': '2026-09-23T08:15:00.000Z',
          'status': 'submitted',
          'syncState': 'synced',
          'reviewState': 'pending',
          'revision': 1,
        },
      ];

      final syntheticConflicts = [
        {
          'id': 'conflict-syn-001',
          'conflictType': 'duplicate_visit',
          'message': 'Visit number is already recorded for this participant.',
          'createdAt': '2026-09-23T08:30:00.000Z',
          'collectorId': 'collector-01',
          'status': 'pending',
          'rejectedRecord': {
            'id': 'rec-syn-003',
            'participant': {
              'studyId': 'C01-100001',
              'name': 'Participant Alpha',
              'indianPhone': '9876543210',
            },
            'visitNumber': 1,
            'collectorId': 'collector-01',
            'createdAt': '2026-09-23T08:30:00.000Z',
            'updatedAt': '2026-09-23T08:30:00.000Z',
            'status': 'draft',
            'syncState': 'pending',
            'reviewState': 'pending',
            'revision': 1,
          },
        },
      ];

      final srcRecordsFile = File(
        '${srcDir.path}${Platform.pathSeparator}$recordsFileName',
      );
      final srcConflictsFile = File(
        '${srcDir.path}${Platform.pathSeparator}$conflictsFileName',
      );

      await srcRecordsFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(syntheticRecords)}\n',
      );
      await srcConflictsFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(syntheticConflicts)}\n',
      );
      log('   [OK] Source data written (2 records, 1 conflict).');

      // 2. Run backup to temp destination
      log('2. Running backup to temporary destination...');
      final backupResult = await backup(
        destination: destDir,
        source: srcDir,
        label: 'synthetic_test',
      );
      log('   [OK] Backup created at: ${backupResult.backupDirectory.path}');

      // 3. Verify backup integrity
      log('3. Verifying backup integrity...');
      final verifyResult = await verifier.verifyBackup(
        backupResult.backupDirectory,
      );
      if (!verifyResult.passed) {
        throw BackupIntegrityException(
          'Verification of pristine backup failed: ${verifyResult.errors}',
        );
      }
      log('   [PASS] Pristine backup passed integrity check.');

      // 4. Tamper detection test
      log(
        '4. Performing tamper detection test (modifying 1 byte in records.json)...',
      );
      final tamperedDir = Directory(
        '${scratchDir.path}${Platform.pathSeparator}tampered_backup',
      );
      await tamperedDir.create(recursive: true);

      // Copy all backup files into tampered directory
      for (final entity in backupResult.backupDirectory.listSync()) {
        if (entity is File) {
          final fileName = entity.uri.pathSegments.last;
          await entity.copy(
            '${tamperedDir.path}${Platform.pathSeparator}$fileName',
          );
        }
      }

      // Tamper 1 byte in records.json
      final tamperedRecordsFile = File(
        '${tamperedDir.path}${Platform.pathSeparator}$recordsFileName',
      );
      final rawRecordsBytes = await tamperedRecordsFile.readAsBytes();
      // Invert 1 bit in the payload
      rawRecordsBytes[rawRecordsBytes.length ~/ 2] ^= 0x01;
      await tamperedRecordsFile.writeAsBytes(rawRecordsBytes, flush: true);

      final tamperedVerify = await verifier.verifyBackup(tamperedDir);
      if (tamperedVerify.passed) {
        throw BackupIntegrityException(
          'Tamper detection failed: tampered backup was incorrectly reported as PASS!',
        );
      }
      log('   [PASS] Tamper detection successfully caught hash mismatch:');
      for (final err in tamperedVerify.errors) {
        log('          - $err');
      }

      // Ensure restore rejects tampered backup
      bool restoreRejected = false;
      try {
        await restore(backupDir: tamperedDir, target: targetDir);
      } on BackupIntegrityException {
        restoreRejected = true;
      }
      if (!restoreRejected) {
        throw BackupIntegrityException(
          'Tamper test failed: restore accepted corrupted backup!',
        );
      }
      log('   [PASS] Restore of tampered backup was rejected immediately.');

      // 5. Restore untampered backup to fresh target directory
      log('5. Restoring untampered backup to fresh target directory...');
      final restoreResult = await restore(
        backupDir: backupResult.backupDirectory,
        target: targetDir,
      );
      if (restoreResult.restoredRecordCount != 2 ||
          restoreResult.restoredConflictCount != 1) {
        throw BackupValidationException(
          'Restored record counts mismatch: records=${restoreResult.restoredRecordCount}, conflicts=${restoreResult.restoredConflictCount}',
        );
      }

      // Verify restored content matches original synthetic data exactly
      final restoredRecords = jsonDecode(
        await File('${targetDir.path}${Platform.pathSeparator}$recordsFileName')
            .readAsString(),
      );
      final restoredConflicts = jsonDecode(
        await File(
          '${targetDir.path}${Platform.pathSeparator}$conflictsFileName',
        ).readAsString(),
      );

      if (jsonEncode(restoredRecords) != jsonEncode(syntheticRecords)) {
        throw BackupValidationException(
          'Restored records do not match original synthetic records!',
        );
      }
      if (jsonEncode(restoredConflicts) != jsonEncode(syntheticConflicts)) {
        throw BackupValidationException(
          'Restored conflicts do not match original synthetic conflicts!',
        );
      }
      log('   [PASS] Restored files match original synthetic data exactly.');

      // 6. Verify overwrite protection refuses overwrite without --confirm-overwrite
      log('6. Testing overwrite protection without --confirm-overwrite...');
      bool overwriteBlocked = false;
      try {
        await restore(
          backupDir: backupResult.backupDirectory,
          target: targetDir,
          confirmOverwrite: false,
        );
      } on BackupOverwriteException {
        overwriteBlocked = true;
      }
      if (!overwriteBlocked) {
        throw BackupOverwriteException(
          'Overwrite protection failed: restore overwrote live target without --confirm-overwrite!',
        );
      }
      log('   [PASS] Overwrite protection successfully refused overwrite.');

      // 7. Verify pre-restore safety snapshot is created when --confirm-overwrite is supplied
      log('7. Testing safety snapshot with --confirm-overwrite...');
      // Modify target records with distinct canary marker
      final canaryRecords = [
        {'id': 'canary-before-restore-record'},
      ];
      await File('${targetDir.path}${Platform.pathSeparator}$recordsFileName')
          .writeAsString(jsonEncode(canaryRecords));

      final confirmedRestoreResult = await restore(
        backupDir: backupResult.backupDirectory,
        target: targetDir,
        confirmOverwrite: true,
      );

      final snapshotDir = confirmedRestoreResult.safetySnapshotDirectory;
      if (snapshotDir == null || !await snapshotDir.exists()) {
        throw BackupException(
          'Pre-restore safety snapshot directory was not created!',
        );
      }

      final snapRecordsFile = File(
        '${snapshotDir.path}${Platform.pathSeparator}$recordsFileName',
      );
      if (!await snapRecordsFile.exists()) {
        throw BackupException(
          'Pre-restore safety snapshot does not contain saved records.json!',
        );
      }
      final snapContent = await snapRecordsFile.readAsString();
      if (!snapContent.contains('canary-before-restore-record')) {
        throw BackupException(
          'Pre-restore safety snapshot did not capture pre-existing canary data!',
        );
      }

      // Verify that target data now has original restored records
      final finalRestored = await File(
        '${targetDir.path}${Platform.pathSeparator}$recordsFileName',
      ).readAsString();
      if (!finalRestored.contains('rec-syn-001')) {
        throw BackupException(
          'Final target data does not contain restored backup records!',
        );
      }
      log('   [PASS] Safety snapshot created at: ${snapshotDir.path}');
      log('   [PASS] Pre-existing canary data correctly archived in snapshot.');
      log('   [PASS] Target restored to clean backup data.');

      log('================================================================');
      log('   ALL 7/7 SYNTHETIC VERIFICATION TESTS PASSED SUCCESSFULLY');
      log('================================================================');
      return true;
    } catch (e, stack) {
      err.writeln('TEST FAILED: $e');
      if (verbose) err.writeln(stack);
      return false;
    } finally {
      // 8. Clean up all temporary directories
      if (await scratchDir.exists()) {
        try {
          await scratchDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}

// ============================================================================
// CLI Entrypoint and Runner
// ============================================================================

/// Command-line parser and command executor for `backup_utility.dart`.
class BackupCli {
  final BackupEngine engine;
  final StringSink out;
  final StringSink err;

  BackupCli({BackupEngine? engine, StringSink? outSink, StringSink? errSink})
    : engine = engine ?? const BackupEngine(),
      out = outSink ?? stdout,
      err = errSink ?? stderr;

  void printUsage() {
    out.writeln('''
===============================================================================
  Local Sync Backup & Recovery Utility (FIPS 180-4 SHA-256 Verified)
===============================================================================

Usage:
  dart run tool/backup_utility.dart <subcommand> [arguments]

Available Subcommands:
  backup      Create a timestamped, verified backup of records and conflicts.
  verify      Validate checksums, manifest, and JSON structure of a backup.
  restore     Safely restore records from backup with overwrite safety snapshot.
  recover     Roll back an interrupted restore from its safety snapshot.
  test        Run automated self-contained synthetic test suite.
  verify-synthetic (alias for test)

Subcommand Details:
  backup:
    --destination=<path>   Required destination folder (e.g., USB drive or network share).
    --source=<path>        Source directory containing records.json (default: .local_data).
    --label=<string>       Optional label appended to backup folder name.

  verify:
    --backup=<path>        Required path to backup directory to verify.

  restore:
    --backup=<path>        Required path to backup directory to restore from.
    --target=<path>        Target directory to restore into (default: .local_data).
    --confirm-overwrite    Required flag if live records exist in the target directory.
                           Automatically takes a pre-restore safety snapshot.

  recover:
    --target=<path>        Target directory with restore_in_progress.json.

  test / verify-synthetic:
    Executes a full verification suite with synthetic records, tamper checks,
    restore validation, and safety snapshot confirmation.

Examples:
  dart run tool/backup_utility.dart backup --destination=E:\\Backups --label=weekly
  dart run tool/backup_utility.dart verify --backup=E:\\Backups\\backup_20260923_080000
  dart run tool/backup_utility.dart restore --backup=E:\\Backups\\backup_20260923_080000 --confirm-overwrite
  dart run tool/backup_utility.dart recover --target=.local_data
  dart run tool/backup_utility.dart test
===============================================================================
''');
  }

  /// Parses CLI arguments into subcommands, options, and flags.
  Map<String, dynamic> parseArgs(List<String> args) {
    if (args.isEmpty) {
      return {'subcommand': 'help'};
    }

    final subcommand = args[0].toLowerCase();
    final options = <String, String>{};
    final flags = <String>{};

    for (int i = 1; i < args.length; i++) {
      final arg = args[i];
      if (arg.startsWith('--')) {
        final equalIndex = arg.indexOf('=');
        if (equalIndex != -1) {
          final key = arg.substring(2, equalIndex);
          final value = arg.substring(equalIndex + 1);
          options[key] = value;
        } else {
          final key = arg.substring(2);
          if (i + 1 < args.length && !args[i + 1].startsWith('-')) {
            options[key] = args[i + 1];
            i++;
          } else {
            flags.add(key);
          }
        }
      } else if (arg.startsWith('-')) {
        final key = arg.substring(1);
        if (i + 1 < args.length && !args[i + 1].startsWith('-')) {
          options[key] = args[i + 1];
          i++;
        } else {
          flags.add(key);
        }
      }
    }

    return {'subcommand': subcommand, 'options': options, 'flags': flags};
  }

  /// Runs the CLI tool with arguments, returning an exit code.
  Future<int> run(List<String> args) async {
    final parsed = parseArgs(args);
    final subcommand = parsed['subcommand'] as String;
    final options = parsed['options'] as Map<String, String>;
    final flags = parsed['flags'] as Set<String>;

    if (flags.contains('help') ||
        flags.contains('h') ||
        subcommand == 'help' ||
        subcommand == '--help' ||
        subcommand == '-h') {
      printUsage();
      return 0;
    }

    try {
      switch (subcommand) {
        case 'backup':
          return await _runBackup(options, flags);
        case 'verify':
          return await _runVerify(options, flags);
        case 'restore':
          return await _runRestore(options, flags);
        case 'recover':
          return await _runRecover(options);
        case 'test':
        case 'verify-synthetic':
          return await _runTest();
        default:
          err.writeln('Unknown subcommand: "$subcommand"');
          printUsage();
          return 64; // Usage error
      }
    } on BackupException catch (e) {
      err.writeln('\n[ERROR] $e');
      return 1;
    } catch (e, stack) {
      err.writeln('\n[UNEXPECTED ERROR] $e');
      err.writeln(stack);
      return 1;
    }
  }

  Future<int> _runBackup(Map<String, String> options, Set<String> flags) async {
    final destPath = options['destination'] ?? options['d'];
    if (destPath == null || destPath.trim().isEmpty) {
      err.writeln('Error: Missing required argument: --destination=<path>');
      out.writeln(
        'Example: dart run tool/backup_utility.dart backup --destination=E:\\Backups',
      );
      return 64;
    }

    final srcPath = options['source'] ?? options['s'] ?? '.local_data';
    final label = options['label'] ?? options['l'];

    // The engine can write to any directory for synthetic tests, but the
    // operator-facing CLI must not mistake a same-PC copy for a real backup.
    final tempRoot = Directory.systemTemp.absolute.path.toLowerCase();
    final sourceAbsolute = Directory(srcPath).absolute.path.toLowerCase();
    final testOverride =
        flags.contains('allow-local-test-destination') &&
        Platform.environment['STUDY_BACKUP_TEST_MODE'] == '1' &&
        sourceAbsolute.startsWith('$tempRoot${Platform.pathSeparator}');
    if (flags.contains('allow-local-test-destination') && !testOverride) {
      throw BackupValidationException(
        'Local destination override is permitted only for synthetic tests under the system temporary directory.',
      );
    }
    if (!testOverride) {
      if (!Platform.isWindows) {
        throw BackupValidationException(
          'Automatic off-device verification is available only on Windows. Use the engine for synthetic tests; do not assume a local path is a backup.',
        );
      }
      final check = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        File('tool/validate_backup_destination.ps1').absolute.path,
        '-Destination',
        destPath,
      ]);
      if (check.exitCode != 0) {
        throw BackupValidationException(
          'Destination is not verified off-PC storage. ${check.stderr.toString().trim()}',
        );
      }
    }

    out.writeln('=== BACKUP OPERATION STARTED ===');
    out.writeln('Source directory:      $srcPath');
    out.writeln('Destination directory: $destPath');
    if (label != null) {
      out.writeln('Backup label:          $label');
    }

    final result = await engine.backup(
      destination: Directory(destPath),
      source: Directory(srcPath),
      label: label,
    );

    out.writeln('\n--- Backup Created Successfully ---');
    out.writeln('Location:     ${result.backupDirectory.path}');
    out.writeln(
      'Timestamp:    ${result.manifest.timestamp} (UTC: ${result.manifest.createdAt})',
    );
    out.writeln('Files Written:');
    for (final entry in result.manifest.files.entries) {
      final name = entry.key;
      final fileInfo = entry.value;
      out.writeln(
        '  - $name: ${fileInfo.recordCount} records, ${fileInfo.sizeBytes} bytes',
      );
      out.writeln('    SHA-256: ${fileInfo.sha256}');
    }
    out.writeln('Manifest:     $manifestFileName');
    out.writeln('Checksums:    $sha256SumsFileName');
    out.writeln('\n[PASS] Verified readback hashes match on disk.');
    out.writeln('=== BACKUP COMPLETED SUCCESSFULLY ===');
    return 0;
  }

  Future<int> _runVerify(Map<String, String> options, Set<String> flags) async {
    final backupPath = options['backup'] ?? options['b'];
    if (backupPath == null || backupPath.trim().isEmpty) {
      err.writeln('Error: Missing required argument: --backup=<path>');
      out.writeln(
        'Example: dart run tool/backup_utility.dart verify --backup=E:\\Backups\\backup_20260923_080000',
      );
      return 64;
    }

    out.writeln('=== VERIFY OPERATION STARTED ===');
    out.writeln('Backup directory: $backupPath');

    final result = await engine.verifier.verifyBackup(Directory(backupPath));

    out.writeln('\n--- Verification Details ---');
    for (final detail in result.details) {
      out.writeln('  [OK] $detail');
    }

    if (result.passed) {
      out.writeln('\nChecksum Verification Summary:');
      for (final entry in result.fileResults.entries) {
        final r = entry.value;
        out.writeln(
          '  [PASS] ${r.fileName}: ${r.actualRecordCount} records, ${r.actualSize} bytes, SHA-256: ${r.actualSha256}',
        );
      }
      out.writeln('\n=== VERIFY RESULT: PASS ===');
      return 0;
    } else {
      err.writeln('\n--- Verification Failures ---');
      for (final error in result.errors) {
        err.writeln('  [FAIL] $error');
      }
      err.writeln('\n=== VERIFY RESULT: FAIL ===');
      return 1;
    }
  }

  Future<int> _runRestore(
    Map<String, String> options,
    Set<String> flags,
  ) async {
    final backupPath = options['backup'] ?? options['b'];
    if (backupPath == null || backupPath.trim().isEmpty) {
      err.writeln('Error: Missing required argument: --backup=<path>');
      out.writeln(
        'Example: dart run tool/backup_utility.dart restore --backup=E:\\Backups\\backup_20260923_080000',
      );
      return 64;
    }

    final targetPath = options['target'] ?? options['t'] ?? '.local_data';
    final confirmOverwrite =
        flags.contains('confirm-overwrite') ||
        flags.contains('confirmOverwrite') ||
        flags.contains('force');

    out.writeln('=== RESTORE OPERATION STARTED ===');
    out.writeln('Backup directory:      $backupPath');
    out.writeln('Target directory:      $targetPath');
    out.writeln('Overwrite confirmed:   $confirmOverwrite');

    final result = await engine.restore(
      backupDir: Directory(backupPath),
      target: Directory(targetPath),
      confirmOverwrite: confirmOverwrite,
    );

    out.writeln('\n--- Restore Completed Successfully ---');
    out.writeln('Target Location:       ${result.targetDirectory.path}');
    if (result.safetySnapshotDirectory != null) {
      out.writeln(
        'Pre-Restore Snapshot:  ${result.safetySnapshotDirectory!.path}',
      );
    }
    out.writeln('Restored Records:      ${result.restoredRecordCount}');
    out.writeln('Restored Conflicts:    ${result.restoredConflictCount}');
    out.writeln('Restored Checksums:');
    for (final entry in result.restoredHashes.entries) {
      out.writeln('  - ${entry.key}: SHA-256 ${entry.value}');
    }
    out.writeln('\n[PASS] Restored files verified and match backup checksums.');
    out.writeln('=== RESTORE COMPLETED SUCCESSFULLY ===');
    return 0;
  }

  Future<int> _runRecover(Map<String, String> options) async {
    final targetPath = options['target'] ?? options['t'] ?? '.local_data';
    await engine.recoverInterruptedRestore(Directory(targetPath));
    out.writeln(
      'Interrupted restore rolled back from its verified safety snapshot.',
    );
    return 0;
  }

  Future<int> _runTest() async {
    final success = await engine.runSyntheticTests(
      verbose: true,
      outSink: out,
      errSink: err,
    );
    return success ? 0 : 1;
  }
}

// ============================================================================
// Main
// ============================================================================

Future<void> main(List<String> args) async {
  final cli = BackupCli();
  final exit = await cli.run(args);
  if (exit != 0) {
    exitCode = exit;
  }
}
