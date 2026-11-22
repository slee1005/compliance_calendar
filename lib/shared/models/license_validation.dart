/// Stable field identifiers that can be mapped to localized form labels.
enum LicenseField {
  /// The UUID v4 record identifier.
  id,

  /// The credential category.
  category,

  /// The credential's type label.
  licenseType,

  /// The holder's name or alias.
  holderName,

  /// Whether the holder is staff or a business.
  holderType,

  /// The date the credential starts.
  issueDate,

  /// The last valid calendar date.
  expirationDate,

  /// The issuing organization.
  issuer,

  /// An optional in-memory number or its encrypted envelope.
  licenseNumber,

  /// The optional location of the customer's original document.
  locationNote,

  /// The schema version.
  schemaVersion,

  /// The organization key version associated with an encrypted number.
  keyVersion,

  /// The complete Calendar property map.
  payload,
}

/// Machine-readable validation reasons; none include an invalid input value.
enum LicenseValidationCode {
  /// A required value is missing or blank.
  required,

  /// A character limit was exceeded.
  tooLong,

  /// Text contains control characters or invalid Unicode scalars.
  invalidText,

  /// An identifier is not an RFC UUID v4 with a valid variant.
  invalidUuid,

  /// A value is outside an explicit allowlist.
  invalidChoice,

  /// A date string is not a real YYYY-MM-DD calendar date.
  invalidDate,

  /// A DateTime is not a UTC midnight calendar date.
  notDateOnly,

  /// Expiration precedes issuance.
  dateOrder,

  /// A schema version is unsupported.
  unsupportedVersion,

  /// The transport value is not a structurally valid v1 number envelope.
  invalidEnvelope,

  /// A wire value is not a string.
  wrongType,

  /// The wire map contains an unrecognized field.
  unexpectedField,

  /// The complete UTF-8 JSON payload exceeds its byte limit.
  payloadTooLarge,

  /// A plaintext number was provided without an encrypted transport value.
  encryptionRequired,

  /// A ciphertext was supplied after its corresponding number was removed.
  unexpectedEncryptedNumber,

  /// A decrypted value was supplied for a payload with no encrypted number.
  unexpectedDecryptedNumber,
}

/// A form-safe failure containing a field and a code, never the input value.
final class LicenseValidationException implements Exception {
  /// Creates a failure that is safe to inspect without logging sensitive input.
  const LicenseValidationException(this.field, this.code);

  /// The affected model field.
  final LicenseField field;

  /// The reason to translate into a form error.
  final LicenseValidationCode code;

  @override
  String toString() =>
      'LicenseValidationException(${field.name}: ${code.name})';
}

/// Strict conversion between UTC-midnight DateTimes and calendar date strings.
abstract final class LicenseDate {
  static final _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// Parses real calendar dates without DateTime.parse's rollover behavior.
  static DateTime parse(String value, {required LicenseField field}) {
    final match = _pattern.firstMatch(value);
    if (match == null || match.end != value.length) {
      throw LicenseValidationException(
        field,
        LicenseValidationCode.invalidDate,
      );
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) {
      throw LicenseValidationException(
        field,
        LicenseValidationCode.invalidDate,
      );
    }
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      throw LicenseValidationException(
        field,
        LicenseValidationCode.invalidDate,
      );
    }
    return date;
  }

  /// Rejects local time, time-of-day values, and years outside 0001..9999.
  static void validate(DateTime value, {required LicenseField field}) {
    if (value.year < 1 || value.year > 9999) {
      throw LicenseValidationException(
        field,
        LicenseValidationCode.invalidDate,
      );
    }
    if (!value.isUtc ||
        value.hour != 0 ||
        value.minute != 0 ||
        value.second != 0 ||
        value.millisecond != 0 ||
        value.microsecond != 0) {
      throw LicenseValidationException(
        field,
        LicenseValidationCode.notDateOnly,
      );
    }
  }

  /// Formats a validated calendar date without changing its time zone or day.
  static String format(DateTime value, {required LicenseField field}) {
    validate(value, field: field);
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
