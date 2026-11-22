/// The planner's stable category names, also used as Calendar wire values.
enum LicenseCategory {
  /// Business operating permits.
  businessPermit,

  /// Professional staff licenses.
  professionalLicense,

  /// Insurance coverage and certificates.
  insurance,

  /// Safety or continuing education credentials.
  safetyTraining,

  /// Facility permits.
  facilityPermit,

  /// Credentials outside the predefined categories.
  other;

  /// Returns only exact schema names; unknown values have no fallback category.
  static LicenseCategory? tryParse(String value) {
    for (final category in values) {
      if (category.name == value) return category;
    }
    return null;
  }
}
