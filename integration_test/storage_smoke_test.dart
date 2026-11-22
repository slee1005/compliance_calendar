import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:license_manager/app/app.dart';
import 'package:license_manager/core/crypto/field_cipher.dart';
import 'package:license_manager/core/crypto/key_manager.dart';
import 'package:license_manager/core/crypto/os_key_store.dart';
import 'package:license_manager/core/storage/cache_models.dart';
import 'package:license_manager/core/storage/db.dart';
import 'package:license_manager/core/storage/local_cache.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/cache_benchmark.dart';
import '../test/support/storage_support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native SQLCipher persists an encrypted cache and revisioned outbox',
    (tester) async {
      await tester.pumpWidget(const ComplianceApp());
      await tester.pumpAndSettle();
      final store = OsKeyStore(
        service:
            'com.smallbizcompliance.t4.${DateTime.now().microsecondsSinceEpoch}',
      );
      final keys = KeyManager(store);
      final temp = await getTemporaryDirectory();
      await temp.create(recursive: true);
      final directory = await temp.createTemp('compliance-t4-');
      final cacheId = storageId(9000);
      ComplianceDatabase? db;
      try {
        (await keys.initialize()).destroy();
        db = await LocalCache.open(
          secureStore: store,
          cacheId: cacheId,
          directory: directory,
          createIfMissing: true,
        );
        final measured = await benchmarkCache(db);
        expect(measured.matches, 92);
        expect((await db.licenses.pendingChanges(limit: 1000)).length, 500);
        expect((await db.licenses.auditEntries()).length, 500);
        final cipher = FieldCipher(keys);
        final record = storageLicense(1, number: 'MEMORY-ONLY-NUMBER');
        final old = await db.licenses.upsert(
          await cipher.encryptPayload(record),
        );
        (await keys.rotate()).destroy();
        await db.licenses.upsert(
          await cipher.encryptPayload(record),
          expectedRevision: 1,
        );
        expect(await db.licenses.acknowledgeChange(record.id, 1), isFalse);
        await db.checkIntegrity();
        final version = db.cipherVersion;
        // Inspect main/WAL bytes while the connection is open, before checkpoint.
        for (final file
            in await directory
                .list()
                .where((e) => e is File)
                .cast<File>()
                .toList()) {
          final bytes = latin1.decode(await file.readAsBytes());
          expect(bytes.contains('T4-FICTIONAL-HOLDER-'), isFalse);
          expect(bytes.contains('MEMORY-ONLY-NUMBER'), isFalse);
        }
        await db.close();
        db = null;
        db = await LocalCache.open(
          secureStore: store,
          cacheId: cacheId,
          directory: directory,
        );
        final restored = (await db.licenses.find(record.id))!;
        expect(restored.revision, 2);
        expect(
          await cipher.decrypt(
            restored.payload.encryptedLicenseNumber,
            license: restored.license,
          ),
          'MEMORY-ONLY-NUMBER',
        );
        expect(
          await cipher.decrypt(
            old.payload.encryptedLicenseNumber,
            license: old.license,
          ),
          'MEMORY-ONLY-NUMBER',
        );
        expect(
          await db.licenses.softDelete(record.id, expectedRevision: 2),
          isTrue,
        );
        expect(
          (await db.licenses.pendingChanges(limit: 1000))
              .where((c) => c.licenseId == record.id)
              .single
              .operation,
          ChangeOperation.delete,
        );
        binding.reportData = {
          'storage': {
            'platform': defaultTargetPlatform.name,
            'mode': kReleaseMode
                ? 'release'
                : kProfileMode
                ? 'profile'
                : 'debug',
            'cipherVersion': version,
            'insert500Ms': measured.insertMs,
            'filterMs': measured.filterMs,
            'matches': measured.matches,
            'verifiedAtUtc': DateTime.now().toUtc().toIso8601String(),
            'performanceEnforced': const bool.fromEnvironment(
              'ENFORCE_STORAGE_PERFORMANCE',
            ),
          },
        };
        if (const bool.fromEnvironment('ENFORCE_STORAGE_PERFORMANCE')) {
          expect(
            kDebugMode,
            isFalse,
            reason: 'Enforce timings on a native AOT build.',
          );
          expect(measured.insertMs, lessThan(50));
          expect(measured.filterMs, lessThan(50));
          expect(measured.insertMs + measured.filterMs, lessThan(50));
        }
      } finally {
        await db?.close();
        await directory.delete(recursive: true);
        await store.withExclusiveAccess(() async {
          for (final slot in [
            KeyManager.slot(1),
            KeyManager.slot(2),
            KeyManager.activeVersionSlot,
            LocalCache.keyVersionSlot(cacheId),
          ]) {
            await store.delete(slot);
            expect(await store.read(slot) == null, isTrue);
          }
        });
      }
    },
  );
}
