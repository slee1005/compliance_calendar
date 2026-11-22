import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:license_manager/shared/models/encrypted_license_number.dart';
import 'package:license_manager/shared/models/license.dart';
import 'package:license_manager/shared/models/license_category.dart';
import 'package:license_manager/shared/models/license_validation.dart';
import 'package:license_manager/shared/models/payload.dart';

const _id = '96db7b78-58ba-465d-bd21-a5340b552c8a';

// Synthetic transport bytes only: these are not keys, tokens, or encryption.
String _envelope([int length = 40]) =>
    'v1.${base64Url.encode(List.generate(length, (i) => i % 256)).replaceAll('=', '')}';

License _license({String? number, String? location}) => License(
  id: _id,
  category: LicenseCategory.professionalLicense,
  licenseType: 'Example permit',
  holderName: 'Example alias',
  holderType: 'staff',
  issueDate: DateTime.utc(2024, 1, 1),
  expirationDate: DateTime.utc(2028, 12, 31),
  issuer: 'Example issuer',
  licenseNumber: number,
  locationNote: location,
);

Map<String, Object?> _map() => {
  'lm_v': '1',
  'lm_app': 'license_manager',
  'lm_id': _id,
  'lm_cat': 'professionalLicense',
  'lm_type': 'Example permit',
  'lm_holder': 'Example alias',
  'lm_htype': 'staff',
  'lm_issue': '2024-01-01',
  'lm_exp': '2028-12-31',
  'lm_issuer': 'Example issuer',
};

Matcher _failure(LicenseField field, LicenseValidationCode code) => throwsA(
  isA<LicenseValidationException>()
      .having((error) => error.field, 'field', field)
      .having((error) => error.code, 'code', code),
);

void main() {
  group('master Calendar payload', () {
    test('exact string-only wire contract and metadata round trip', () {
      final payload = LicensePayload.fromLicense(_license());
      expect(payload.toMap(), _map());
      expect(payload.toMap(), hasLength(10));
      expect(payload.toMap().keys.every((key) => key.length <= 44), isTrue);
      expect(LicensePayload.fromMap(payload.toMap()).toLicense(), _license());
      expect(payload.encryptedLicenseNumber, isNull);
      expect(LicensePayload.fromMap(payload.toMap()), payload);
      expect(
        LicensePayload.fromMap(payload.toMap()).hashCode,
        payload.hashCode,
      );
      expect(
        () => payload.toMap()['ssn'] = 'DISALLOWED',
        throwsUnsupportedError,
      );
    });

    test('the contract survives actual JSON encoding and decoding', () {
      final payload = LicensePayload.fromLicense(
        _license(location: 'Example shelf'),
      );
      final decoded =
          jsonDecode(jsonEncode(payload.toMap())) as Map<String, dynamic>;
      expect(LicensePayload.fromMap(decoded), payload);
      expect(
        LicensePayload.fromMap(decoded).toLicense().locationNote,
        'Example shelf',
      );
    });

    test('number transport retains only a typed opaque envelope', () {
      final original = _license(
        number: 'MEMORY-ONLY',
        location: 'Example shelf',
      );
      final envelope = EncryptedLicenseNumber.parse(_envelope());
      final payload = LicensePayload.fromLicense(
        original,
        encryptedLicenseNumber: envelope,
      );
      final wire = payload.toMap();
      expect(wire['lm_num'], envelope.encoded);
      expect(wire['lm_loc'], 'Example shelf');
      expect(jsonEncode(wire), isNot(contains('MEMORY-ONLY')));
      expect(payload.toLicense().licenseNumber, isNull);
      final restored = LicensePayload.fromMap(wire);
      expect(restored.encryptedLicenseNumber, envelope);
      expect(restored.toLicense().licenseNumber, isNull);
      expect(
        restored.toLicense(decryptedLicenseNumber: 'MEMORY-ONLY'),
        original,
      );
      expect(original.licenseNumber, 'MEMORY-ONLY');
    });

    test(
      'there is no implicit plaintext, lost-number, or stale-number fallback',
      () {
        expect(
          () => LicensePayload.fromLicense(_license(number: 'MEMORY-ONLY')),
          _failure(
            LicenseField.licenseNumber,
            LicenseValidationCode.encryptionRequired,
          ),
        );
        expect(
          () => LicensePayload.fromLicense(
            _license(),
            encryptedLicenseNumber: EncryptedLicenseNumber.parse(_envelope()),
          ),
          _failure(
            LicenseField.licenseNumber,
            LicenseValidationCode.unexpectedEncryptedNumber,
          ),
        );
        expect(
          () =>
              LicensePayload.fromLicense(_license())
                  .toLicense(decryptedLicenseNumber: 'MEMORY-ONLY'),
          _failure(
            LicenseField.licenseNumber,
            LicenseValidationCode.unexpectedDecryptedNumber,
          ),
        );
        expect(
          () => LicensePayload.fromMap({..._map(), 'lm_num': 'MEMORY-ONLY'}),
          _failure(
            LicenseField.licenseNumber,
            LicenseValidationCode.invalidEnvelope,
          ),
        );
      },
    );

    test(
      'absent optional keys and an explicitly empty location stay distinct',
      () {
        expect(
          LicensePayload.fromLicense(_license()).toMap().containsKey('lm_loc'),
          isFalse,
        );
        final wire = {..._map(), 'lm_loc': ''};
        expect(LicensePayload.fromMap(wire).toMap(), wire);
      },
    );

    for (final category in LicenseCategory.values) {
      test('round trips category ${category.name}', () {
        final wire = {..._map(), 'lm_cat': category.name};
        expect(LicensePayload.fromMap(wire).toLicense().category, category);
        expect(LicensePayload.fromMap(wire).toMap(), wire);
      });
    }

    test('business ownership round trips without conversion to staff', () {
      final wire = {..._map(), 'lm_htype': 'business'};
      expect(LicensePayload.fromMap(wire).toLicense().holderType, 'business');
      expect(LicensePayload.fromMap(wire).toMap(), wire);
    });

    const requiredFields = {
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
    };
    for (final entry in requiredFields.entries) {
      test('missing ${entry.key} is a field-specific failure', () {
        final wire = _map()..remove(entry.key);
        expect(
          () => LicensePayload.fromMap(wire),
          _failure(entry.value, LicenseValidationCode.required),
        );
      });
      test('non-string ${entry.key} is not coerced', () {
        expect(
          () => LicensePayload.fromMap({..._map(), entry.key: 1}),
          _failure(entry.value, LicenseValidationCode.wrongType),
        );
      });
    }

    test(
      'optional keys must be absent or strings, never null or other types',
      () {
        for (final bad in [null, 123, false, <int>[]]) {
          expect(
            () => LicensePayload.fromMap({..._map(), 'lm_num': bad}),
            _failure(
              LicenseField.licenseNumber,
              LicenseValidationCode.wrongType,
            ),
          );
          expect(
            () => LicensePayload.fromMap({..._map(), 'lm_loc': bad}),
            _failure(
              LicenseField.locationNote,
              LicenseValidationCode.wrongType,
            ),
          );
        }
      },
    );

    for (final key in [
      'ssn',
      'dateOfBirth',
      'photo',
      'document',
      'memo',
      'lm_stage',
    ]) {
      test(
        'rejects unrecognized property $key instead of forwarding or dropping it',
        () {
          expect(
            () => LicensePayload.fromMap({..._map(), key: 'DISALLOWED'}),
            _failure(
              LicenseField.payload,
              LicenseValidationCode.unexpectedField,
            ),
          );
        },
      );
    }

    test('versions, app tags, and categories have no fallback behavior', () {
      expect(
        () => LicensePayload.fromMap({..._map(), 'lm_v': '2'}),
        _failure(
          LicenseField.schemaVersion,
          LicenseValidationCode.unsupportedVersion,
        ),
      );
      expect(
        () => LicensePayload.fromMap({..._map(), 'lm_app': 'another_app'}),
        _failure(LicenseField.payload, LicenseValidationCode.invalidChoice),
      );
      expect(
        () => LicensePayload.fromMap({..._map(), 'lm_cat': 'unknown'}),
        _failure(LicenseField.category, LicenseValidationCode.invalidChoice),
      );
      expect(
        () => LicensePayload.fromMap({..._map(), 'lm_htype': 'administrator'}),
        _failure(LicenseField.holderType, LicenseValidationCode.invalidChoice),
      );
    });

    test(
      'wire dates and metadata are validated before a record is restored',
      () {
        expect(
          () => LicensePayload.fromMap({..._map(), 'lm_id': 'not-an-id'}),
          _failure(LicenseField.id, LicenseValidationCode.invalidUuid),
        );
        expect(
          () => LicensePayload.fromMap({..._map(), 'lm_issue': '2026-02-30'}),
          _failure(LicenseField.issueDate, LicenseValidationCode.invalidDate),
        );
        expect(
          () => LicensePayload.fromMap({..._map(), 'lm_exp': '2026-04-31'}),
          _failure(
            LicenseField.expirationDate,
            LicenseValidationCode.invalidDate,
          ),
        );
        expect(
          () => LicensePayload.fromMap({..._map(), 'lm_exp': '2023-12-31'}),
          _failure(
            LicenseField.expirationDate,
            LicenseValidationCode.dateOrder,
          ),
        );
        expect(
          () => LicensePayload.fromMap({
            ..._map(),
            'lm_type': List.filled(61, 'x').join(),
          }),
          _failure(LicenseField.licenseType, LicenseValidationCode.tooLong),
        );
      },
    );

    test('UTF-8 budget rejects multibyte metadata without truncating it', () {
      final wire = {
        ..._map(),
        'lm_type': List.filled(60, '가').join(),
        'lm_holder': List.filled(60, '나').join(),
        'lm_issuer': List.filled(80, '다').join(),
        'lm_loc': List.filled(120, '라').join(),
      };
      final record = License(
        id: _id,
        category: LicenseCategory.professionalLicense,
        licenseType: wire['lm_type']! as String,
        holderName: wire['lm_holder']! as String,
        holderType: 'staff',
        issueDate: DateTime.utc(2024, 1, 1),
        expirationDate: DateTime.utc(2028, 12, 31),
        issuer: wire['lm_issuer']! as String,
        locationNote: wire['lm_loc']! as String,
      );
      expect(record.validate, returnsNormally);
      expect(
        utf8.encode(jsonEncode(wire)).length,
        greaterThan(LicensePayload.maxBytes),
      );
      expect(
        () => LicensePayload.fromMap(wire),
        _failure(LicenseField.payload, LicenseValidationCode.payloadTooLarge),
      );
      expect(
        () => LicensePayload.fromLicense(record),
        _failure(LicenseField.payload, LicenseValidationCode.payloadTooLarge),
      );
      expect(record.locationNote!.runes.length, 120);
    });

    test('exactly 1024 UTF-8 JSON bytes are accepted; 1025 are rejected', () {
      Map<String, Object?>? boundary;
      for (var length = 29; length < 800 && boundary == null; length++) {
        for (var padding = 0; padding < 4; padding++) {
          final candidate = {
            ..._map(),
            'lm_num': _envelope(length),
            'lm_loc': List.filled(padding, 'x').join(),
          };
          if (utf8.encode(jsonEncode(candidate)).length ==
              LicensePayload.maxBytes) {
            boundary = candidate;
            break;
          }
        }
      }
      expect(boundary, isNotNull);
      final accepted = boundary!;
      final payload = LicensePayload.fromMap(accepted);
      expect(payload.toMap(), accepted);
      expect(utf8.encode(jsonEncode(payload.toMap())).length, 1024);
      final record = payload.toLicense(decryptedLicenseNumber: 'MEMORY-ONLY');
      expect(
        LicensePayload.fromLicense(
          record,
          encryptedLicenseNumber: payload.encryptedLicenseNumber,
        ).toMap(),
        accepted,
      );
      final oversized = {...accepted, 'lm_loc': '${accepted['lm_loc']}x'};
      expect(utf8.encode(jsonEncode(oversized)).length, 1025);
      expect(
        () => LicensePayload.fromMap(oversized),
        _failure(LicenseField.payload, LicenseValidationCode.payloadTooLarge),
      );
    });

    test('payload diagnostics contain neither metadata nor ciphertext', () {
      final payload = LicensePayload.fromLicense(
        _license(number: 'MEMORY-ONLY'),
        encryptedLicenseNumber: EncryptedLicenseNumber.parse(_envelope()),
      );
      for (final value in [
        _id,
        'Example alias',
        'Example issuer',
        'MEMORY-ONLY',
        _envelope(),
      ]) {
        expect(payload.toString(), isNot(contains(value)));
      }
    });
  });

  group('opaque envelope syntax, not cryptographic authentication', () {
    test('accepts and preserves padded or unpadded v1 base64url', () {
      final padded = 'v1.${base64Url.encode(List.generate(29, (i) => i))}';
      for (final value in [padded, padded.replaceAll('=', ''), _envelope(29)]) {
        final parsed = EncryptedLicenseNumber.parse(value);
        expect(parsed.encoded, value);
        expect(parsed, EncryptedLicenseNumber.parse(value));
        expect(parsed.hashCode, EncryptedLicenseNumber.parse(value).hashCode);
        expect(parsed.toString(), isNot(contains(value)));
        final wire = {..._map(), 'lm_num': value};
        expect(LicensePayload.fromMap(wire).toMap(), wire);
      }
    });

    for (final entry in [
      '',
      'MEMORY-ONLY',
      'v1.',
      'v1.A',
      _envelope(28),
      _envelope().replaceFirst('v1.', 'v2.'),
      '${_envelope()}\n',
      '${_envelope()}+',
      '${_envelope()}/',
      '${_envelope()}%',
      '${_envelope()}===',
    ].indexed) {
      test('rejects malformed envelope case ${entry.$1}', () {
        expect(
          () => EncryptedLicenseNumber.parse(entry.$2),
          _failure(
            LicenseField.licenseNumber,
            LicenseValidationCode.invalidEnvelope,
          ),
        );
      });
    }

    test('rejects noncanonical trailing base64 bits and oversized values', () {
      final valid =
          'v1.${base64Url.encode(List.filled(29, 0)).replaceAll('=', '')}';
      final noncanonical = '${valid.substring(0, valid.length - 1)}B';
      expect(
        () => EncryptedLicenseNumber.parse(noncanonical),
        _failure(
          LicenseField.licenseNumber,
          LicenseValidationCode.invalidEnvelope,
        ),
      );
      expect(
        () =>
            EncryptedLicenseNumber.parse('v1.${List.filled(1022, 'A').join()}'),
        _failure(LicenseField.licenseNumber, LicenseValidationCode.tooLong),
      );
    });
  });
}
