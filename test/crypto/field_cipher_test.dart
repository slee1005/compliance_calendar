import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:license_manager/core/crypto/field_cipher.dart';
import 'package:license_manager/core/crypto/key_derivation.dart';
import 'package:license_manager/core/crypto/key_manager.dart';
import 'package:license_manager/core/crypto/key_store.dart';
import 'package:license_manager/shared/models/encrypted_license_number.dart';
import 'package:license_manager/shared/models/license_validation.dart';
import 'package:license_manager/shared/models/payload.dart';

import '../support/crypto_support.dart';

List<int> _bytes(EncryptedLicenseNumber value) =>
    base64Url.decode(base64Url.normalize(value.encoded.substring(3)));

EncryptedLicenseNumber _tamper(EncryptedLicenseNumber value, int index) {
  final bytes = _bytes(value);
  bytes[index] ^= 1;
  return EncryptedLicenseNumber.parse(
    'v1.${base64Url.encode(bytes)}',
    keyVersion: value.keyVersion,
  );
}

void main() {
  late TestKeyStore store;
  late KeyManager keys;
  late FieldCipher cipher;
  setUp(() {
    store = TestKeyStore();
    keys = KeyManager(store);
    cipher = FieldCipher(keys);
  });
  tearDown(() => store.values.clear());

  test(
    'real AES-GCM encryption round trips UTF-8 without plaintext in payload',
    () async {
      (await keys.initialize()).destroy();
      final record = cryptoLicense(number: '가상번호-😀');
      final payload = await cipher.encryptPayload(record);
      expect(payload.encryptedLicenseNumber!.keyVersion, 1);
      expect(payload.toMap().containsKey('lm_key'), isFalse);
      expect(
        jsonEncode(payload.toMap()).contains(record.licenseNumber!),
        isFalse,
      );
      final restored = LicensePayload.fromMap(payload.toMap());
      expect(
        await cipher.decrypt(
          restored.encryptedLicenseNumber,
          license: restored.toLicense(),
        ),
        record.licenseNumber,
      );
      expect(restored.toLicense().licenseNumber, isNull);
    },
  );

  test(
    'ciphertext interoperates with the exact library AES-GCM/AAD contract',
    () async {
      final org = await keys.initialize();
      final record = cryptoLicense();
      final encrypted = (await cipher.encrypt(record))!;
      final raw = _bytes(encrypted);
      final field = await KeyDerivation.numberKey(org, record);
      try {
        final clear = await AesGcm.with256bits().decrypt(
          SecretBox(
            raw.sublist(12, raw.length - 16),
            nonce: raw.sublist(0, 12),
            mac: Mac(raw.sublist(raw.length - 16)),
          ),
          secretKey: field,
          aad: utf8.encode('lm:v1:${record.id}:2028-12-31'),
        );
        expect(utf8.decode(clear), 'MEMORY-ONLY');
        clear.fillRange(0, clear.length, 0);
      } finally {
        org.destroy();
        field.destroy();
      }
    },
  );

  test('nonce, ciphertext, tag, identity, and expiration changes fail authentication', () async {
    (await keys.initialize()).destroy();
    final record = cryptoLicense();
    final encrypted = (await cipher.encrypt(record))!;
    for (final index in [0, 12, _bytes(encrypted).length - 1]) {
      expect(
        await cipher.decrypt(_tamper(encrypted, index), license: record),
        isNull,
      );
    }
    expect(
      await cipher.decrypt(
        encrypted,
        license: cryptoLicense(id: '6411817c-9e8a-44d0-a9b2-a471cc5d2b84'),
      ),
      isNull,
    );
    expect(
      await cipher.decrypt(
        encrypted,
        license: cryptoLicense(expiry: DateTime.utc(2029, 1, 1)),
      ),
      isNull,
    );
  });

  test(
    'wrong organizations and absent, corrupt, or unavailable keys return null',
    () async {
      (await keys.initialize()).destroy();
      final record = cryptoLicense();
      final encrypted = (await cipher.encrypt(record))!;
      final otherStore = TestKeyStore();
      final otherKeys = KeyManager(otherStore);
      (await otherKeys.initialize()).destroy();
      expect(
        await FieldCipher(otherKeys).decrypt(encrypted, license: record),
        isNull,
      );
      otherStore.values.clear();
      expect(
        await FieldCipher(otherKeys).decrypt(encrypted, license: record),
        isNull,
      );
      store.values[KeyManager.slot(1)] = 'CORRUPT';
      expect(await cipher.decrypt(encrypted, license: record), isNull);
      store.failReads = true;
      expect(await cipher.decrypt(encrypted, license: record), isNull);
    },
  );

  test(
    'encryption does not create missing keys; no-number metadata needs no key',
    () async {
      await expectLater(
        cipher.encrypt(cryptoLicense()),
        throwsA(
          isA<KeyManagementException>().having(
            (e) => e.code,
            'code',
            KeyErrorCode.missingKey,
          ),
        ),
      );
      expect(store.writes, 0);
      store.failReads = true;
      final reads = store.reads;
      expect(await cipher.encrypt(cryptoLicense(number: null)), isNull);
      expect(
        await cipher.decrypt(null, license: cryptoLicense(number: null)),
        isNull,
      );
      expect(
        (await cipher.encryptPayload(cryptoLicense(number: null)))
            .encryptedLicenseNumber,
        isNull,
      );
      expect(store.reads, reads);
    },
  );

  test(
    'oversized plaintext is rejected before touching secure storage',
    () async {
      await expectLater(
        cipher.encrypt(cryptoLicense(number: List.filled(2000, 'x').join())),
        throwsA(
          isA<LicenseValidationException>().having(
            (e) => e.code,
            'code',
            LicenseValidationCode.tooLong,
          ),
        ),
      );
      expect(store.reads, 0);
      expect(store.writes, 0);
    },
  );

  test('authenticated but invalid decoded text is never returned as a number', () async {
    final org = await keys.initialize();
    final record = cryptoLicense();
    final field = await KeyDerivation.numberKey(org, record);
    try {
      for (final invalid in [
        [255],
        [32],
        [10],
      ]) {
        final aes = AesGcm.with256bits();
        final box = await aes.encrypt(
          invalid,
          secretKey: field,
          nonce: aes.newNonce(),
          aad: utf8.encode('lm:v1:${record.id}:2028-12-31'),
        );
        final value = EncryptedLicenseNumber.parse(
          'v1.${base64Url.encode([...box.nonce, ...box.cipherText, ...box.mac.bytes])}',
        );
        expect(await cipher.decrypt(value, license: record), isNull);
      }
    } finally {
      org.destroy();
      field.destroy();
    }
  });

  test(
    'rotation preserves old reads and lazy migration emits the current version',
    () async {
      (await keys.initialize()).destroy();
      final record = cryptoLicense();
      final old = (await cipher.encrypt(record))!;
      (await keys.rotate()).destroy();
      expect(await cipher.decrypt(old, license: record), 'MEMORY-ONLY');
      final migrated = (await cipher.migrateIfNeeded(old, license: record))!;
      expect(migrated.keyVersion, 2);
      expect(migrated.encoded == old.encoded, isFalse);
      expect(await cipher.decrypt(migrated, license: record), 'MEMORY-ONLY');
      final payload = LicensePayload.fromLicense(
        record,
        encryptedLicenseNumber: migrated,
      );
      expect(payload.toMap()['lm_key'], '2');
      final restored = LicensePayload.fromMap(payload.toMap());
      expect(restored.encryptedLicenseNumber!.keyVersion, 2);
      expect(
        await cipher.decrypt(
          restored.encryptedLicenseNumber,
          license: restored.toLicense(),
        ),
        'MEMORY-ONLY',
      );
      expect(await cipher.migrateIfNeeded(migrated, license: record), migrated);
      expect(store.values.containsKey(KeyManager.slot(1)), isTrue);
      final wrongVersion = EncryptedLicenseNumber.parse(
        old.encoded,
        keyVersion: 2,
      );
      expect(await cipher.decrypt(wrongVersion, license: record), isNull);
    },
  );

  test(
    'migration fails closed and leaves original ciphertext unchanged',
    () async {
      (await keys.initialize()).destroy();
      final record = cryptoLicense();
      final old = (await cipher.encrypt(record))!;
      (await keys.rotate()).destroy();
      final damaged = _tamper(old, 12);
      expect(await cipher.migrateIfNeeded(damaged, license: record), isNull);
      store.failReads = true;
      expect(await cipher.migrateIfNeeded(old, license: record), isNull);
      expect(old.keyVersion, 1);
    },
  );

  test(
    '10,000 encryptions do not reuse a 12-byte nonce under one field key',
    () async {
      (await keys.initialize()).destroy();
      final seen = <String>{};
      final record = cryptoLicense();
      for (var i = 0; i < 10000; i++) {
        final encrypted = (await cipher.encrypt(record))!;
        final nonce = _bytes(encrypted).sublist(0, 12);
        expect(nonce.length, 12);
        expect(
          seen.add(base64Url.encode(nonce)),
          isTrue,
          reason: 'nonce uniqueness at iteration $i',
        );
      }
      expect(seen.length, 10000);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
