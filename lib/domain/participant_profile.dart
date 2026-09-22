import 'study_configuration.dart';

/// Identifying details collected once for a participant.
class ParticipantProfile {
  ParticipantProfile({
    required String studyId,
    required String name,
    required String indianPhone,
    required ParticipantIdPolicy idPolicy,
  }) : studyId = _requireStudyId(studyId, idPolicy),
       name = normalizeName(name),
       indianPhone = requireIndianPhone(indianPhone);

  final String studyId;
  final String name;

  /// Stored in canonical E.164 form.
  final String indianPhone;

  static String? normalizeIndianPhone(String? value) {
    final compact = (value ?? '').replaceAll(RegExp(r'[\s()-]'), '');
    var local = compact;
    if (local.startsWith('+91')) local = local.substring(3);
    if (local.startsWith('91') && local.length == 12) {
      local = local.substring(2);
    }
    if (local.startsWith('0') && local.length == 11) local = local.substring(1);
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(local)) return null;
    return '+91$local';
  }

  static String _requireStudyId(String value, ParticipantIdPolicy policy) {
    final normalized = policy.normalize(value);
    if (normalized == null) {
      throw ArgumentError.value(value, 'studyId', 'Invalid participant ID.');
    }
    return normalized;
  }

  static String normalizeName(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        'name',
        'A participant name is required.',
      );
    }
    return normalized;
  }

  static String requireIndianPhone(String value) {
    final normalized = normalizeIndianPhone(value);
    if (normalized == null) {
      throw ArgumentError.value(
        value,
        'indianPhone',
        'Invalid Indian mobile number.',
      );
    }
    return normalized;
  }

  Map<String, Object> toFirestoreMap() => {
    'studyId': studyId,
    'name': name,
    'indianPhone': indianPhone,
  };

  Map<String, String> toCsvRow() => {
    'participant_study_id': studyId,
    'participant_name': name,
    'participant_indian_phone': indianPhone,
  };
}
