import 'dart:io';

import 'package:license_manager/core/crypto/key_derivation.dart';
import 'package:license_manager/core/crypto/key_manager.dart';
import 'package:license_manager/core/storage/db.dart';
import 'package:license_manager/shared/models/license.dart';
import 'package:license_manager/shared/models/license_category.dart';
import 'package:license_manager/shared/models/payload.dart';

import 'crypto_support.dart';

/// Runtime-only keys and isolated encrypted test files; never a production store.
final class StorageHarness {
  /// Caches contain only explicitly fictional structured records.
  final TestKeyStore store = TestKeyStore();

  /// Root-isolate key manager.
  late final KeyManager keys = KeyManager(store);

  /// Temporary directory belonging only to this test.
  late Directory directory;

  /// Explicit derived DB key; never printed or snapshotted.
  late DatabaseKey key;

  /// Worker under test.
  late ComplianceDatabase db;

  /// Isolated file path.
  String get path => '${directory.path}/cache.db';

  /// Prepares one encrypted cache with a runtime CSPRNG key.
  Future<void> initialize() async {
    directory = await Directory.systemTemp.createTemp('compliance-t4-test-');
    (await keys.initialize()).destroy();
    key = await KeyDerivation.databaseKey(keys, keyVersion: 1);
    db = await ComplianceDatabase.open(
      path: path,
      key: key,
      createIfMissing: true,
    );
  }

  /// Closes the worker, clears runtime keys, and deletes only its test directory.
  Future<void> dispose() async {
    await db.close();
    key.destroy();
    store.values.clear();
    await directory.delete(recursive: true);
  }
}

/// Deterministic UUIDs identify fictional records, never secret keys.
String storageId(int i) =>
    '00000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}';

/// Fictional structured data for cache tests, with no document fixtures.
License storageLicense(
  int i, {
  int days = 91,
  String? number,
  String? name,
  LicenseCategory? category,
  String type = 'Example permit',
  String holderType = 'staff',
}) => License(
  id: storageId(i),
  category: category ?? LicenseCategory.values[i % 6],
  licenseType: type,
  holderName: name ?? 'T4-FICTIONAL-HOLDER-$i',
  holderType: holderType,
  issueDate: DateTime.utc(2020),
  expirationDate: DateTime.utc(2026, 11, 21).add(Duration(days: days)),
  issuer: 'Fictional issuer',
  licenseNumber: number,
  locationNote: 'Example cabinet',
);

/// Builds metadata-only payloads; numbered records must use the real FieldCipher.
LicensePayload storagePayload(
  int i, {
  int days = 91,
  String? name,
  LicenseCategory? category,
  String type = 'Example permit',
  String holderType = 'staff',
}) => LicensePayload.fromLicense(
  storageLicense(
    i,
    days: days,
    name: name,
    category: category,
    type: type,
    holderType: holderType,
  ),
);
