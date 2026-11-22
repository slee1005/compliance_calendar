import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:license_manager/core/crypto/field_cipher.dart';
import 'package:license_manager/core/storage/cache_models.dart';
import 'package:license_manager/core/storage/db.dart';
import 'package:license_manager/shared/models/license_category.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/storage_support.dart';

Matcher failure(StorageErrorCode code) =>
    throwsA(isA<StorageException>().having((e) => e.code, 'code', code));

void main() {
  late StorageHarness h;
  setUp(() async {
    h = StorageHarness();
    await h.initialize();
  });
  tearDown(() async => h.dispose());

  test(
    'upsert persists ciphertext, revisions, and audit in one transaction',
    () async {
      final cipher = FieldCipher(h.keys);
      final license = storageLicense(1, number: 'MEMORY-ONLY-NUMBER');
      final payload = await cipher.encryptPayload(license);
      final first = await h.db.licenses.upsert(payload, expectedRevision: 0);
      expect(first.revision, 1);
      expect(first.license.licenseNumber, isNull);
      expect(
        await cipher.decrypt(
          first.payload.encryptedLicenseNumber,
          license: first.license,
        ),
        'MEMORY-ONLY-NUMBER',
      );
      await h.db.licenses.upsert(payload, expectedRevision: 1);
      expect((await h.db.licenses.find(license.id))!.revision, 2);
      final audit = await h.db.licenses.auditEntries();
      expect(audit.length, 2);
      expect(audit.first.previousHash, isNull);
      expect(
        audit.last.previousHash ==
            sha256.convert(utf8.encode(jsonEncode(payload.toMap()))).toString(),
        isTrue,
      );
      expect((await h.db.licenses.pendingChanges()).single.revision, 2);
      await h.db.checkIntegrity();
    },
  );

  test(
    'stale revision rejects without cache, queue, or audit changes',
    () async {
      await h.db.licenses.upsert(storagePayload(1));
      await expectLater(
        h.db.licenses.upsert(
          storagePayload(1, name: 'Changed alias'),
          expectedRevision: 0,
        ),
        failure(StorageErrorCode.revisionConflict),
      );
      expect((await h.db.licenses.find(storageId(1)))!.revision, 1);
      expect((await h.db.licenses.auditEntries()).length, 1);
      expect((await h.db.licenses.pendingChanges()).single.revision, 1);
    },
  );

  test(
    'soft delete is idempotent, keeps mappings, and prevents resurrection',
    () async {
      final repo = h.db.licenses;
      await repo.upsert(storagePayload(1));
      await repo.saveEventMapping(
        CalendarEventMapping(
          licenseId: storageId(1),
          masterEventId: 'example-master',
          preparationEventId: 'example-d30',
        ),
      );
      expect(await repo.softDelete(storageId(1), expectedRevision: 1), isTrue);
      expect(await repo.softDelete(storageId(1)), isFalse);
      expect(await repo.softDelete(storageId(99)), isFalse);
      expect(await repo.find(storageId(1)), isNull);
      expect(await repo.list(), isEmpty);
      final deleted = (await repo.find(storageId(1), includeDeleted: true))!;
      expect(deleted.deletedAt, isNotNull);
      expect(deleted.revision, 2);
      expect(
        (await repo.eventMapping(storageId(1)))!.preparationEventId,
        'example-d30',
      );
      expect(
        (await repo.pendingChanges()).single.operation,
        ChangeOperation.delete,
      );
      expect((await repo.pendingChanges()).single.payload, isNull);
      await expectLater(
        repo.upsert(storagePayload(1)),
        failure(StorageErrorCode.revisionConflict),
      );
      expect((await repo.auditEntries()).last.action, AuditAction.softDelete);
    },
  );

  test(
    'batch rollback includes earlier writes, queue rows and audit',
    () async {
      final repo = h.db.licenses;
      await repo.upsert(storagePayload(2));
      await repo.softDelete(storageId(2));
      await expectLater(
        repo.upsertAll([storagePayload(1), storagePayload(2)]),
        failure(StorageErrorCode.revisionConflict),
      );
      expect(await repo.find(storageId(1)), isNull);
      expect((await repo.auditEntries()).length, 2);
      expect((await repo.pendingChanges()).length, 1);
      await expectLater(
        repo.upsertAll([storagePayload(3), storagePayload(3)]),
        failure(StorageErrorCode.invalidRequest),
      );
      await expectLater(
        repo.upsertAll(List.generate(1001, storagePayload)),
        failure(StorageErrorCode.invalidRequest),
      );
    },
  );

  test('all planner status boundaries use indexed date ranges and advance with today', () async {
    final today = DateTime.utc(2026, 11, 21);
    const days = [-1, 0, 7, 8, 30, 31, 90, 91];
    await h.db.licenses.upsertAll([
      for (var i = 0; i < days.length; i++) storagePayload(i, days: days[i]),
    ]);
    const counts = {
      LicenseStatus.expired: 1,
      LicenseStatus.critical: 2,
      LicenseStatus.urgent: 2,
      LicenseStatus.upcoming: 2,
      LicenseStatus.normal: 1,
    };
    for (final status in LicenseStatus.values) {
      final rows = await h.db.licenses.list(
        filter: LicenseFilter(status: status, today: today),
      );
      expect(rows.length, counts[status]);
      expect(rows.every((r) => r.statusAt(today) == status), isTrue);
      final plan = await h.db.licenses.explainFilter(
        LicenseFilter(status: status, today: today),
      );
      expect(plan.join(' ').contains('idx_license_status_expiry'), isTrue);
    }
    expect(
      (await h.db.licenses.list(
        filter: LicenseFilter(
          status: LicenseStatus.expired,
          today: today.add(const Duration(days: 1)),
        ),
      )).length,
      2,
    );
    await expectLater(
      h.db.licenses.list(
        filter: const LicenseFilter(status: LicenseStatus.expired),
      ),
      failure(StorageErrorCode.invalidRequest),
    );
  });

  test('status filters preserve supported date limits without overflowing the wire schema', () async {
    await h.db.licenses.upsert(storagePayload(1));
    for (final today in [DateTime.utc(1), DateTime.utc(9999, 12, 31)]) {
      final counts = <LicenseStatus, int>{};
      for (final status in LicenseStatus.values) {
        counts[status] = (await h.db.licenses.list(
          filter: LicenseFilter(status: status, today: today),
        )).length;
      }
      expect(counts.values.reduce((a, b) => a + b), 1);
      expect(
        counts[today.year == 1 ? LicenseStatus.normal : LicenseStatus.expired],
        1,
      );
    }
  });

  test('category/type/holder filters, literal search, stable ordering and pagination', () async {
    final repo = h.db.licenses;
    await repo.upsertAll([
      storagePayload(
        1,
        days: 1,
        name: '100%_Example',
        category: LicenseCategory.insurance,
        type: 'Insurance',
      ),
      storagePayload(
        2,
        days: 0,
        category: LicenseCategory.insurance,
        type: 'Insurance',
        holderType: 'business',
      ),
      storagePayload(3, days: 1, name: "O'Example", type: 'Permit'),
    ]);
    expect(
      (await repo.list(
        filter: const LicenseFilter(category: LicenseCategory.insurance),
      )).length,
      2,
    );
    expect(
      (await repo.list(
        filter: const LicenseFilter(
          licenseType: 'Insurance',
          holderType: 'business',
        ),
      )).single.license.id,
      storageId(2),
    );
    expect(
      (await repo.list(filter: const LicenseFilter(search: '%_')))
          .single
          .license
          .id,
      storageId(1),
    );
    expect(
      await repo.list(filter: const LicenseFilter(search: "' OR 1=1 --")),
      isEmpty,
    );
    expect(
      (await repo.list(filter: const LicenseFilter(search: "o'example")))
          .single
          .license
          .id,
      storageId(3),
    );
    expect(
      (await repo.list(filter: const LicenseFilter(limit: 1, offset: 1)))
          .single
          .license
          .id,
      storageId(1),
    );
    for (final filter in [
      const LicenseFilter(limit: 0),
      const LicenseFilter(limit: 1001),
      const LicenseFilter(offset: -1),
      const LicenseFilter(holderType: 'unknown'),
    ]) {
      await expectLater(
        repo.list(filter: filter),
        failure(StorageErrorCode.invalidRequest),
      );
    }
    for (final filter in [
      const LicenseFilter(category: LicenseCategory.insurance),
      const LicenseFilter(licenseType: 'Insurance'),
    ]) {
      expect(
        (await repo.explainFilter(filter))
            .join(' ')
            .contains(
              filter.category != null
                  ? 'idx_license_category_expiry'
                  : 'idx_license_type_expiry',
            ),
        isTrue,
      );
    }
  });

  test(
    'in-flight acknowledgment and failure cannot consume or delay newer edits',
    () async {
      final repo = h.db.licenses;
      await repo.upsert(storagePayload(1));
      final old = (await repo.pendingChanges()).single;
      await repo.upsert(storagePayload(1, name: 'New fictional alias'));
      expect(old.payload!.toLicense().holderName, 'T4-FICTIONAL-HOLDER-1');
      expect(
        await repo.acknowledgeChange(old.licenseId, old.revision),
        isFalse,
      );
      expect(
        await repo.deferChange(
          old.licenseId,
          old.revision,
          ChangeFailure.offline,
        ),
        isFalse,
      );
      final latest = (await repo.pendingChanges()).single;
      expect(latest.revision, 2);
      expect(latest.attempts, 0);
      expect(
        await repo.acknowledgeChange(latest.licenseId, latest.revision),
        isTrue,
      );
      expect(await repo.pendingChanges(), isEmpty);
      expect(await repo.find(storageId(1)), isNotNull);
    },
  );

  test(
    'retry backoff is persisted, bounded, and reset by a new revision',
    () async {
      final repo = h.db.licenses;
      final now = DateTime.utc(2026, 11, 21);
      await repo.upsert(storagePayload(1));
      expect(
        await repo.deferChange(
          storageId(1),
          1,
          ChangeFailure.rateLimited,
          now: now,
        ),
        isTrue,
      );
      expect(await repo.pendingChanges(asOf: now), isEmpty);
      var due = (await repo.pendingChanges(
        asOf: now.add(const Duration(seconds: 30)),
      )).single;
      expect(due.attempts, 1);
      expect(due.lastFailure, ChangeFailure.rateLimited);
      for (var i = 0; i < 15; i++) {
        await repo.deferChange(
          storageId(1),
          1,
          ChangeFailure.offline,
          now: now,
        );
      }
      due = (await repo.pendingChanges(asOf: now.add(const Duration(days: 1))))
          .single;
      expect(
        due.nextAttemptAt.difference(now).inSeconds,
        lessThanOrEqualTo(86400),
      );
      await repo.upsert(storagePayload(1));
      due = (await repo.pendingChanges(asOf: now)).single;
      expect(due.attempts, 0);
      expect(due.lastFailure, isNull);
    },
  );

  test(
    'queue/settings/ref/mappings/audit survive worker close and reopen',
    () async {
      final repo = h.db.licenses;
      await repo.upsert(storagePayload(1));
      await repo.saveSettings(
        CacheSettings(
          displayName: 'Example team',
          maskNames: false,
          quietStartHour: 22,
          reminderDays: [90, 30, 7, 1],
        ),
      );
      await repo.saveCalendarRef(
        CalendarRef(
          calendarId: 'example-calendar',
          accountEmail: 'example.invalid@example.invalid',
          syncCursor: 'NON-AUTH-SYNC-CURSOR',
          lastSyncedAt: DateTime.utc(2026),
        ),
      );
      await repo.saveEventMapping(
        CalendarEventMapping(
          licenseId: storageId(1),
          masterEventId: 'example-event',
          etag: 'example-etag',
        ),
      );
      await h.db.close();
      h.db = await ComplianceDatabase.open(path: h.path, key: h.key);
      expect((await h.db.licenses.pendingChanges()).length, 1);
      expect((await h.db.licenses.settings()).maskNames, isFalse);
      expect((await h.db.licenses.settings()).reminderDays, [90, 30, 7, 1]);
      expect(
        (await h.db.licenses.calendarRef())!.syncCursor,
        'NON-AUTH-SYNC-CURSOR',
      );
      expect(
        (await h.db.licenses.eventMapping(storageId(1)))!.etag,
        'example-etag',
      );
      expect((await h.db.licenses.auditEntries()).length, 1);
      await expectLater(repo.list(), failure(StorageErrorCode.closed));
    },
  );

  test('invalid settings and event mappings change nothing; defaults are not persisted', () async {
    expect((await h.db.licenses.settings()).reminderDays, [30, 7, 1]);
    for (final settings in [
      CacheSettings(quietStartHour: 24),
      CacheSettings(reminderDays: []),
      CacheSettings(reminderDays: [7, 7]),
      CacheSettings(reminderDays: [0]),
    ]) {
      await expectLater(
        h.db.licenses.saveSettings(settings),
        failure(StorageErrorCode.invalidRequest),
      );
    }
    expect((await h.db.licenses.settings()).quietStartHour, 21);
    await expectLater(
      h.db.licenses.saveEventMapping(
        CalendarEventMapping(licenseId: storageId(1), masterEventId: 'example'),
      ),
      failure(StorageErrorCode.invalidRequest),
    );
    await expectLater(
      h.db.licenses.find('PRIVATE-INVALID-ID'),
      failure(StorageErrorCode.invalidRequest),
    );
    expect(
      const StorageException(StorageErrorCode.invalidRequest)
          .toString()
          .contains('PRIVATE'),
      isFalse,
    );
  });

  test(
    'DB/WAL have no plaintext holder/number and audit triggers reject mutation',
    () async {
      final payload = await FieldCipher(h.keys)
          .encryptPayload(storageLicense(1, number: 'MEMORY-ONLY-NUMBER'));
      await h.db.licenses.upsert(payload);
      for (final file
          in await h.directory
              .list()
              .where((f) => f is File)
              .cast<File>()
              .toList()) {
        final bytes = await file.readAsBytes();
        final decoded = latin1.decode(bytes);
        expect(decoded.contains('T4-FICTIONAL-HOLDER-1'), isFalse);
        expect(decoded.contains('MEMORY-ONLY-NUMBER'), isFalse);
      }
      await h.db.checkpoint();
      await h.db.close();
      final bytes = await File(h.path).readAsBytes();
      expect(
        latin1.decode(bytes.take(16).toList()).startsWith('SQLite format 3'),
        isFalse,
      );
      final raw = sqlite3.open(h.path);
      try {
        raw.execute('PRAGMA cipher_log_level=NONE');
        expect(
          () => raw.select('SELECT count(*) FROM sqlite_master'),
          throwsA(isA<SqliteException>()),
        );
        raw.execute('PRAGMA key="x\'${h.key.hex}\'"');
        expect(
          () => raw.execute('UPDATE audit_local SET previous_hash=NULL'),
          throwsA(isA<SqliteException>()),
        );
        expect(
          () => raw.execute('DELETE FROM audit_local'),
          throwsA(isA<SqliteException>()),
        );
      } finally {
        raw.close();
      }
    },
  );
}
