import 'dart:convert';

import 'encrypted_license_number.dart';
import 'license.dart';
import 'license_category.dart';
import 'license_validation.dart';

/// An immutable master-event property payload that never retains plaintext numbers.
///
/// This is a wire contract only: it performs no I/O, encryption, or Calendar API
/// calls. Unknown fields and oversized maps are rejected rather than truncated.
final class LicensePayload {
  /// Removes the in-memory number and requires its separate encrypted envelope.
  factory LicensePayload.fromLicense(
    License license, {
    EncryptedLicenseNumber? encryptedLicenseNumber,
  }) {
    license.validate();
    if (license.licenseNumber != null && encryptedLicenseNumber == null) {
      throw const LicenseValidationException(
        LicenseField.licenseNumber,
        LicenseValidationCode.encryptionRequired,
      );
    }
    if (license.licenseNumber == null && encryptedLicenseNumber != null) {
      throw const LicenseValidationException(
        LicenseField.licenseNumber,
        LicenseValidationCode.unexpectedEncryptedNumber,
      );
    }
    final payload = LicensePayload._(
      license.withLicenseNumber(null),
      encryptedLicenseNumber,
    );
    payload.toMap(); // Enforce the complete payload budget before accepting it.
    return payload;
  }

  /// Reads only the exact v1 schema; optional keys must also contain strings.
  factory LicensePayload.fromMap(Map<String, Object?> value) {
    if (value.keys.any((key) => !_fields.containsKey(key))) {
      throw const LicenseValidationException(
        LicenseField.payload,
        LicenseValidationCode.unexpectedField,
      );
    }
    final map = <String, String>{};
    for (final entry in _fields.entries) {
      if (!value.containsKey(entry.key)) {
        if (!_optional.contains(entry.key)) {
          throw LicenseValidationException(
            entry.value,
            LicenseValidationCode.required,
          );
        }
        continue;
      }
      final raw = value[entry.key];
      if (raw is! String) {
        throw LicenseValidationException(
          entry.value,
          LicenseValidationCode.wrongType,
        );
      }
      map[entry.key] = raw;
    }
    _checkSize(map);
    if (map['lm_app'] != 'license_manager') {
      throw const LicenseValidationException(
        LicenseField.payload,
        LicenseValidationCode.invalidChoice,
      );
    }
    if (map['lm_v'] != '1') {
      throw const LicenseValidationException(
        LicenseField.schemaVersion,
        LicenseValidationCode.unsupportedVersion,
      );
    }
    final category = LicenseCategory.tryParse(map['lm_cat']!);
    if (category == null) {
      throw const LicenseValidationException(
        LicenseField.category,
        LicenseValidationCode.invalidChoice,
      );
    }
    final license = License(
      id: map['lm_id']!,
      category: category,
      licenseType: map['lm_type']!,
      holderName: map['lm_holder']!,
      holderType: map['lm_htype']!,
      issueDate: LicenseDate.parse(
        map['lm_issue']!,
        field: LicenseField.issueDate,
      ),
      expirationDate: LicenseDate.parse(
        map['lm_exp']!,
        field: LicenseField.expirationDate,
      ),
      issuer: map['lm_issuer']!,
      locationNote: map['lm_loc'],
    );
    final encodedNumber = map['lm_num'];
    final rawKeyVersion = map['lm_key'];
    var keyVersion = 1;
    if (rawKeyVersion != null) {
      final parsed = int.tryParse(rawKeyVersion);
      if (encodedNumber == null ||
          parsed == null ||
          parsed.toString() != rawKeyVersion ||
          parsed < 1 ||
          parsed > EncryptedLicenseNumber.maxKeyVersion) {
        throw const LicenseValidationException(
          LicenseField.keyVersion,
          LicenseValidationCode.invalidChoice,
        );
      }
      keyVersion = parsed;
    }
    return LicensePayload._(
      license,
      encodedNumber == null
          ? null
          : EncryptedLicenseNumber.parse(encodedNumber, keyVersion: keyVersion),
    );
  }

  const LicensePayload._(this._metadata, this.encryptedLicenseNumber);

  /// Conservative total UTF-8 JSON budget required by planner section 7.5.
  static const int maxBytes = 1024;

  static const _optional = {'lm_num', 'lm_loc', 'lm_key'};
  static const _fields = {
    'lm_v': LicenseField.schemaVersion,
    'lm_app': LicenseField.payload,
    'lm_id': LicenseField.id,
    'lm_cat': LicenseField.category,
    'lm_type': LicenseField.licenseType,
    'lm_holder': LicenseField.holderName,
    'lm_htype': LicenseField.holderType,
    'lm_issue': LicenseField.issueDate,
    'lm_exp': LicenseField.expirationDate,
    'lm_issuer': LicenseField.issuer,
    'lm_num': LicenseField.licenseNumber,
    'lm_loc': LicenseField.locationNote,
    'lm_key': LicenseField.keyVersion,
  };

  final License _metadata;

  /// Optional opaque number; plaintext is absent from this payload's state.
  final EncryptedLicenseNumber? encryptedLicenseNumber;

  /// Produces an immutable string map suitable for private extended properties.
  Map<String, String> toMap() {
    final map = <String, String>{
      'lm_v': '${_metadata.schemaVersion}',
      'lm_app': 'license_manager',
      'lm_id': _metadata.id,
      'lm_cat': _metadata.category.name,
      'lm_type': _metadata.licenseType,
      'lm_holder': _metadata.holderName,
      'lm_htype': _metadata.holderType,
      'lm_issue': LicenseDate.format(
        _metadata.issueDate,
        field: LicenseField.issueDate,
      ),
      'lm_exp': LicenseDate.format(
        _metadata.expirationDate,
        field: LicenseField.expirationDate,
      ),
      'lm_issuer': _metadata.issuer,
      if (encryptedLicenseNumber != null)
        'lm_num': encryptedLicenseNumber!.encoded,
      if (encryptedLicenseNumber != null &&
          encryptedLicenseNumber!.keyVersion > 1)
        'lm_key': '${encryptedLicenseNumber!.keyVersion}',
      if (_metadata.locationNote != null) 'lm_loc': _metadata.locationNote!,
    };
    _checkSize(map);
    return Map.unmodifiable(map);
  }

  /// Restores metadata; plaintext is supplied only after a separate T3 decrypt.
  ///
  /// Without a decrypted value the number stays null, even when ciphertext is
  /// present. A missing key must not turn ciphertext into a displayed number.
  License toLicense({String? decryptedLicenseNumber}) {
    if (decryptedLicenseNumber != null && encryptedLicenseNumber == null) {
      throw const LicenseValidationException(
        LicenseField.licenseNumber,
        LicenseValidationCode.unexpectedDecryptedNumber,
      );
    }
    return _metadata.withLicenseNumber(decryptedLicenseNumber);
  }

  static void _checkSize(Map<String, String> map) {
    if (utf8.encode(jsonEncode(map)).length > maxBytes) {
      throw const LicenseValidationException(
        LicenseField.payload,
        LicenseValidationCode.payloadTooLarge,
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is LicensePayload &&
      other._metadata == _metadata &&
      other.encryptedLicenseNumber == encryptedLicenseNumber;

  @override
  int get hashCode => Object.hash(_metadata, encryptedLicenseNumber);

  @override
  String toString() => 'LicensePayload(schemaVersion: 1)';
}
