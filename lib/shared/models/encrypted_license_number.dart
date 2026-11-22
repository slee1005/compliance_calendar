import 'dart:convert';

import 'license_validation.dart';

/// A structurally checked opaque `v1.<base64url>` transport envelope.
///
/// Parsing does not encrypt data or authenticate a GCM tag. FieldCipher produces
/// and authenticates the nonce/ciphertext/tag with the correct organization key.
final class EncryptedLicenseNumber {
  /// Accepts only URL-safe v1 envelopes with a nonce, ciphertext, and tag.
  factory EncryptedLicenseNumber.parse(String value, {int keyVersion = 1}) {
    if (keyVersion < 1 || keyVersion > maxKeyVersion) {
      throw const LicenseValidationException(
        LicenseField.keyVersion,
        LicenseValidationCode.invalidChoice,
      );
    }
    const field = LicenseField.licenseNumber;
    if (value.length > 1024) {
      throw const LicenseValidationException(
        field,
        LicenseValidationCode.tooLong,
      );
    }
    final match = _pattern.firstMatch(value);
    if (match == null || match.end != value.length) {
      throw const LicenseValidationException(
        field,
        LicenseValidationCode.invalidEnvelope,
      );
    }
    final body = match.group(1)!;
    try {
      final bytes = base64Url.decode(base64Url.normalize(body));
      // 12-byte nonce + at least one ciphertext byte + 16-byte GCM tag.
      if (bytes.length < 29 ||
          base64Url.encode(bytes).replaceAll('=', '') !=
              body.replaceAll('=', '')) {
        throw const FormatException();
      }
    } on FormatException {
      throw const LicenseValidationException(
        field,
        LicenseValidationCode.invalidEnvelope,
      );
    }
    return EncryptedLicenseNumber._(value, keyVersion);
  }

  const EncryptedLicenseNumber._(this.encoded, this.keyVersion);

  /// The supported positive version range for organization key slots.
  static const maxKeyVersion = 0x7fffffff;

  static final _pattern = RegExp(r'^v1\.([A-Za-z0-9_-]+={0,2})$');

  /// The validated wire value; padded and unpadded base64url are preserved.
  final String encoded;

  /// Organization key slot, independent of the `v1.` envelope format version.
  final int keyVersion;

  @override
  bool operator ==(Object other) =>
      other is EncryptedLicenseNumber &&
      other.encoded == encoded &&
      other.keyVersion == keyVersion;

  @override
  int get hashCode => Object.hash(encoded, keyVersion);

  @override
  String toString() => 'EncryptedLicenseNumber(redacted)';
}
