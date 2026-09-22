import '../collector_auth/collector_access.dart';
import '../domain/participant_profile.dart';
import '../domain/visit_record.dart';

/// Exactly one participant identifier may be supplied to a cloud lookup.
class ParticipantLookupQuery {
  const ParticipantLookupQuery._({this.studyId, this.indianPhone})
    : assert((studyId == null) != (indianPhone == null));

  factory ParticipantLookupQuery.byStudyId(String studyId) {
    final normalized = studyId.trim().toUpperCase();
    if (normalized.isEmpty) {
      throw ArgumentError.value(studyId, 'studyId', 'Study ID is required.');
    }
    return ParticipantLookupQuery._(studyId: normalized);
  }

  factory ParticipantLookupQuery.byIndianPhone(String indianPhone) {
    final normalized = ParticipantProfile.normalizeIndianPhone(indianPhone);
    if (normalized == null) {
      throw ArgumentError.value(
        indianPhone,
        'indianPhone',
        'Invalid Indian mobile number.',
      );
    }
    return ParticipantLookupQuery._(indianPhone: normalized);
  }

  final String? studyId;
  final String? indianPhone;
}

/// Data needed to create a participant when no server record is found.
///
/// Study IDs are intentionally not supplied by collectors: the server assigns
/// them inside the same atomic allocation as the first visit number.
class NewParticipantDetails {
  NewParticipantDetails({required this.name, required String indianPhone})
    : indianPhone = ParticipantProfile.requireIndianPhone(indianPhone);

  final String name;
  final String indianPhone;
}

class ParticipantLookupResult {
  const ParticipantLookupResult({
    required this.participant,
    required this.nextVisitNumber,
  }) : assert(nextVisitNumber > 0);

  final ParticipantProfile participant;
  final int nextVisitNumber;
}

/// A server-created reservation for exactly one visit.
///
/// [requestKey] lets the app retry an interrupted allocation without consuming
/// another participant or visit number.
class VisitAllocation {
  const VisitAllocation({
    required this.visitId,
    required this.requestKey,
    required this.participant,
    required this.visitNumber,
  }) : assert(visitId != ''),
       assert(requestKey != ''),
       assert(visitNumber > 0);

  final String visitId;
  final String requestKey;
  final ParticipantProfile participant;
  final int visitNumber;
}

class UploadVisitResult {
  const UploadVisitResult({required this.record, required this.created});

  final VisitRecord record;

  /// False means the server returned the existing idempotent result.
  final bool created;
}

class CloudVisitConflictException implements Exception {
  const CloudVisitConflictException(this.message);

  final String message;

  @override
  String toString() => 'CloudVisitConflictException: $message';
}

/// Collector-facing cloud API. Firebase, REST, or another hosted backend can
/// implement this without changing the collector workflow.
abstract interface class StudyCloudGateway implements CollectorAccessGateway {
  Future<ParticipantLookupResult?> lookupParticipant({
    required CollectorInstallationSession session,
    required ParticipantLookupQuery query,
  });

  /// Atomically resolves an existing participant or creates one, then reserves
  /// its next visit. [requestKey] must be durable on the phone for retries.
  Future<VisitAllocation> allocateVisit({
    required CollectorInstallationSession session,
    required NewParticipantDetails participant,
    required String requestKey,
  });

  /// Creates or updates the cloud copy of a server-allocated visit.
  ///
  /// [idempotencyKey] must be durable on the phone. Repeating it returns the
  /// original result and never creates a second visit.
  Future<UploadVisitResult> uploadVisit({
    required CollectorInstallationSession session,
    required VisitRecord record,
    required String idempotencyKey,
  });

  /// Returns only the history belonging to the valid bound collector device.
  Future<List<VisitRecord>> listCollectorHistory({
    required CollectorInstallationSession session,
  });
}
