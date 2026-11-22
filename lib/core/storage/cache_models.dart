import '../../shared/models/license.dart';
import '../../shared/models/license_category.dart';
import '../../shared/models/license_validation.dart';
import '../../shared/models/payload.dart';

/// Value-free failures; database SQL, paths, parameters and keys are never exposed.
enum StorageErrorCode {
  /// Required SQLCipher encryption is unavailable.
  encryptionUnavailable,

  /// The key, file or operating system prevented opening the cache.
  cannotOpen,

  /// A newer or foreign database must not be modified.
  unsupportedSchema,

  /// Stored data violates this application's contract.
  corruptData,

  /// The worker was closed or terminated.
  closed,

  /// An input is outside the supported contract.
  invalidRequest,

  /// An optimistic update no longer matches the cached revision.
  revisionConflict,

  /// An operation could not be committed; retry or inspect local state.
  operationFailed,

  /// An existing cache has no secure key-version binding.
  missingKeyBinding,
}

/// Sanitized failure safe to translate into user-facing recovery guidance.
final class StorageException implements Exception {
  /// Contains only a non-sensitive reason.
  const StorageException(this.code);

  /// Reason for the failed operation.
  final StorageErrorCode code;
  @override
  String toString() => 'StorageException(${code.name})';
}

/// Persisted records have dates; required-but-missing credentials belong to T14.
enum LicenseStatus {
  /// Expiration was before today.
  expired,

  /// Expires today through seven days from today.
  critical,

  /// Expires in eight through thirty days.
  urgent,

  /// Expires in thirty-one through ninety days.
  upcoming,

  /// Expires more than ninety days from today.
  normal;

  /// Uses date-only UTC values, independently of elapsed hours and DST.
  static LicenseStatus at(DateTime expiration, DateTime today) {
    LicenseDate.validate(today, field: LicenseField.expirationDate);
    LicenseDate.validate(expiration, field: LicenseField.expirationDate);
    final days = expiration.difference(today).inDays;
    return switch (days) {
      < 0 => expired,
      <= 7 => critical,
      <= 30 => urgent,
      <= 90 => upcoming,
      _ => normal,
    };
  }
}

/// A cache row retaining its number ciphertext even when decryption is unavailable.
final class CachedLicense {
  /// Creates a revisioned immutable cache view.
  const CachedLicense({
    required this.payload,
    required this.revision,
    required this.updatedAt,
    this.deletedAt,
  });

  /// Metadata and encrypted optional number; no decrypted number is retained.
  final LicensePayload payload;

  /// Monotonically increasing local revision for compare-and-swap updates.
  final int revision;

  /// UTC time of the last local mutation.
  final DateTime updatedAt;

  /// UTC tombstone time; null for active records.
  final DateTime? deletedAt;

  /// Date-validated metadata with no plaintext number.
  License get license => payload.toLicense();

  /// Calculates the status at the supplied date, never stores a stale status.
  LicenseStatus statusAt(DateTime today) =>
      LicenseStatus.at(license.expirationDate, today);
  @override
  String toString() => 'CachedLicense(revision: $revision, redacted)';
}

/// An indexed filter; text matching is literal and is never interpolated into SQL.
final class LicenseFilter {
  /// Today must be date-only UTC when filtering by status.
  const LicenseFilter({
    this.status,
    this.today,
    this.category,
    this.licenseType,
    this.holderType,
    this.search,
    this.expiresFrom,
    this.expiresThrough,
    this.includeDeleted = false,
    this.limit = 1000,
    this.offset = 0,
  });

  /// Optional planner status range.
  final LicenseStatus? status;

  /// Date on which the status is evaluated, required with status.
  final DateTime? today;

  /// Optional category equality.
  final LicenseCategory? category;

  /// Optional exact credential type label.
  final String? licenseType;

  /// Optional staff/business equality.
  final String? holderType;

  /// Literal substring across holder/type/issuer; no SQL LIKE metacharacters.
  final String? search;

  /// Inclusive date-only UTC lower bound.
  final DateTime? expiresFrom;

  /// Inclusive date-only UTC upper bound.
  final DateTime? expiresThrough;

  /// Includes tombstones for explicit diagnostics/sync only.
  final bool includeDeleted;

  /// At most 1000 rows per request.
  final int limit;

  /// Number of sorted rows to skip.
  final int offset;
}

/// Kind of idempotent local write awaiting Calendar integration.
enum ChangeOperation {
  /// Write the encrypted payload.
  upsert,

  /// Delete remote events; retain the local tombstone.
  delete,
}

/// Allowed retry reasons; raw HTTP responses and backend messages are forbidden.
enum ChangeFailure {
  /// Device is offline.
  offline,

  /// Reauthentication is required.
  unauthorized,

  /// Remote request quota was exceeded.
  rateLimited,

  /// Remote state changed concurrently.
  conflict,

  /// Remote service could not be reached.
  unavailable,
}

/// A revisioned snapshot: acknowledgments cannot consume a newer local edit.
final class PendingChange {
  /// Builds an immutable pending snapshot.
  const PendingChange({
    required this.licenseId,
    required this.revision,
    required this.operation,
    required this.payload,
    required this.attempts,
    required this.nextAttemptAt,
    this.lastFailure,
  });

  /// Correlation ID; remote mappings are kept separately.
  final String licenseId;

  /// Revision to supply to acknowledge/defer.
  final int revision;

  /// The intended Calendar operation; no request has been sent yet.
  final ChangeOperation operation;

  /// Encrypted payload snapshot for upsert; null for deletion.
  final LicensePayload? payload;

  /// Recorded failed attempts for this revision.
  final int attempts;

  /// UTC due time for the next attempt.
  final DateTime nextAttemptAt;

  /// Whitelisted failure code, without remote message content.
  final ChangeFailure? lastFailure;
  @override
  String toString() => 'PendingChange(revision: $revision, redacted)';
}

/// Metadata needed to correlate both Calendar events, including after deletion.
final class CalendarEventMapping {
  /// Creates an event mapping; these are identifiers, never OAuth credentials.
  const CalendarEventMapping({
    required this.licenseId,
    required this.masterEventId,
    this.preparationEventId,
    this.etag,
  });

  /// UUID of the corresponding cached record.
  final String licenseId;

  /// Main expiry event ID.
  final String masterEventId;

  /// D-30 preparation event ID, if created.
  final String? preparationEventId;

  /// Last known remote etag for a later conditional write.
  final String? etag;
  @override
  String toString() => 'CalendarEventMapping(redacted)';
}

/// Encrypted local synchronization reference; contains no OAuth access/refresh token.
final class CalendarRef {
  /// A cursor is a Calendar synchronization cursor, not an authentication secret.
  const CalendarRef({
    required this.calendarId,
    required this.accountEmail,
    this.syncCursor,
    this.lastSyncedAt,
  });

  /// App-created Calendar identifier.
  final String calendarId;

  /// Account correlation metadata, inside SQLCipher only.
  final String accountEmail;

  /// Optional incremental-sync cursor.
  final String? syncCursor;

  /// Last successfully applied synchronization time in UTC.
  final DateTime? lastSyncedAt;
  @override
  String toString() => 'CalendarRef(redacted)';
}

/// Typed settings prevent arbitrary credential/blob storage in the cache.
final class CacheSettings {
  /// Uses the planner's default quiet hours and reminder stages.
  CacheSettings({
    this.displayName = '',
    this.maskNames = true,
    this.quietStartHour = 21,
    this.quietEndHour = 7,
    List<int> reminderDays = const [30, 7, 1],
  }) : reminderDays = List.unmodifiable(reminderDays);

  /// Display name, at most 60 scalars; no document data.
  final String displayName;

  /// Whether the UI should mask names.
  final bool maskNames;

  /// Local quiet-hour start, 0..23.
  final int quietStartHour;

  /// Local quiet-hour end, 0..23.
  final int quietEndHour;

  /// One to five distinct reminder stages, each 1..365 days before expiry.
  final List<int> reminderDays;
  @override
  String toString() => 'CacheSettings(redacted)';
}

/// Append-only local mutation audit action.
enum AuditAction {
  /// Local insert/update.
  upsert,

  /// Local tombstone creation.
  softDelete,
}

/// Audit data contains no previous field values or decrypted number.
final class AuditEntry {
  /// Constructs a safe audit view.
  const AuditEntry({
    required this.sequence,
    required this.occurredAt,
    required this.action,
    required this.licenseId,
    required this.previousHash,
  });

  /// Local ordering sequence.
  final int sequence;

  /// UTC mutation time.
  final DateTime occurredAt;

  /// Allowed action.
  final AuditAction action;

  /// Correlation UUID.
  final String licenseId;

  /// SHA-256 of the previous complete wire payload, or null on first insert.
  final String? previousHash;
  @override
  String toString() => 'AuditEntry(redacted)';
}
