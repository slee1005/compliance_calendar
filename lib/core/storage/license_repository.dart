import '../../shared/models/payload.dart';
import 'cache_models.dart';

/// Encrypted local cache and transactional outbox; performs no network calls.
abstract interface class LicenseRepository {
  /// Atomically caches a payload, queues its snapshot, and appends an audit row.
  /// With expectedRevision, zero means new; a mismatch changes nothing.
  Future<CachedLicense> upsert(LicensePayload payload, {int? expectedRevision});

  /// One transaction, at most 1000 unique records; failure rolls back the batch.
  Future<void> upsertAll(List<LicensePayload> payloads);

  /// Returns a row including its ciphertext; tombstones are opt-in.
  Future<CachedLicense?> find(String id, {bool includeDeleted = false});

  /// Lists active records by expiration date then ID with an optional filter.
  Future<List<CachedLicense>> list({
    LicenseFilter filter = const LicenseFilter(),
  });

  /// Creates an idempotent tombstone and queued delete, retaining event mappings.
  Future<bool> softDelete(String id, {int? expectedRevision});

  /// Reads due immutable queue snapshots in insertion order.
  Future<List<PendingChange>> pendingChanges({DateTime? asOf, int limit = 100});

  /// Consumes only the exact revision sent; a newer edit remains pending.
  Future<bool> acknowledgeChange(String id, int revision);

  /// Backs off only the exact failed revision, with no raw backend error content.
  Future<bool> deferChange(
    String id,
    int revision,
    ChangeFailure reason, {
    DateTime? now,
  });

  /// Stores event identifiers without modifying pending local changes.
  Future<void> saveEventMapping(CalendarEventMapping mapping);

  /// Returns event identifiers even for soft-deleted records.
  Future<CalendarEventMapping?> eventMapping(String id);

  /// Stores a typed sync reference inside SQLCipher, never an OAuth token.
  Future<void> saveCalendarRef(CalendarRef reference);

  /// Reads the current account's encrypted sync reference.
  Future<CalendarRef?> calendarRef();

  /// Stores only supported app settings inside SQLCipher.
  Future<void> saveSettings(CacheSettings settings);

  /// Returns persisted settings or the planner defaults.
  Future<CacheSettings> settings();

  /// Reads append-only, value-free local mutation history in sequence order.
  Future<List<AuditEntry>> auditEntries({
    int afterSequence = 0,
    int limit = 1000,
  });

  /// Returns redacted query-plan descriptions for index validation.
  Future<List<String>> explainFilter(LicenseFilter filter);
}
