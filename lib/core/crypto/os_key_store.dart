import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'key_store.dart';

/// App-scoped OS secure storage with a zero-content cross-process lock file.
final class OsKeyStore implements KeyStore {
  /// Uses private non-synchronizing keychain services and no plaintext fallback.
  factory OsKeyStore({
    String service = 'com.smallbizcompliance.license-manager.keys',
  }) {
    if (kIsWeb ||
        !const {
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
          TargetPlatform.windows,
        }.contains(defaultTargetPlatform)) {
      throw const KeyManagementException(KeyErrorCode.storageUnavailable);
    }
    final match = RegExp(r'^[a-zA-Z0-9.-]+$').firstMatch(service);
    if (service.length > 100 || match == null || match.end != service.length) {
      throw const KeyManagementException(KeyErrorCode.storageUnavailable);
    }
    return OsKeyStore._(
      service,
      defaultTargetPlatform == TargetPlatform.windows,
      FlutterSecureStorage(
        iOptions: IOSOptions(
          accountName: service,
          accessibility: KeychainAccessibility.unlocked_this_device,
          synchronizable: false,
        ),
        // Private macOS login Keychain, without shared groups/provisioning.
        mOptions: MacOsOptions(
          accountName: service,
          accessibility: KeychainAccessibility.unlocked_this_device,
          synchronizable: false,
          usesDataProtectionKeychain: false,
        ),
        aOptions: AndroidOptions(
          storageNamespace: service,
          resetOnError: false,
          migrateOnAlgorithmChange: false,
        ),
        wOptions: const WindowsOptions(useBackwardCompatibility: false),
      ),
    );
  }

  const OsKeyStore._(this._service, this._prefixKeys, this._storage);
  final String _service;
  final bool _prefixKeys;
  final FlutterSecureStorage _storage;

  // Windows has an app-wide backend rather than Apple/Android service scopes.
  String _physicalKey(String key) => _prefixKeys ? '$_service.$key' : key;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: _physicalKey(key));
    } catch (_) {
      throw const KeyManagementException(KeyErrorCode.storageUnavailable);
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: _physicalKey(key), value: value);
    } catch (_) {
      throw const KeyManagementException(KeyErrorCode.storageUnavailable);
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: _physicalKey(key));
    } catch (_) {
      throw const KeyManagementException(KeyErrorCode.storageUnavailable);
    }
  }

  @override
  Future<T> withExclusiveAccess<T>(Future<T> Function() action) async {
    RandomAccessFile? handle;
    try {
      final base = await getApplicationSupportDirectory();
      final locks = Directory.fromUri(base.uri.resolve('crypto-locks/'));
      await locks.create(recursive: true);
      final fileName = _prefixKeys
          ? 'secure-storage-windows.lock'
          : '$_service.lock';
      handle = await File.fromUri(locks.uri.resolve(fileName))
          .open(mode: FileMode.append);
      await handle.lock(FileLock.blockingExclusive);
    } catch (_) {
      try {
        await handle?.close();
      } catch (_) {
        /* Preserve sanitized I/O error. */
      }
      throw const KeyManagementException(KeyErrorCode.storageUnavailable);
    }
    try {
      // Domain errors belong to the caller, e.g. a denied password is not an
      // inaccessible Keychain. Each service sanitizes its own callback errors.
      return await action();
    } finally {
      try {
        await handle.close();
      } catch (_) {
        throw const KeyManagementException(KeyErrorCode.storageUnavailable);
      }
    }
  }

  @override
  String toString() => 'OsKeyStore(redacted)';
}
