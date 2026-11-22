import 'license_category.dart';
import 'license_validation.dart';

/// Immutable credential metadata. Plaintext numbers exist in memory only.
///
/// This type deliberately has no Map/JSON persistence method. Calendar writes
/// must go through LicensePayload with a separate encrypted number envelope.
final class License {
  /// Validates schema v1 at runtime, including in release builds.
  factory License({
    required String id,
    required LicenseCategory category,
    required String licenseType,
    required String holderName,
    required String holderType,
    required DateTime issueDate,
    required DateTime expirationDate,
    required String issuer,
    String? licenseNumber,
    String? locationNote,
    int schemaVersion = 1,
  }) {
    final license = License._(
      id: id,
      category: category,
      licenseType: licenseType,
      holderName: holderName,
      holderType: holderType,
      issueDate: issueDate,
      expirationDate: expirationDate,
      issuer: issuer,
      licenseNumber: licenseNumber,
      locationNote: locationNote,
      schemaVersion: schemaVersion,
    );
    license.validate();
    return license;
  }

  const License._({
    required this.id,
    required this.category,
    required this.licenseType,
    required this.holderName,
    required this.holderType,
    required this.issueDate,
    required this.expirationDate,
    required this.issuer,
    required this.licenseNumber,
    required this.locationNote,
    required this.schemaVersion,
  });

  static final _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static final _controls = RegExp(r'[\x00-\x1f\x7f\u0085\u2028\u2029]');

  /// UUID v4 used to correlate the master Calendar event.
  final String id;

  /// One of the planner's six category values.
  final LicenseCategory category;

  /// Type label, 1..60 Unicode scalars on one line.
  final String licenseType;

  /// Holder name or alias, 1..60 Unicode scalars on one line.
  final String holderName;

  /// Exactly `staff` or `business`.
  final String holderType;

  /// Issuance calendar date, UTC midnight.
  final DateTime issueDate;

  /// Expiration calendar date, UTC midnight, no earlier than issuance.
  final DateTime expirationDate;

  /// Issuer label, 1..80 Unicode scalars on one line.
  final String issuer;

  /// Optional plaintext number. Never serialize this field directly.
  final String? licenseNumber;

  /// Optional original-document location, at most 120 Unicode scalars.
  final String? locationNote;

  /// The currently supported schema version, 1.
  final int schemaVersion;

  /// Rechecks the immutable record and throws a value-free form error.
  void validate() {
    if (schemaVersion != 1) {
      throw const LicenseValidationException(
        LicenseField.schemaVersion,
        LicenseValidationCode.unsupportedVersion,
      );
    }
    final match = _uuidV4.firstMatch(id);
    if (match == null || match.end != id.length) {
      throw const LicenseValidationException(
        LicenseField.id,
        LicenseValidationCode.invalidUuid,
      );
    }
    if (holderType != 'staff' && holderType != 'business') {
      throw const LicenseValidationException(
        LicenseField.holderType,
        LicenseValidationCode.invalidChoice,
      );
    }
    _text(licenseType, LicenseField.licenseType, max: 60);
    _text(holderName, LicenseField.holderName, max: 60);
    _text(issuer, LicenseField.issuer, max: 80);
    if (locationNote != null) {
      _text(
        locationNote!,
        LicenseField.locationNote,
        max: 120,
        allowEmpty: true,
      );
    }
    if (licenseNumber != null) {
      _text(licenseNumber!, LicenseField.licenseNumber);
    }
    LicenseDate.validate(issueDate, field: LicenseField.issueDate);
    LicenseDate.validate(expirationDate, field: LicenseField.expirationDate);
    if (expirationDate.isBefore(issueDate)) {
      throw const LicenseValidationException(
        LicenseField.expirationDate,
        LicenseValidationCode.dateOrder,
      );
    }
  }

  /// Copies metadata with a decrypted number, or removes it from memory views.
  License withLicenseNumber(String? value) => License(
    id: id,
    category: category,
    licenseType: licenseType,
    holderName: holderName,
    holderType: holderType,
    issueDate: issueDate,
    expirationDate: expirationDate,
    issuer: issuer,
    licenseNumber: value,
    locationNote: locationNote,
    schemaVersion: schemaVersion,
  );

  static void _text(
    String value,
    LicenseField field, {
    int? max,
    bool allowEmpty = false,
  }) {
    if (!allowEmpty && value.trim().isEmpty) {
      throw LicenseValidationException(field, LicenseValidationCode.required);
    }
    if (max != null && value.runes.length > max) {
      throw LicenseValidationException(field, LicenseValidationCode.tooLong);
    }
    if (_controls.hasMatch(value) ||
        value.runes.any((rune) => rune >= 0xd800 && rune <= 0xdfff)) {
      throw LicenseValidationException(
        field,
        LicenseValidationCode.invalidText,
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is License &&
      other.id == id &&
      other.category == category &&
      other.licenseType == licenseType &&
      other.holderName == holderName &&
      other.holderType == holderType &&
      other.issueDate == issueDate &&
      other.expirationDate == expirationDate &&
      other.issuer == issuer &&
      other.licenseNumber == licenseNumber &&
      other.locationNote == locationNote &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    id,
    category,
    licenseType,
    holderName,
    holderType,
    issueDate,
    expirationDate,
    issuer,
    licenseNumber,
    locationNote,
    schemaVersion,
  );

  @override
  String toString() => 'License(schemaVersion: $schemaVersion)';
}
