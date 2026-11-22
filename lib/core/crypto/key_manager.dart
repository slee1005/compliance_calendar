import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../shared/models/encrypted_license_number.dart';
import 'key_store.dart';

/// An ephemeral organization key; its bytes must never enter logs or app files.
final class OrganizationKey {
  OrganizationKey._(this.version, this._key);

  /// Version of the OS secure-storage slot used for this key.
  final int version;
  final SecretKeyData _key;

  /// Opaque key handle for cryptographic operations; ownership stays here.
  SecretKey get secretKey => _key;

  /// Releases this handle and attempts to overwrite its owned byte buffer.
  void destroy() => _key.destroy();

  @override
  String toString() => 'OrganizationKey(version: $version, redacted)';
}

/// Creates, loads, and rotates 32-byte CSPRNG keys without deleting old slots.
final class KeyManager {
  /// Uses an injected secure store; production must use OsKeyStore.
  KeyManager(this._store);

  /// Non-secret active-key pointer, itself stored in OS secure storage.
  static const activeVersionSlot = 'lm.orgKey.activeVersion';

  /// Resolves the immutable slot name mandated by the planner.
  static String slot(int version) {
    _validateVersion(version);
    return 'lm.orgKey.v$version';
  }

  final KeyStore _store;
  static Future<void> _tail = Future.value();

  /// Initializes a new organization, or resumes an interrupted v1 activation.
  ///
  /// A present but invalid key is never overwritten. Reads for normal operation
  /// use loadCurrent instead, so missing keys never trigger regeneration.
  Future<OrganizationKey> initialize() => _exclusive(() async {
    final active = await _store.read(activeVersionSlot);
    if (active != null) return _read(_parseVersion(active));
    if (await _store.read(slot(2)) != null) {
      throw const KeyManagementException(KeyErrorCode.invalidVersion);
    }
    final encoded = await _store.read(slot(1));
    final key = encoded == null ? await _create(1) : _decode(encoded, 1);
    try {
      await _writeVerified(activeVersionSlot, '1');
      return key;
    } catch (_) {
      key.destroy();
      rethrow;
    }
  });

  /// Loads the active key without creating or replacing anything.
  Future<OrganizationKey> loadCurrent() => _exclusive(() async {
    final active = await _store.read(activeVersionSlot);
    if (active == null) {
      throw const KeyManagementException(KeyErrorCode.missingKey);
    }
    return _read(_parseVersion(active));
  });

  /// Loads exactly the requested key version, never a fallback slot.
  Future<OrganizationKey> loadVersion(int version) =>
      _exclusive(() => _read(version));

  /// Returns the validated active version without retaining key material.
  Future<int> currentVersion() async {
    final key = await loadCurrent();
    try {
      return key.version;
    } finally {
      key.destroy();
    }
  }

  /// Persists and verifies a new slot before atomically selecting its version.
  ///
  /// Previous slots are retained for lazy field migration and SQLCipher rekey.
  /// A failed pointer write can be resumed using the already persisted slot.
  Future<OrganizationKey> rotate() => _exclusive(() async {
    final active = await _store.read(activeVersionSlot);
    if (active == null) {
      throw const KeyManagementException(KeyErrorCode.missingKey);
    }
    final old = await _read(_parseVersion(active));
    final version = old.version;
    old.destroy();
    if (version == EncryptedLicenseNumber.maxKeyVersion) {
      throw const KeyManagementException(KeyErrorCode.versionLimit);
    }
    final next = version + 1;
    final encoded = await _store.read(slot(next));
    final key = encoded == null ? await _create(next) : _decode(encoded, next);
    try {
      await _writeVerified(activeVersionSlot, '$next');
      return key;
    } catch (_) {
      key.destroy();
      rethrow;
    }
  });

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    final previous = _tail;
    final completed = Completer<void>();
    _tail = completed.future;
    await previous;
    try {
      return await _store.withExclusiveAccess(action);
    } on KeyManagementException {
      rethrow;
    } catch (_) {
      throw const KeyManagementException(KeyErrorCode.storageUnavailable);
    } finally {
      completed.complete();
    }
  }

  Future<OrganizationKey> _read(int version) async {
    _validateVersion(version);
    final encoded = await _store.read(slot(version));
    if (encoded == null) {
      throw const KeyManagementException(KeyErrorCode.missingKey);
    }
    return _decode(encoded, version);
  }

  Future<OrganizationKey> _create(int version) async {
    final secret = SecretKeyData.random(length: 32);
    try {
      final encoded = base64Url.encode(secret.bytes);
      await _writeVerified(slot(version), encoded);
      return OrganizationKey._(version, secret);
    } catch (_) {
      secret.destroy();
      rethrow;
    }
  }

  Future<void> _writeVerified(String name, String value) async {
    await _store.write(name, value);
    if (await _store.read(name) != value) {
      throw const KeyManagementException(KeyErrorCode.storageConflict);
    }
  }

  static OrganizationKey _decode(String value, int version) {
    try {
      if (value.length != 44 ||
          !RegExp(r'^[A-Za-z0-9_-]{43}=$').hasMatch(value)) {
        throw const FormatException();
      }
      final bytes = base64Url.decode(value);
      if (bytes.length != 32 || base64Url.encode(bytes) != value) {
        bytes.fillRange(0, bytes.length, 0);
        throw const FormatException();
      }
      return OrganizationKey._(
        version,
        SecretKeyData(bytes, overwriteWhenDestroyed: true),
      );
    } on FormatException {
      throw const KeyManagementException(KeyErrorCode.corruptKey);
    }
  }

  static int _parseVersion(String value) {
    final version = int.tryParse(value);
    if (version == null || '$version' != value) {
      throw const KeyManagementException(KeyErrorCode.invalidVersion);
    }
    _validateVersion(version);
    return version;
  }

  static void _validateVersion(int version) {
    if (version < 1 || version > EncryptedLicenseNumber.maxKeyVersion) {
      throw const KeyManagementException(KeyErrorCode.invalidVersion);
    }
  }

  @override
  String toString() => 'KeyManager(redacted)';
}
