# T2 데이터 모델 계약

원문 플래너 v1.2의 7.2 스키마와 7.5의 1KB payload 한도를 구현한다. 이 모델 계층은 순수 Dart 검증·직렬화이며, 저장·암호화·Google API 호출은 수행하지 않는다. 실제 암호화는 T3의 `core/crypto`에서 처리한다. 예시 UI의 `DemoCredential`과 운영 모델은 분리한다.

## 파일과 책임

| 파일 | 책임 |
|---|---|
| `lib/shared/models/license_category.dart` | 원문 6개 enum과 정확한 wire 이름 |
| `lib/shared/models/license.dart` | 불변 `License`, 런타임 검증, 메모리 전용 번호 |
| `lib/shared/models/license_validation.dart` | 값이 없는 필드·오류 코드, 엄격한 달력 날짜 변환 |
| `lib/shared/models/encrypted_license_number.dart` | 불투명한 `v1.<base64url>` 봉투 형식 검증 |
| `lib/shared/models/payload.dart` | `LicensePayload.fromLicense/fromMap/toMap/toLicense` |

## 입력 검증

- `id`: UUID v4, 올바른 variant. 대·소문자 hex는 허용하고 원래 표기를 보존한다.
- `category`: 원문의 enum 6개. 미지의 값을 `other`로 바꾸지 않는다.
- `holderType`: `staff` 또는 `business`만 허용한다.
- `licenseType` / `holderName` / `issuer`: 필수, 각각 60 / 60 / 80 Unicode scalar 이내.
- `locationNote`: 선택, 0~120 Unicode scalar. 누락(`null`)과 명시적 빈 문자열은 구분한다.
- 업무 텍스트는 한 줄로 제한하고 제어 문자·잘못된 Unicode scalar를 거부한다. 값을 조용히 자르거나 공백을 제거하지 않는다.
- 번호는 생략 가능하다. 제공했다면 빈 값·제어 문자는 거부한다. 평문 번호는 메모리에만 유지한다.
- 날짜는 **UTC 자정의 DateTime**으로만 받는다. 현지 시각·시/분/초·밀리초·마이크로초가 들어간 값은 거부한다. 지원 연도는 0001~9999다.
- `YYYY-MM-DD` 파서는 윤년과 실제 일자를 확인한다. `2026-02-30`을 3월로 넘기는 DateTime의 자동 보정에 의존하지 않는다.
- `expirationDate >= issueDate`, `schemaVersion == 1`을 강제한다.

검증은 `assert`에 의존하지 않는다. 실패 시 `LicenseValidationException(field, code)`를 던진다. 오류와 모델의 `toString()`에 입력값·이름·번호·발급기관·보관 위치를 포함하지 않는다. 후속 입력 폼은 field/code를 사용자 언어로 변환한다.

## 번호를 저장용 구조와 분리

`License`에는 `toMap`·`toJson`을 두지 않았다. 저장용 구조는 `LicensePayload` 한 곳에서 만든다.

```dart
// 번호가 없으면 메타데이터만 직렬화한다.
final payload = LicensePayload.fromLicense(licenseWithoutNumber);
final wire = payload.toMap();
final restored = LicensePayload.fromMap(wire).toLicense();

// 번호가 있으면 T3의 암호화 결과가 별도로 필요하다.
final withNumber = LicensePayload.fromLicense(
  licenseWithNumber,
  encryptedLicenseNumber: encryptedEnvelopeFromT3,
);
```

평문 번호가 있는데 암호문을 주지 않으면 `encryptionRequired`로 거부한다. 번호를 지웠는데 이전 암호문을 주는 경우에도 거부한다. payload 객체에는 평문 번호를 보관하지 않는다. T3 이후에는 `FieldCipher.encryptPayload(license)`로 실제 암호화와 payload 생성을 함께 수행할 수 있다.

`fromMap`으로 복원한 payload의 `toLicense()`는 번호가 `null`인 메타데이터를 반환한다. 암호문을 번호 대신 화면에 표시하지 않는다. T3에서 인증·복호화한 값만 `toLicense(decryptedLicenseNumber: ...)`로 메모리 모델에 넣는다. payload에 암호문이 없는데 복호화 값을 주면 거부한다.

봉투는 `v1.` 접두사, URL-safe base64, 최소 12B nonce + 1B ciphertext + 16B tag 구조를 확인한다. 올바른 padded/unpadded 표기는 보존한다. **이 모델의 형식 검사는 GCM 인증이 아니다.** 실제 키·nonce 생성과 위변조 검증은 `core/crypto/field_cipher.dart`가 수행한다. T2 단위 테스트의 봉투 바이트는 형식 검사 전용 가상 값이며 키·토큰·실제 면허번호가 아니다.

T3의 키 회전을 위해 `EncryptedLicenseNumber.keyVersion`을 추가했다. 기존 봉투는 기본값 1이며, 버전 2 이상은 payload의 선택 문자열 `lm_key`로 직렬화한다. 봉투의 `v1.`은 형식 버전이므로 키 회전 후에도 바뀌지 않는다. 자세한 키 수명주기는 `crypto-design.md`를 따른다.

## Calendar payload 경계

- 기본 스키마는 `lm_v`, `lm_app`, `lm_id`, `lm_cat`, `lm_type`, `lm_holder`, `lm_htype`, `lm_issue`, `lm_exp`, `lm_issuer`, 선택 `lm_num`·`lm_loc`다. T3의 키 회전 메타데이터로 선택 `lm_key`를 추가했다. 암호문이 없는 키 버전, 0·음수·비정규 표기·지원 범위 밖 버전은 거부한다.
- 모든 값은 문자열이다. 숫자·null 등을 문자열로 자동 변환하지 않는다.
- 모르는 필드는 거부한다. SSN·사진·생년월일 등 추가 필드를 통과시키거나 조용히 삭제하지 않는다.
- `lm_stage` 같은 이벤트 제어 메타데이터는 이 모델에 속하지 않는다. T10의 EventMapper가 마스터·D-30 이벤트를 구분한 후 스키마 payload와 따로 검증해야 한다.
- 반환 Map은 불변이다. 지원하지 않는 버전·앱 태그·카테고리를 대체값으로 읽지 않는다.
- compact JSON 전체를 UTF-8로 인코딩해 **1024바이트 이하**인지 읽기·쓰기 양쪽에서 확인한다. 정확히 1024바이트는 허용하고, 초과하면 저장을 거부한다. 한글·emoji와 JSON escape의 실제 바이트 수를 계산한다.
- Google의 속성별 일반 제한보다 보수적인 전체 1KB 제한은 원문의 앱 계약을 따른 것이다. Google Calendar private properties가 암호화라는 의미는 아니다. 이름·날짜·발급기관 등은 Google에서 처리된다.

## 확인

```sh
./tool/flutter test test/models
bash tool/verify.sh
```

모델·날짜·형식 오류, UUID/길이 경계, 윤년, JSON 왕복, 번호 평문 차단, 알 수 없는 필드, 1024/1025바이트 경계를 확인한다. UI 변경이 없는 단계이므로 기존 375×667 / 1440×900 및 200% 글자 크기 검사도 전체 검증에 포함한다.

수동 확인 한 줄: `./tool/flutter test test/models` 실행 후 오류와 평문 번호의 저장용 payload 유입이 거부되고, 기존 예시 UI는 실제 데이터 입력을 열지 않는지 확인한다.
