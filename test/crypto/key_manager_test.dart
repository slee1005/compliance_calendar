import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:license_manager/core/crypto/key_derivation.dart';
import 'package:license_manager/core/crypto/key_manager.dart';
import 'package:license_manager/core/crypto/key_store.dart';
import 'package:license_manager/shared/models/encrypted_license_number.dart';

import '../support/crypto_support.dart';

Matcher _error(KeyErrorCode code) => throwsA(
  isA<KeyManagementException>().having((error) => error.code, 'code', code),
);

void main() {
  late TestKeyStore store;
  late KeyManager manager;
  setUp(() {
    store = TestKeyStore();
    manager = KeyManager(store);
  });
  tearDown(() => store.values.clear());

  test(
    'initialization generates 32 bytes and reads the same durable v1 key',
    () async {
      final created = await manager.initialize();
      final loaded = await KeyManager(store).loadCurrent();
      try {
        expect(created.version, 1);
        expect((await created.secretKey.extractBytes()).length, 32);
        expect(
          (await created.secretKey.extract()) ==
              await loaded.secretKey.extract(),
          isTrue,
        );
        expect(store.values[KeyManager.activeVersionSlot], '1');
        expect(store.writes, 2);
        expect(
          created.toString().contains(store.values[KeyManager.slot(1)]!),
          isFalse,
        );
      } finally {
        created.destroy();
        loaded.destroy();
      }
    },
  );

  test(
    'parallel initialization across managers does not replace a key',
    () async {
      final keys = await Future.wait(
        List.generate(20, (_) => KeyManager(store).initialize()),
      );
      try {
        final reference = await keys.first.secretKey.extract();
        for (final key in keys) {
          expect((await key.secretKey.extract()) == reference, isTrue);
        }
        expect(store.writes, 2);
      } finally {
        for (final key in keys) {
          key.destroy();
        }
      }
    },
  );

  test('ordinary reads never initialize missing keys', () async {
    await expectLater(manager.loadCurrent(), _error(KeyErrorCode.missingKey));
    await expectLater(manager.loadVersion(1), _error(KeyErrorCode.missingKey));
    await expectLater(manager.rotate(), _error(KeyErrorCode.missingKey));
    expect(store.writes, 0);
  });

  test('a missing active slot is not regenerated or overwritten', () async {
    (await manager.initialize()).destroy();
    store.values.remove(KeyManager.slot(1));
    final writes = store.writes;
    await expectLater(manager.loadCurrent(), _error(KeyErrorCode.missingKey));
    await expectLater(manager.initialize(), _error(KeyErrorCode.missingKey));
    expect(store.writes, writes);
  });

  test('malformed persisted keys fail closed without replacement', () async {
    for (final value in [
      'CORRUPT',
      base64Url.encode(List.filled(31, 0)),
      base64Url.encode(List.filled(33, 0)),
    ]) {
      store.values[KeyManager.slot(1)] = value;
      await expectLater(manager.initialize(), _error(KeyErrorCode.corruptKey));
      expect(store.values[KeyManager.slot(1)] == value, isTrue);
      expect(store.writes, 0);
    }
  });

  test('active-version metadata is canonical and bounded', () async {
    for (final value in ['', '01', '0', '-1', '1.0', '2147483648', '1\n']) {
      store.values[KeyManager.activeVersionSlot] = value;
      await expectLater(
        manager.loadCurrent(),
        _error(KeyErrorCode.invalidVersion),
      );
      await expectLater(
        manager.initialize(),
        _error(KeyErrorCode.invalidVersion),
      );
    }
    expect(store.writes, 0);
  });

  test('interrupted v1 activation reuses the persisted key', () async {
    store.failWriteTo = KeyManager.activeVersionSlot;
    await expectLater(
      manager.initialize(),
      _error(KeyErrorCode.storageUnavailable),
    );
    final before = store.values[KeyManager.slot(1)];
    expect(before != null, isTrue);
    store.failWriteTo = null;
    final recovered = await manager.initialize();
    recovered.destroy();
    expect(store.values[KeyManager.slot(1)] == before, isTrue);
    expect(await manager.currentVersion(), 1);
  });

  test(
    'rotation writes a new key, retains old keys, and survives restart',
    () async {
      (await manager.initialize()).destroy();
      final old = store.values[KeyManager.slot(1)];
      final rotated = await manager.rotate();
      rotated.destroy();
      expect(await KeyManager(store).currentVersion(), 2);
      expect(store.values[KeyManager.slot(1)] == old, isTrue);
      expect(store.values[KeyManager.slot(2)] != old, isTrue);
      (await manager.loadVersion(1)).destroy();
    },
  );

  test(
    'interrupted rotation never loses the previous key or pending new key',
    () async {
      (await manager.initialize()).destroy();
      final old = store.values[KeyManager.slot(1)];
      store.failWriteTo = KeyManager.activeVersionSlot;
      await expectLater(
        manager.rotate(),
        _error(KeyErrorCode.storageUnavailable),
      );
      final pending = store.values[KeyManager.slot(2)];
      expect(pending != null, isTrue);
      expect(await manager.currentVersion(), 1);
      store.failWriteTo = null;
      (await manager.rotate()).destroy();
      expect(await manager.currentVersion(), 2);
      expect(store.values[KeyManager.slot(1)] == old, isTrue);
      expect(store.values[KeyManager.slot(2)] == pending, isTrue);
    },
  );

  test('a missing pointer after rotation cannot roll back to v1', () async {
    (await manager.initialize()).destroy();
    (await manager.rotate()).destroy();
    store.values.remove(KeyManager.activeVersionSlot);
    final writes = store.writes;
    await expectLater(
      manager.initialize(),
      _error(KeyErrorCode.invalidVersion),
    );
    expect(store.writes, writes);
  });

  test(
    'ambiguous pointer verification preserves the actually committed key',
    () async {
      (await manager.initialize()).destroy();
      store.failReadBackOf = KeyManager.activeVersionSlot;
      await expectLater(
        manager.rotate(),
        _error(KeyErrorCode.storageUnavailable),
      );
      store.failReadBackOf = null;
      expect(await manager.currentVersion(), 2);
      expect(store.values.containsKey(KeyManager.slot(1)), isTrue);
      expect(store.values.containsKey(KeyManager.slot(2)), isTrue);
    },
  );

  test('unverifiable writes are reported and do not activate a key', () async {
    store.discardWrites = true;
    await expectLater(
      manager.initialize(),
      _error(KeyErrorCode.storageConflict),
    );
    expect(store.values.containsKey(KeyManager.activeVersionSlot), isFalse);
  });

  test(
    'storage and lock failures are sanitized and do not poison the queue',
    () async {
      store.failReads = true;
      try {
        await manager.initialize();
        fail('Expected error');
      } on KeyManagementException catch (error) {
        expect(error.code, KeyErrorCode.storageUnavailable);
        expect(
          error.toString().contains('SIMULATED-PRIVATE-BACKEND-DETAIL'),
          isFalse,
        );
      }
      expect(store.writes, 0);
      store.failReads = false;
      store.failLock = true;
      await expectLater(
        manager.initialize(),
        _error(KeyErrorCode.storageUnavailable),
      );
      store.failLock = false;
      (await manager.initialize()).destroy();
      expect(await manager.currentVersion(), 1);
    },
  );

  test('version overflow never replaces existing material', () async {
    (await manager.initialize()).destroy();
    const maximum = EncryptedLicenseNumber.maxKeyVersion;
    store.values[KeyManager.slot(maximum)] = store.values[KeyManager.slot(1)]!;
    store.values[KeyManager.activeVersionSlot] = '$maximum';
    final writes = store.writes;
    await expectLater(manager.rotate(), _error(KeyErrorCode.versionLimit));
    expect(store.writes, writes);
    for (final version in [0, -1, maximum + 1]) {
      expect(
        () => KeyManager.slot(version),
        _error(KeyErrorCode.invalidVersion),
      );
    }
  });

  test(
    'HKDF field and database contracts match their specified salt/info',
    () async {
      final organization = await manager.initialize();
      final record = cryptoLicense();
      final field = await KeyDerivation.numberKey(organization, record);
      final db = await KeyDerivation.databaseKey(manager, keyVersion: 1);
      final expectedField = await Hkdf(hmac: Hmac.sha256(), outputLength: 32)
          .deriveKey(
            secretKey: organization.secretKey,
            nonce: utf8.encode(record.id),
            info: utf8.encode('lm/field/num/v1'),
          );
      final expectedDb = await Hkdf(hmac: Hmac.sha256(), outputLength: 32)
          .deriveKey(
            secretKey: organization.secretKey,
            info: utf8.encode('lm/db/v1'),
          );
      try {
        expect(field == expectedField, isTrue);
        final expectedHex = expectedDb.bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        expect(db.hex == expectedHex, isTrue);
        expect(db.hex.length, 64);
        expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(db.hex), isTrue);
        expect(field == expectedDb, isFalse);
        expect(db.toString().contains(db.hex), isFalse);
      } finally {
        field.destroy();
        db.destroy();
        expectedField.destroy();
        expectedDb.destroy();
        organization.destroy();
      }
      expect(() => db.hex, throwsStateError);
    },
  );

  test(
    'record salts differ and DB versions remain explicit after rotation',
    () async {
      final org = await manager.initialize();
      final field1 = await KeyDerivation.numberKey(org, cryptoLicense());
      final field2 = await KeyDerivation.numberKey(
        org,
        cryptoLicense(id: '6411817c-9e8a-44d0-a9b2-a471cc5d2b84'),
      );
      final before = await KeyDerivation.databaseKey(manager, keyVersion: 1);
      (await manager.rotate()).destroy();
      final old = await KeyDerivation.databaseKey(manager, keyVersion: 1);
      final next = await KeyDerivation.databaseKey(manager, keyVersion: 2);
      try {
        expect(field1 == field2, isFalse);
        expect(before.hex == old.hex, isTrue);
        expect(before.hex == next.hex, isFalse);
        expect(old.keyVersion, 1);
        expect(next.keyVersion, 2);
      } finally {
        org.destroy();
        field1.destroy();
        field2.destroy();
        before.destroy();
        old.destroy();
        next.destroy();
      }
    },
  );
}
