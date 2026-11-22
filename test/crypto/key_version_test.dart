import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:license_manager/shared/models/encrypted_license_number.dart';
import 'package:license_manager/shared/models/license_validation.dart';
import 'package:license_manager/shared/models/payload.dart';

import '../support/crypto_support.dart';

void main() {
  // Synthetic envelope-format bytes only; no cryptographic keys are fixtures.
  final encoded = 'v1.${base64Url.encode(List.filled(40, 0))}';
  Map<String, String> legacy() => LicensePayload.fromLicense(
    cryptoLicense(),
    encryptedLicenseNumber: EncryptedLicenseNumber.parse(encoded),
  ).toMap();

  test('legacy payloads keep exactly the v1 contract', () {
    final wire = legacy();
    expect(wire.containsKey('lm_key'), isFalse);
    final parsed = LicensePayload.fromMap(wire);
    expect(parsed.encryptedLicenseNumber!.keyVersion, 1);
    expect(parsed.toMap(), wire);
    expect(LicensePayload.fromMap({...wire, 'lm_key': '1'}).toMap(), wire);
  });

  test(
    'rotated envelopes carry key version separately from envelope v1 format',
    () {
      final envelope = EncryptedLicenseNumber.parse(encoded, keyVersion: 2);
      final wire = LicensePayload.fromLicense(
        cryptoLicense(),
        encryptedLicenseNumber: envelope,
      ).toMap();
      expect(wire['lm_key'], '2');
      expect(wire['lm_v'], '1');
      expect(wire['lm_num']!.startsWith('v1.'), isTrue);
      expect(LicensePayload.fromMap(wire).encryptedLicenseNumber, envelope);
      expect(envelope == EncryptedLicenseNumber.parse(encoded), isFalse);
    },
  );

  test(
    'key versions are canonical, positive, bounded, and require ciphertext',
    () {
      for (final bad in ['0', '-1', '01', '1.0', '2\n', '2147483648', '']) {
        expect(
          () => LicensePayload.fromMap({...legacy(), 'lm_key': bad}),
          throwsA(
            isA<LicenseValidationException>().having(
              (e) => e.field,
              'field',
              LicenseField.keyVersion,
            ),
          ),
        );
      }
      final noNumber = LicensePayload.fromLicense(cryptoLicense(number: null))
          .toMap();
      expect(
        () => LicensePayload.fromMap({...noNumber, 'lm_key': '2'}),
        throwsA(isA<LicenseValidationException>()),
      );
      for (final bad in [null, 2, false]) {
        expect(
          () => LicensePayload.fromMap({...legacy(), 'lm_key': bad}),
          throwsA(isA<LicenseValidationException>()),
        );
      }
      for (final bad in [0, -1, EncryptedLicenseNumber.maxKeyVersion + 1]) {
        expect(
          () => EncryptedLicenseNumber.parse(encoded, keyVersion: bad),
          throwsA(isA<LicenseValidationException>()),
        );
      }
    },
  );

  test(
    'rotation metadata is included in the existing UTF-8 payload budget',
    () {
      Map<String, Object?>? boundary;
      for (var length = 29; length < 800 && boundary == null; length++) {
        final number = 'v1.${base64Url.encode(List.filled(length, 0))}';
        for (var padding = 0; padding < 4; padding++) {
          final candidate = <String, Object?>{
            ...legacy(),
            'lm_num': number,
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
      expect(LicensePayload.fromMap(accepted).toMap(), accepted);
      expect(
        () => LicensePayload.fromMap({...accepted, 'lm_key': '2'}),
        throwsA(
          isA<LicenseValidationException>().having(
            (error) => error.code,
            'code',
            LicenseValidationCode.payloadTooLarge,
          ),
        ),
      );
    },
  );
}
