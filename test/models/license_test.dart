import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:license_manager/shared/models/license.dart';
import 'package:license_manager/shared/models/license_category.dart';
import 'package:license_manager/shared/models/license_validation.dart';

const _id = '96db7b78-58ba-465d-bd21-a5340b552c8a';

String _repeat(String value, int count) => List.filled(count, value).join();

License _license({
  String id = _id,
  String licenseType = 'Example permit',
  String holderName = 'Example alias',
  String holderType = 'staff',
  String issuer = 'Example issuer',
  DateTime? issueDate,
  DateTime? expirationDate,
  String? licenseNumber,
  String? locationNote,
  int schemaVersion = 1,
}) => License(
  id: id,
  category: LicenseCategory.businessPermit,
  licenseType: licenseType,
  holderName: holderName,
  holderType: holderType,
  issueDate: issueDate ?? DateTime.utc(2024, 1, 1),
  expirationDate: expirationDate ?? DateTime.utc(2028, 12, 31),
  issuer: issuer,
  licenseNumber: licenseNumber,
  locationNote: locationNote,
  schemaVersion: schemaVersion,
);

Matcher _failure(LicenseField field, LicenseValidationCode code) => throwsA(
  isA<LicenseValidationException>()
      .having((error) => error.field, 'field', field)
      .having((error) => error.code, 'code', code),
);

void main() {
  group('License v1 validation', () {
    test(
      'valid metadata has exact types, optional fields, and value equality',
      () {
        final record = _license();
        expect(record.schemaVersion, 1);
        expect(record.licenseNumber, isNull);
        expect(record.locationNote, isNull);
        expect(record.issueDate.isUtc, isTrue);
        expect(record, _license());
        expect(record.hashCode, _license().hashCode);
        expect(record, isNot(_license(holderType: 'business')));
        expect(record, isNot(_license(issuer: 'Other example issuer')));
        expect(record.validate, returnsNormally);
      },
    );

    test('maximum text lengths and Unicode scalars are accepted', () {
      final record = _license(
        licenseType: _repeat('가', 60),
        holderName: _repeat('😀', 60),
        issuer: _repeat('나', 80),
        locationNote: _repeat('다', 120),
      );
      expect(record.holderName.runes.length, 60);
      expect(record.validate, returnsNormally);
      expect(_license(locationNote: '').locationNote, '');
    });

    test('text is not silently trimmed or truncated', () {
      final record = _license(holderName: ' Example alias ');
      expect(record.holderName, ' Example alias ');
      expect(
        () => _license(licenseType: _repeat('가', 61)),
        _failure(LicenseField.licenseType, LicenseValidationCode.tooLong),
      );
      expect(
        () => _license(holderName: _repeat('😀', 61)),
        _failure(LicenseField.holderName, LicenseValidationCode.tooLong),
      );
      expect(
        () => _license(issuer: _repeat('a', 81)),
        _failure(LicenseField.issuer, LicenseValidationCode.tooLong),
      );
      expect(
        () => _license(locationNote: _repeat('b', 121)),
        _failure(LicenseField.locationNote, LicenseValidationCode.tooLong),
      );
    });

    test('required text and a provided number must not be blank', () {
      expect(
        () => _license(licenseType: ''),
        _failure(LicenseField.licenseType, LicenseValidationCode.required),
      );
      expect(
        () => _license(holderName: '  '),
        _failure(LicenseField.holderName, LicenseValidationCode.required),
      );
      expect(
        () => _license(issuer: '\t'),
        _failure(LicenseField.issuer, LicenseValidationCode.required),
      );
      expect(
        () => _license(licenseNumber: ''),
        _failure(LicenseField.licenseNumber, LicenseValidationCode.required),
      );
    });

    for (final bad in [
      'Permit\nextra',
      'Permit\r',
      'Permit\u0000',
      'Permit\u2028',
    ]) {
      test('rejects control characters in type ${bad.codeUnits}', () {
        expect(
          () => _license(licenseType: bad),
          _failure(LicenseField.licenseType, LicenseValidationCode.invalidText),
        );
      });
    }

    test('rejects controls in all other text and invalid Unicode scalars', () {
      expect(
        () => _license(holderName: 'Alias\nnext'),
        _failure(LicenseField.holderName, LicenseValidationCode.invalidText),
      );
      expect(
        () => _license(issuer: 'Issuer\u007f'),
        _failure(LicenseField.issuer, LicenseValidationCode.invalidText),
      );
      expect(
        () => _license(locationNote: 'Shelf\tA'),
        _failure(LicenseField.locationNote, LicenseValidationCode.invalidText),
      );
      expect(
        () => _license(licenseNumber: 'MEMORY\nONLY'),
        _failure(LicenseField.licenseNumber, LicenseValidationCode.invalidText),
      );
      expect(
        () => _license(holderName: String.fromCharCode(0xd800)),
        _failure(LicenseField.holderName, LicenseValidationCode.invalidText),
      );
    });

    for (final entry in [
      '',
      'not-a-record-id',
      '00000000-0000-0000-0000-000000000000',
      '96db7b78-58ba-165d-bd21-a5340b552c8a',
      '96db7b78-58ba-465d-7d21-a5340b552c8a',
      '${_id}0',
      '$_id\n',
    ].indexed) {
      test('rejects malformed or non-v4 UUID case ${entry.$1}', () {
        expect(
          () => _license(id: entry.$2),
          _failure(LicenseField.id, LicenseValidationCode.invalidUuid),
        );
      });
    }

    test('UUID hexadecimal case is preserved', () {
      expect(_license(id: _id.toUpperCase()).id, _id.toUpperCase());
    });

    for (final bad in ['', 'manager', 'Staff', 'business\n']) {
      test('holder type is an exact allowlist: ${bad.codeUnits}', () {
        expect(
          () => _license(holderType: bad),
          _failure(
            LicenseField.holderType,
            LicenseValidationCode.invalidChoice,
          ),
        );
      });
    }

    test('rejects unsupported schema versions', () {
      for (final version in [0, 2, -1]) {
        expect(
          () => _license(schemaVersion: version),
          _failure(
            LicenseField.schemaVersion,
            LicenseValidationCode.unsupportedVersion,
          ),
        );
      }
    });

    test('expiration can equal issuance but cannot precede it', () {
      final sameDay = DateTime.utc(2024, 2, 29);
      expect(
        _license(issueDate: sameDay, expirationDate: sameDay).validate,
        returnsNormally,
      );
      expect(
        () => _license(issueDate: DateTime.utc(2029)),
        _failure(LicenseField.expirationDate, LicenseValidationCode.dateOrder),
      );
    });

    test('copying a memory-only number never changes the original record', () {
      final record = _license(licenseNumber: 'MEMORY-ONLY');
      final cleared = record.withLicenseNumber(null);
      expect(cleared.licenseNumber, isNull);
      expect(record.licenseNumber, 'MEMORY-ONLY');
      expect(cleared.withLicenseNumber('MEMORY-ONLY'), record);
    });

    test(
      'diagnostics redact metadata and plaintext; no JSON writer exists',
      () {
        final record = _license(
          licenseNumber: 'MEMORY-ONLY',
          locationNote: 'Example shelf',
        );
        final diagnostics = record.toString();
        for (final privateValue in [
          _id,
          record.licenseType,
          record.holderName,
          record.issuer,
          record.licenseNumber!,
          record.locationNote!,
        ]) {
          expect(diagnostics, isNot(contains(privateValue)));
        }
        expect(
          () => jsonEncode(record),
          throwsA(isA<JsonUnsupportedObjectError>()),
        );
        try {
          _license(id: 'INPUT-MUST-NOT-APPEAR');
          fail('Expected validation failure');
        } on LicenseValidationException catch (error) {
          expect(error.toString(), isNot(contains('INPUT-MUST-NOT-APPEAR')));
        }
      },
    );
  });

  group('calendar dates', () {
    for (final date in [
      '0001-01-01',
      '2000-02-29',
      '2024-02-29',
      '9999-12-31',
    ]) {
      test('strict round trip for $date', () {
        final value = LicenseDate.parse(date, field: LicenseField.issueDate);
        expect(value.isUtc, isTrue);
        expect(value.hour, 0);
        expect(LicenseDate.format(value, field: LicenseField.issueDate), date);
      });
    }
    for (final bad in [
      '',
      '2026-02-29',
      '1900-02-29',
      '2024-04-31',
      '2024-00-01',
      '2024-13-01',
      '2024-01-00',
      '2024-01-32',
      '0000-01-01',
      '2024-2-01',
      '2024/02/01',
      '2024-02-01T00:00:00Z',
      '2024-02-01+09:00',
      '2024-02-01\n',
      ' 2024-02-01',
    ]) {
      test('rejects invalid calendar input ${bad.codeUnits}', () {
        expect(
          () => LicenseDate.parse(bad, field: LicenseField.issueDate),
          _failure(LicenseField.issueDate, LicenseValidationCode.invalidDate),
        );
      });
    }
    test('both date fields reject local time and non-midnight UTC values', () {
      for (final bad in [
        DateTime(2024),
        DateTime.utc(2024, 1, 1, 1),
        DateTime.utc(2024, 1, 1, 0, 1),
        DateTime.utc(2024, 1, 1, 0, 0, 1),
        DateTime.utc(2024, 1, 1, 0, 0, 0, 1),
        DateTime.utc(2024, 1, 1, 0, 0, 0, 0, 1),
      ]) {
        expect(
          () => _license(issueDate: bad),
          _failure(LicenseField.issueDate, LicenseValidationCode.notDateOnly),
        );
        expect(
          () => _license(expirationDate: bad),
          _failure(
            LicenseField.expirationDate,
            LicenseValidationCode.notDateOnly,
          ),
        );
      }
      for (final bad in [
        DateTime.utc(0),
        DateTime.utc(-1),
        DateTime.utc(10000),
      ]) {
        expect(
          () => _license(issueDate: bad),
          _failure(LicenseField.issueDate, LicenseValidationCode.invalidDate),
        );
      }
    });
  });

  test('category wire names are exact and have no unknown fallback', () {
    expect(LicenseCategory.values.map((v) => v.name), [
      'businessPermit',
      'professionalLicense',
      'insurance',
      'safetyTraining',
      'facilityPermit',
      'other',
    ]);
    for (final category in LicenseCategory.values) {
      expect(LicenseCategory.tryParse(category.name), category);
    }
    expect(LicenseCategory.tryParse('OTHER'), isNull);
    expect(LicenseCategory.tryParse('unknown'), isNull);
  });
}
