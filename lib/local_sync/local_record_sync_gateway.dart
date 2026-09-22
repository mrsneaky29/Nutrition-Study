/// Boundary for optionally mirroring locally collected records to a LAN service.
///
/// The collector UI depends on this interface rather than HTTP so the local
/// service can be removed or replaced without changing the collection flow.
abstract interface class LocalRecordSyncGateway {
  Future<LocalRecordSyncResult> sendRecord(Map<String, Object?> record);
}

enum LocalRecordSyncResult { synced, pending, failed }
