/// Shared participant Study ID validation and formatting contract.
///
/// Supported formats:
/// 1. Collector-scoped IDs (no practical limit):
///    `C<collectorNum>-<sequence>`, e.g., `C01-000001`, `C02-000002`.
///    - Collector numbers: any positive number (formatted with at least 2 digits).
///    - Sequence numbers: positive, with at least six digits (no upper cap).
/// 2. Legacy demo IDs:
///    `P<sequence>`, e.g., `P001`, `P002`, `P101`, `P0001`.
library;

/// Matches collector-scoped IDs like `C01-000001` or `C001-000001`.
final _collectorScopedRegex = RegExp(r'^C(\d{2,})-(\d{6,})$', caseSensitive: false);

/// Matches legacy IDs like `P001`, `P0001`.
final _legacyParticipantRegex = RegExp(r'^P(\d{3,})$', caseSensitive: false);

/// Returns true if [studyId] matches either the standard collector-scoped
/// format (`C01-000001`) or legacy format (`P001`).
bool isValidParticipantStudyId(String? studyId) {
  return normalizeParticipantStudyId(studyId) != null;
}

/// Normalizes [studyId] to uppercase and trimmed form, or returns null if invalid.
String? normalizeParticipantStudyId(String? studyId) {
  if (studyId == null) return null;
  final trimmed = studyId.trim().toUpperCase();
  if (trimmed.isEmpty) return null;
  final collectorMatch = _collectorScopedRegex.firstMatch(trimmed);
  if (collectorMatch != null) {
    final collectorNum = BigInt.tryParse(collectorMatch.group(1)!);
    final seqNum = int.tryParse(collectorMatch.group(2)!);
    if (collectorNum == null || collectorNum < BigInt.one ||
        seqNum == null || seqNum < 1) {
      return null;
    }
    final colStr = collectorNum.toString().padLeft(2, '0');
    final seqStr = seqNum.toString().padLeft(6, '0');
    return 'C$colStr-$seqStr';
  }

  final legacyMatch = _legacyParticipantRegex.firstMatch(trimmed);
  if (legacyMatch != null) {
    final num = int.tryParse(legacyMatch.group(1)!);
    if (num == null || num < 1) return null;
    final digits = legacyMatch.group(1)!;
    return 'P${num.toString().padLeft(digits.length, '0')}';
  }

  return null;
}

/// Generates a collector-scoped Study ID from any positive collector number
/// and any positive sequence number.
String formatCollectorParticipantStudyId(int collectorNumber, int sequenceNumber) {
  if (collectorNumber < 1) {
    throw ArgumentError.value(
      collectorNumber,
      'collectorNumber',
      'Collector number must be positive.',
    );
  }
  if (sequenceNumber < 1) {
    throw ArgumentError.value(
      sequenceNumber,
      'sequenceNumber',
      'Sequence number must be a positive integer.',
    );
  }
  final colStr = collectorNumber.toString().padLeft(2, '0');
  final seqStr = sequenceNumber.toString().padLeft(6, '0');
  return 'C$colStr-$seqStr';
}

/// Returns the expected prefix for a collector number, e.g. `C01-` for collector 1.
String collectorParticipantPrefix(int collectorNumber) {
  if (collectorNumber < 1) {
    throw ArgumentError.value(collectorNumber, 'collectorNumber');
  }
  return 'C${collectorNumber.toString().padLeft(2, '0')}-';
}

/// Extracts the collector number from a collector-scoped ID, or null if legacy.
int? extractCollectorNumberFromStudyId(String studyId) {
  final normalized = normalizeParticipantStudyId(studyId);
  if (normalized == null) return null;
  final match = _collectorScopedRegex.firstMatch(normalized);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
