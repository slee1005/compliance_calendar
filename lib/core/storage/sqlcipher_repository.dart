part of 'db.dart';

final class _SqlCipherLicenseRepository implements LicenseRepository {
  _SqlCipherLicenseRepository(this.db);
  final ComplianceDatabase db;

  @override
  Future<CachedLicense> upsert(
    LicensePayload payload, {
    int? expectedRevision,
  }) async => _cached(
    (await db._request('upsert', {
      'payload': payload.toMap(),
      'expected': expectedRevision,
    })),
  );
  @override
  Future<void> upsertAll(List<LicensePayload> payloads) async =>
      await db._request('batch', {
        'payloads': [for (final p in payloads) p.toMap()],
      });
  @override
  Future<CachedLicense?> find(String id, {bool includeDeleted = false}) async {
    final row = await db._request('find', {
      'id': id,
      'deleted': includeDeleted,
    });
    return row == null ? null : _cached(row);
  }

  @override
  Future<List<CachedLicense>> list({
    LicenseFilter filter = const LicenseFilter(),
  }) async => [
    for (final row in (await db._request('list', _filterMap(filter))) as List)
      _cached(row),
  ];
  @override
  Future<bool> softDelete(String id, {int? expectedRevision}) async =>
      (await db._request('delete', {'id': id, 'expected': expectedRevision}))
          as bool;
  @override
  Future<List<PendingChange>> pendingChanges({
    DateTime? asOf,
    int limit = 100,
  }) async {
    final rows = await db._request('pending', {
      'now': _time(asOf),
      'limit': limit,
    }) as List;
    return List.unmodifiable(
      rows.map((raw) {
        final row = raw as Map;
        return PendingChange(
          licenseId: row['license_id'] as String,
          revision: row['revision'] as int,
          operation: ChangeOperation.values.byName(row['operation'] as String),
          payload: row['payload'] == null ? null : _payload(row['payload']),
          attempts: row['attempts'] as int,
          nextAttemptAt: _date(row['next_attempt_at']),
          lastFailure: row['last_error'] == null
              ? null
              : ChangeFailure.values.byName(row['last_error'] as String),
        );
      }),
    );
  }

  @override
  Future<bool> acknowledgeChange(String id, int revision) async =>
      await db._request('ack', {'id': id, 'revision': revision}) as bool;
  @override
  Future<bool> deferChange(
    String id,
    int revision,
    ChangeFailure reason, {
    DateTime? now,
  }) async => await db._request('defer', {
    'id': id,
    'revision': revision,
    'reason': reason.name,
    'now': _time(now),
  }) as bool;
  @override
  Future<void> saveEventMapping(CalendarEventMapping mapping) async =>
      await db._request('map', {
        'id': mapping.licenseId,
        'master': mapping.masterEventId,
        'preparation': mapping.preparationEventId,
        'etag': mapping.etag,
      });
  @override
  Future<CalendarEventMapping?> eventMapping(String id) async {
    final row = await db._request('getMap', {'id': id}) as Map?;
    return row == null
        ? null
        : CalendarEventMapping(
            licenseId: row['license_id'] as String,
            masterEventId: row['master_event_id'] as String,
            preparationEventId: row['preparation_event_id'] as String?,
            etag: row['etag'] as String?,
          );
  }

  @override
  Future<void> saveCalendarRef(CalendarRef reference) async =>
      await db._request('ref', {
        'calendar': reference.calendarId,
        'email': reference.accountEmail,
        'cursor': reference.syncCursor,
        'synced': reference.lastSyncedAt == null
            ? null
            : _time(reference.lastSyncedAt),
      });
  @override
  Future<CalendarRef?> calendarRef() async {
    final row = await db._request('getRef') as Map?;
    return row == null
        ? null
        : CalendarRef(
            calendarId: row['calendar_id'] as String,
            accountEmail: row['account_email'] as String,
            syncCursor: row['sync_cursor'] as String?,
            lastSyncedAt: row['last_synced_at'] == null
                ? null
                : _date(row['last_synced_at']),
          );
  }

  @override
  Future<void> saveSettings(CacheSettings settings) async =>
      await db._request('settings', {
        'name': settings.displayName,
        'mask': settings.maskNames,
        'start': settings.quietStartHour,
        'end': settings.quietEndHour,
        'days': settings.reminderDays,
      });
  @override
  Future<CacheSettings> settings() async {
    final row = await db._request('getSettings') as Map?;
    return row == null
        ? CacheSettings()
        : CacheSettings(
            displayName: row['display_name'] as String,
            maskNames: row['mask_names'] == 1,
            quietStartHour: row['quiet_start'] as int,
            quietEndHour: row['quiet_end'] as int,
            reminderDays: (jsonDecode(row['reminder_days'] as String) as List)
                .cast<int>(),
          );
  }

  @override
  Future<List<AuditEntry>> auditEntries({
    int afterSequence = 0,
    int limit = 1000,
  }) async => List.unmodifiable(
    (await db._request('audit', {
      'after': afterSequence,
      'limit': limit,
    }) as List).map((raw) {
      final row = raw as Map;
      return AuditEntry(
        sequence: row['sequence'] as int,
        occurredAt: _date(row['occurred_at']),
        action: AuditAction.values.byName(row['action'] as String),
        licenseId: row['license_id'] as String,
        previousHash: row['previous_hash'] as String?,
      );
    }),
  );
  @override
  Future<List<String>> explainFilter(LicenseFilter filter) async =>
      (await db._request('explain', _filterMap(filter)) as List).cast<String>();

  static int _time(DateTime? time) {
    if (time != null && !time.isUtc) {
      throw const StorageException(StorageErrorCode.invalidRequest);
    }
    return (time ?? DateTime.now().toUtc()).microsecondsSinceEpoch;
  }

  static DateTime _date(Object? time) =>
      DateTime.fromMicrosecondsSinceEpoch(time as int, isUtc: true);
  static LicensePayload _payload(Object? encoded) => LicensePayload.fromMap(
    (jsonDecode(encoded as String) as Map).cast<String, Object?>(),
  );
  static CachedLicense _cached(Object? raw) {
    try {
      final row = raw as Map;
      return CachedLicense(
        payload: _payload(row['payload']),
        revision: row['revision'] as int,
        updatedAt: _date(row['updated_at']),
        deletedAt: row['deleted_at'] == null ? null : _date(row['deleted_at']),
      );
    } catch (_) {
      throw const StorageException(StorageErrorCode.corruptData);
    }
  }

  static Map<String, Object?> _filterMap(LicenseFilter filter) {
    String? date(DateTime? value) => value == null
        ? null
        : LicenseDate.format(value, field: LicenseField.expirationDate);
    return {
      'status': filter.status?.name,
      'today': date(filter.today),
      'category': filter.category?.name,
      'type': filter.licenseType,
      'holder': filter.holderType,
      'search': filter.search,
      'from': date(filter.expiresFrom),
      'through': date(filter.expiresThrough),
      'deleted': filter.includeDeleted,
      'limit': filter.limit,
      'offset': filter.offset,
    };
  }
}
