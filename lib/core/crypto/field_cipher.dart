import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../shared/models/encrypted_license_number.dart';
import '../../shared/models/license.dart';
import '../../shared/models/license_validation.dart';
import '../../shared/models/payload.dart';
import 'key_derivation.dart';
import 'key_manager.dart';
import 'key_store.dart';

/// Sanitized encryption failure; never contains plaintext or secret material.
final class FieldEncryptionException implements Exception {
  /// Indicates a cryptographic operation could not safely produce a result.
  const FieldEncryptionException();

  @override
  String toString() => 'FieldEncryptionException';
}

/// AES-256-GCM number encryption using record-bound HKDF keys and AAD.
final class FieldCipher {
  /// Uses only organization keys supplied by the secure key manager.
  FieldCipher(this._keys);
  final KeyManager _keys;
  final AesGcm _aes = AesGcm.with256bits();

  /// Encrypts a memory-only number with a fresh library-generated 12-byte nonce.
  ///
  /// A missing number returns null without opening secure storage. Missing keys
  /// produce an explicit error; this method never initializes an organization.
  Future<EncryptedLicenseNumber?> encrypt(License license) async {
    license.validate();
    final value = license.licenseNumber;
    if (value == null) return null;
    final clear = utf8.encode(value);
    OrganizationKey? organization;
    SecretKeyData? fieldKey;
    try {
      final envelopeLength = 3 + ((12 + clear.length + 16 + 2) ~/ 3) * 4;
      if (envelopeLength > 1024) {
        throw const LicenseValidationException(
          LicenseField.licenseNumber,
          LicenseValidationCode.tooLong,
        );
      }
      organization = await _keys.loadCurrent();
      fieldKey = await KeyDerivation.numberKey(organization, license);
      final box = await _aes.encrypt(
        clear,
        secretKey: fieldKey,
        nonce: _aes.newNonce(),
        aad: _aad(license),
      );
      final encoded = base64Url
          .encode([...box.nonce, ...box.cipherText, ...box.mac.bytes])
          .replaceAll('=', '');
      return EncryptedLicenseNumber.parse(
        'v1.$encoded',
        keyVersion: organization.version,
      );
    } on KeyManagementException {
      rethrow;
    } on LicenseValidationException {
      rethrow;
    } catch (_) {
      throw const FieldEncryptionException();
    } finally {
      clear.fillRange(0, clear.length, 0);
      fieldKey?.destroy();
      organization?.destroy();
    }
  }

  /// Builds a size-checked payload only after real number encryption succeeds.
  Future<LicensePayload> encryptPayload(License license) async =>
      LicensePayload.fromLicense(
        license,
        encryptedLicenseNumber: await encrypt(license),
      );

  /// Authenticates the exact version, record ID, and expiration date.
  ///
  /// Missing/corrupt keys, modified data, invalid UTF-8, and storage failures
  /// return null. The caller must retain the original ciphertext on failure.
  Future<String?> decrypt(
    EncryptedLicenseNumber? envelope, {
    required License license,
  }) async {
    if (envelope == null) return null;
    OrganizationKey? organization;
    SecretKeyData? fieldKey;
    List<int>? clear;
    try {
      license.validate();
      organization = await _keys.loadVersion(envelope.keyVersion);
      fieldKey = await KeyDerivation.numberKey(organization, license);
      final bytes = base64Url.decode(
        base64Url.normalize(envelope.encoded.substring(3)),
      );
      final box = SecretBox(
        bytes.sublist(12, bytes.length - 16),
        nonce: bytes.sublist(0, 12),
        mac: Mac(bytes.sublist(bytes.length - 16)),
      );
      clear = await _aes.decrypt(box, secretKey: fieldKey, aad: _aad(license));
      final number = utf8.decode(clear);
      // Validate decoded text without logging or returning an invalid record.
      license.withLicenseNumber(number);
      return number;
    } catch (_) {
      return null;
    } finally {
      if (clear != null) {
        try {
          clear.fillRange(0, clear.length, 0);
        } on UnsupportedError {
          // Some library backends return immutable buffers; never promise full
          // RAM erasure across managed strings, libraries, and native copies.
        }
      }
      fieldKey?.destroy();
      organization?.destroy();
    }
  }

  /// Authenticates old data and re-encrypts it for the current version on demand.
  ///
  /// Returns null on a read failure; it never deletes or overwrites old data.
  /// Actual DB/Calendar persistence belongs to the later repository/sync layers.
  Future<EncryptedLicenseNumber?> migrateIfNeeded(
    EncryptedLicenseNumber envelope, {
    required License license,
  }) async {
    try {
      final number = await decrypt(envelope, license: license);
      if (number == null) return null;
      if (envelope.keyVersion == await _keys.currentVersion()) return envelope;
      return await encrypt(license.withLicenseNumber(number));
    } on KeyManagementException {
      return null;
    } on FieldEncryptionException {
      return null;
    } on LicenseValidationException {
      return null;
    }
  }

  static List<int> _aad(License license) => utf8.encode(
    'lm:v1:${license.id}:${LicenseDate.format(license.expirationDate, field: LicenseField.expirationDate)}',
  );

  @override
  String toString() => 'FieldCipher(redacted)';
}
