import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../crypto/key_derivation.dart';
import '../crypto/key_manager.dart';
import '../crypto/key_store.dart';
import '../../shared/models/encrypted_license_number.dart';
import 'cache_models.dart';
import 'db.dart';

/// Binds a cache UUID to its DB key version in OS secure storage.
///
/// Organization-key rotation does not silently switch an existing database key.
/// No organization key is generated here. Explicit initialization belongs to T3.
abstract final class LocalCache {
  static Future<void> _tail = Future.value();

  // POSIX advisory locks coordinate processes, not concurrent async callers
  // in one process. Keep binding selection and first DB open serialized here.
  static Future<T> _serialized<T>(Future<T> Function() action) async {
    final previous = _tail;
    final completed = Completer<void>();
    _tail = completed.future;
    await previous;
    try {
      return await action();
    } finally {
      completed.complete();
    }
  }

  /// Non-secret secure metadata slot; also used for scoped test cleanup.
  static String keyVersionSlot(String cacheId) {
    if (!RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(cacheId) ||
        cacheId.length != 36) {
      throw const StorageException(StorageErrorCode.invalidRequest);
    }
    return 'lm.cache.$cacheId.keyVersion';
  }

  /// Opens an app-support cache using the caller's account-scoped UUID.
  static Future<ComplianceDatabase> openApplication({
    required KeyStore secureStore,
    required String cacheId,
    bool createIfMissing = false,
  }) async {
    try {
      final support = await getApplicationSupportDirectory();
      return await open(
        secureStore: secureStore,
        cacheId: cacheId,
        directory: Directory.fromUri(support.uri.resolve('cache/')),
        createIfMissing: createIfMissing,
      );
    } on StorageException {
      rethrow;
    } on KeyManagementException {
      rethrow;
    } catch (_) {
      throw const StorageException(StorageErrorCode.cannotOpen);
    }
  }

  /// Explicit directory injection for isolated development/native test caches.
  ///
  /// A missing binding beside an existing file is a recovery error. It never
  /// assumes the newest organization key, replaces the file, or falls back.
  static Future<ComplianceDatabase> open({
    required KeyStore secureStore,
    required String cacheId,
    required Directory directory,
    bool createIfMissing = false,
  }) => _serialized(
    () => _open(
      secureStore: secureStore,
      cacheId: cacheId,
      directory: directory,
      createIfMissing: createIfMissing,
    ),
  );

  static Future<ComplianceDatabase> _open({
    required KeyStore secureStore,
    required String cacheId,
    required Directory directory,
    required bool createIfMissing,
  }) async {
    final slot = keyVersionSlot(cacheId);
    if (!directory.isAbsolute) {
      throw const StorageException(StorageErrorCode.invalidRequest);
    }
    final file = File.fromUri(directory.uri.resolve('$cacheId.db'));
    final keys = KeyManager(secureStore);
    Future<String?> binding() =>
        secureStore.withExclusiveAccess(() => secureStore.read(slot));
    try {
      var encoded = await binding();
      if (encoded == null) {
        if (await file.exists()) {
          throw const StorageException(StorageErrorCode.missingKeyBinding);
        }
        if (!createIfMissing) {
          throw const StorageException(StorageErrorCode.cannotOpen);
        }
        final candidate = await keys.currentVersion();
        // Never nest key-manager and metadata locks. The candidate remains
        // valid even if a concurrent organization rotation selects a newer key.
        encoded = await secureStore.withExclusiveAccess(() async {
          final existing = await secureStore.read(slot);
          if (existing != null) return existing;
          await secureStore.write(slot, '$candidate');
          if (await secureStore.read(slot) != '$candidate') {
            throw const KeyManagementException(KeyErrorCode.storageConflict);
          }
          return '$candidate';
        });
      }
      final version = int.tryParse(encoded!);
      if (version == null ||
          '$version' != encoded ||
          version < 1 ||
          version > EncryptedLicenseNumber.maxKeyVersion) {
        throw const StorageException(StorageErrorCode.missingKeyBinding);
      }
      final key = await KeyDerivation.databaseKey(keys, keyVersion: version);
      try {
        if (createIfMissing) await directory.create(recursive: true);
        return await ComplianceDatabase.open(
          path: file.path,
          key: key,
          createIfMissing: createIfMissing,
        );
      } finally {
        key.destroy();
      }
    } on StorageException {
      rethrow;
    } on KeyManagementException {
      rethrow;
    } catch (_) {
      throw const StorageException(StorageErrorCode.cannotOpen);
    }
  }
}
