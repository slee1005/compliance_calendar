import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:license_manager/app/app.dart';
import 'package:license_manager/core/crypto/field_cipher.dart';
import 'package:license_manager/core/crypto/key_derivation.dart';
import 'package:license_manager/core/crypto/key_manager.dart';
import 'package:license_manager/core/crypto/os_key_store.dart';
import 'package:license_manager/shared/models/license.dart';
import 'package:license_manager/shared/models/license_category.dart';
import 'package:license_manager/shared/models/payload.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native secure storage creates, reloads, rotates, and removes test keys',
    (tester) async {
      await tester.pumpWidget(const ComplianceApp());
      await tester.pumpAndSettle();
      final store = OsKeyStore(
        service:
            'com.smallbizcompliance.t3.${DateTime.now().microsecondsSinceEpoch}',
      );
      final keys = KeyManager(store);
      final record = License(
        id: '96db7b78-58ba-465d-bd21-a5340b552c8a',
        category: LicenseCategory.professionalLicense,
        licenseType: 'Example permit',
        holderName: 'Example alias',
        holderType: 'staff',
        issueDate: DateTime.utc(2024),
        expirationDate: DateTime.utc(2028, 12, 31),
        issuer: 'Example issuer',
        licenseNumber: 'MEMORY-ONLY',
      );
      try {
        final first = await keys.initialize();
        expect((await first.secretKey.extractBytes()).length, 32);
        first.destroy();
        final cipher = FieldCipher(keys);
        final old = (await cipher.encrypt(record))!;
        expect(
          await FieldCipher(KeyManager(store)).decrypt(old, license: record),
          'MEMORY-ONLY',
        );
        (await keys.rotate()).destroy();
        expect(await keys.currentVersion(), 2);
        final migrated = (await cipher.migrateIfNeeded(old, license: record))!;
        expect(migrated.keyVersion, 2);
        final wire = LicensePayload.fromLicense(
          record,
          encryptedLicenseNumber: migrated,
        ).toMap();
        final decoded = LicensePayload.fromMap(wire);
        expect(
          await cipher.decrypt(
            decoded.encryptedLicenseNumber,
            license: decoded.toLicense(),
          ),
          'MEMORY-ONLY',
        );
        expect(await cipher.decrypt(old, license: record), 'MEMORY-ONLY');
        final db = await KeyDerivation.databaseKey(keys, keyVersion: 1);
        expect(db.hex.length, 64);
        db.destroy();
      } finally {
        await store.withExclusiveAccess(() async {
          for (final slot in [
            KeyManager.slot(1),
            KeyManager.slot(2),
            KeyManager.activeVersionSlot,
          ]) {
            await store.delete(slot);
            expect(await store.read(slot) == null, isTrue);
          }
        });
      }
    },
  );
}
