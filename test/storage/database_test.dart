import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:license_manager/core/crypto/key_derivation.dart';
import 'package:license_manager/core/crypto/key_manager.dart';
import 'package:license_manager/core/crypto/key_store.dart';
import 'package:license_manager/core/storage/cache_models.dart';
import 'package:license_manager/core/storage/db.dart';
import 'package:license_manager/core/storage/local_cache.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/crypto_support.dart';
import '../support/storage_support.dart';

Matcher failure(StorageErrorCode code) =>
    throwsA(isA<StorageException>().having((e) => e.code, 'code', code));

final class _ScheduledStore implements KeyStore {
  _ScheduledStore(this.delegate);
  final KeyStore delegate;
  int active = 0;
  int maximum = 0;
  @override
  Future<String?> read(String key) => delegate.read(key);
  @override
  Future<void> write(String key, String value) => delegate.write(key, value);
  @override
  Future<void> delete(String key) => delegate.delete(key);
  @override
  Future<T> withExclusiveAccess<T>(Future<T> Function() action) async {
    active++;
    if (active > maximum) maximum = active;
    try {
      // Deliberately yields, modelling OS calls whose file locks cannot
      // serialize asynchronous clients inside one POSIX process.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      return await action();
    } finally {
      active--;
    }
  }
}

void main() {
  late StorageHarness h;
  setUp(() async {
    h = StorageHarness();
    await h.initialize();
  });
  tearDown(() => h.dispose());

  test('missing file is not created by an ordinary open', () async {
    final path = '${h.directory.path}/missing.db';
    await expectLater(
      ComplianceDatabase.open(path: path, key: h.key),
      failure(StorageErrorCode.cannotOpen),
    );
    expect(await File(path).exists(), isFalse);
    for (final path in [':memory:', 'relative.db', '']) {
      await expectLater(
        ComplianceDatabase.open(path: path, key: h.key, createIfMissing: true),
        failure(StorageErrorCode.invalidRequest),
      );
    }
  });
  test(
    'wrong key fails without replacing or modifying an existing encrypted file',
    () async {
      await h.db.licenses.upsert(storagePayload(1));
      await h.db.close();
      final before = sha256.convert(await File(h.path).readAsBytes());
      final other = TestKeyStore();
      final manager = KeyManager(other);
      (await manager.initialize()).destroy();
      final key = await KeyDerivation.databaseKey(manager, keyVersion: 1);
      try {
        await expectLater(
          ComplianceDatabase.open(
            path: h.path,
            key: key,
            createIfMissing: true,
          ),
          failure(StorageErrorCode.cannotOpen),
        );
        expect(
          sha256.convert(await File(h.path).readAsBytes()) == before,
          isTrue,
        );
      } finally {
        key.destroy();
        other.values.clear();
      }
      h.db = await ComplianceDatabase.open(path: h.path, key: h.key);
      expect((await h.db.licenses.list()).length, 1);
    },
  );
  test(
    'corruption is not deleted, regenerated, or treated as an empty cache',
    () async {
      await h.db.licenses.upsert(storagePayload(1));
      await h.db.close();
      final file = File(h.path);
      final bytes = await file.readAsBytes();
      bytes[100] ^= 1;
      await file.writeAsBytes(bytes, flush: true);
      final before = sha256.convert(bytes);
      await expectLater(
        ComplianceDatabase.open(
          path: h.path,
          key: h.key,
          createIfMissing: true,
        ),
        failure(StorageErrorCode.cannotOpen),
      );
      expect(sha256.convert(await file.readAsBytes()) == before, isTrue);
    },
  );
  test('future schema and foreign encrypted database are preserved', () async {
    await h.db.close();
    final raw = sqlite3.open(h.path);
    try {
      raw.execute('PRAGMA cipher_log_level=NONE');
      raw.execute('PRAGMA key="x\'${h.key.hex}\'"');
      raw.userVersion = 2;
    } finally {
      raw.close();
    }
    final before = sha256.convert(await File(h.path).readAsBytes());
    await expectLater(
      ComplianceDatabase.open(path: h.path, key: h.key),
      failure(StorageErrorCode.unsupportedSchema),
    );
    expect(sha256.convert(await File(h.path).readAsBytes()) == before, isTrue);
  });
  test(
    'close is idempotent and all subsequent work fails explicitly',
    () async {
      await h.db.close();
      await h.db.close();
      await expectLater(
        h.db.checkIntegrity(),
        failure(StorageErrorCode.closed),
      );
      await expectLater(
        h.db.licenses.upsert(storagePayload(1)),
        failure(StorageErrorCode.closed),
      );
    },
  );
  test(
    'concurrent connections serialize writes and compare revisions',
    () async {
      final second = await ComplianceDatabase.open(path: h.path, key: h.key);
      try {
        await h.db.licenses.upsert(storagePayload(1));
        final results = await Future.wait([
          h.db.licenses
              .upsert(
                storagePayload(1, name: 'First edit'),
                expectedRevision: 1,
              )
              .then<Object>((r) => r)
              .catchError((Object e) => e),
          second.licenses
              .upsert(
                storagePayload(1, name: 'Second edit'),
                expectedRevision: 1,
              )
              .then<Object>((r) => r)
              .catchError((Object e) => e),
        ]);
        expect(results.whereType<CachedLicense>().length, 1);
        expect(
          results.whereType<StorageException>().single.code,
          StorageErrorCode.revisionConflict,
        );
        expect((await second.licenses.find(storageId(1)))!.revision, 2);
      } finally {
        await second.close();
      }
    },
  );
  test(
    'secure cache binding pins DB key version across organization rotation',
    () async {
      final id = storageId(91);
      var cache = await LocalCache.open(
        secureStore: h.store,
        cacheId: id,
        directory: h.directory,
        createIfMissing: true,
      );
      try {
        await cache.licenses.upsert(storagePayload(1));
      } finally {
        await cache.close();
      }
      expect(h.store.values[LocalCache.keyVersionSlot(id)], '1');
      (await h.keys.rotate()).destroy();
      cache = await LocalCache.open(
        secureStore: h.store,
        cacheId: id,
        directory: h.directory,
      );
      try {
        expect((await cache.licenses.list()).length, 1);
      } finally {
        await cache.close();
      }
      expect(h.store.values[LocalCache.keyVersionSlot(id)], '1');
      h.store.values.remove(LocalCache.keyVersionSlot(id));
      await expectLater(
        LocalCache.open(
          secureStore: h.store,
          cacheId: id,
          directory: h.directory,
          createIfMissing: true,
        ),
        failure(StorageErrorCode.missingKeyBinding),
      );
    },
  );
  test('concurrent first opens select one durable cache key binding', () async {
    final store = _ScheduledStore(h.store);
    final caches = await Future.wait(
      List.generate(
        8,
        (_) => LocalCache.open(
          secureStore: store,
          cacheId: storageId(95),
          directory: h.directory,
          createIfMissing: true,
        ),
      ),
    );
    try {
      expect(store.maximum, 1);
      expect(h.store.values[LocalCache.keyVersionSlot(storageId(95))], '1');
      await caches.first.licenses.upsert(storagePayload(1));
      for (final cache in caches) {
        expect((await cache.licenses.list()).length, 1);
      }
    } finally {
      for (final cache in caches) {
        await cache.close();
      }
    }
  });

  test('no automatic organization key creation or binding repair', () async {
    final store = TestKeyStore();
    final id = storageId(92);
    await expectLater(
      LocalCache.open(
        secureStore: store,
        cacheId: id,
        directory: h.directory,
        createIfMissing: true,
      ),
      throwsA(
        isA<KeyManagementException>().having(
          (e) => e.code,
          'code',
          KeyErrorCode.missingKey,
        ),
      ),
    );
    expect(store.values, isEmpty);
    expect(await File('${h.directory.path}/$id.db').exists(), isFalse);
    for (final binding in ['0', '01', '-1', '2147483648', '1\n']) {
      h.store.values[LocalCache.keyVersionSlot(id)] = binding;
      await expectLater(
        LocalCache.open(
          secureStore: h.store,
          cacheId: id,
          directory: h.directory,
          createIfMissing: true,
        ),
        failure(StorageErrorCode.missingKeyBinding),
      );
      expect(h.store.values[LocalCache.keyVersionSlot(id)], binding);
    }
  });
  test(
    'different cache UUIDs isolate records and Calendar account references',
    () async {
      final one = await LocalCache.open(
        secureStore: h.store,
        cacheId: storageId(93),
        directory: h.directory,
        createIfMissing: true,
      );
      final two = await LocalCache.open(
        secureStore: h.store,
        cacheId: storageId(94),
        directory: h.directory,
        createIfMissing: true,
      );
      try {
        await one.licenses.upsert(storagePayload(1));
        expect(await two.licenses.list(), isEmpty);
        await one.licenses.saveCalendarRef(
          const CalendarRef(
            calendarId: 'example-one',
            accountEmail: 'one@example.invalid',
          ),
        );
        expect(await two.licenses.calendarRef(), isNull);
        await expectLater(
          one.licenses.saveCalendarRef(
            const CalendarRef(
              calendarId: 'example-two',
              accountEmail: 'two@example.invalid',
            ),
          ),
          failure(StorageErrorCode.revisionConflict),
        );
      } finally {
        await one.close();
        await two.close();
      }
    },
  );
  test('plain or unrelated data is not imported or overwritten', () async {
    final path = '${h.directory.path}/unrelated.db';
    const text = 'UNRELATED-NONCUSTOMER-DATA';
    await File(path).writeAsString(text);
    await expectLater(
      ComplianceDatabase.open(path: path, key: h.key, createIfMissing: true),
      failure(StorageErrorCode.cannotOpen),
    );
    expect(await File(path).readAsString(), text);
    expect(
      latin1.decode(await File(path).readAsBytes()).contains(text),
      isTrue,
    );
  });
}
