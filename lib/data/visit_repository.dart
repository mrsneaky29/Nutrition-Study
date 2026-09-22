import '../domain/authenticated_user.dart';
import '../domain/participant_profile.dart';
import '../domain/visit_record.dart';

abstract class VisitRepository {
  /// Starts the next numbered visit for [participant]. Only collectors may do so.
  Future<VisitRecord> createDraft({
    required AuthenticatedUser actor,
    required ParticipantProfile participant,
    DateTime? now,
  });

  /// Returns a record only when [actor] owns it or is an administrator.
  Future<VisitRecord?> getById(String id, AuthenticatedUser actor);

  /// Collectors see their records; administrators see every record.
  Future<List<VisitRecord>> listVisibleTo(AuthenticatedUser actor);

  /// Saves a collector-owned record. Submission status is retained on edits.
  /// Each save increments its audit-friendly revision and requests re-sync.
  Future<VisitRecord> saveOwnRecord({
    required AuthenticatedUser actor,
    required VisitRecord record,
  });

  /// Saves study data from the standalone administrator workflow.
  ///
  /// The repository preserves immutable record identity, collector ownership,
  /// creation time, and archive state. It supplies the audit timestamp and next
  /// revision rather than trusting values submitted by the admin client.
  Future<VisitRecord> saveAdminRecord({
    required AuthenticatedUser actor,
    required VisitRecord record,
    DateTime? now,
  });

  /// Validates confirmation and transitions a collector-owned draft to submitted.
  Future<VisitRecord> submit({
    required AuthenticatedUser actor,
    required String visitId,
    DateTime? now,
  });

  /// Lets the owning collector update the delivery state without changing content.
  Future<VisitRecord> updateSyncState({
    required AuthenticatedUser actor,
    required String visitId,
    required SyncState syncState,
    DateTime? now,
  });

  /// Archives or restores a visit from the separate administrator workflow.
  /// Archived visits are retained for audit purposes and stay visible to admins.
  Future<VisitRecord> setArchived({
    required AuthenticatedUser actor,
    required String visitId,
    required bool archived,
    DateTime? now,
  });
}
