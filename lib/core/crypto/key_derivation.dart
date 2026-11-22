import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../shared/models/license.dart';
import 'key_manager.dart';

/// An ephemeral raw SQLCipher key bound to an explicit organization key version.
final class DatabaseKey {
  DatabaseKey._(this.keyVersion, this._key);
  final SecretKeyData _key;

  /// Retain this version in secure metadata until SQLCipher rekey succeeds.
  final int keyVersion;

  /// 64 lowercase hex characters for runtime SQLCipher raw-key injection only.
  String get hex =>
      _key.bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  /// Attempts to overwrite the owned derived-key buffer and releases it.
  void destroy() => _key.destroy();

  @override
  String toString() => 'DatabaseKey(version: $keyVersion, redacted)';
}

/// The planner's HKDF-SHA256 domain separation, implemented by cryptography.
abstract final class KeyDerivation {
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// Derives a record-specific number key with the exact v1 salt and info.
  static Future<SecretKeyData> numberKey(
    OrganizationKey organization,
    License license,
  ) async {
    license.validate();
    final derived = await _hkdf.deriveKey(
      secretKey: organization.secretKey,
      nonce: utf8.encode(license.id),
      info: utf8.encode('lm/field/num/v1'),
    );
    try {
      return derived.copy();
    } finally {
      derived.destroy();
    }
  }

  /// Derives a DB key for an explicit version, never implicitly rotates a DB.
  static Future<DatabaseKey> databaseKey(
    KeyManager keys, {
    required int keyVersion,
  }) async {
    final organization = await keys.loadVersion(keyVersion);
    try {
      final derived = await _hkdf.deriveKey(
        secretKey: organization.secretKey,
        info: utf8.encode('lm/db/v1'),
      );
      try {
        return DatabaseKey._(keyVersion, derived.copy());
      } finally {
        derived.destroy();
      }
    } finally {
      organization.destroy();
    }
  }
}
