# T3 암호화·키 관리

원문 7.3을 `cryptography 2.9.0`과 `flutter_secure_storage 11.2.0`으로 구현한다. 암호 알고리즘을 직접 구현하지 않는다. UI·Calendar·SQLCipher·결제 SDK는 이 모듈에 포함하지 않는다.

## 구성

| 파일 | 책임 |
|---|---|
| `key_store.dart` | 보안 저장소·배타 접근 인터페이스와 값이 없는 오류 코드 |
| `os_key_store.dart` | OS 보안 저장소 옵션·서비스 격리·프로세스 간 파일 잠금 |
| `key_manager.dart` | 32바이트 CSPRNG 조직 키 생성·재읽기·회전·장애 복구 |
| `key_derivation.dart` | HKDF-SHA256 필드 키와 SQLCipher raw key 유도 |
| `field_cipher.dart` | AES-256-GCM 번호 암호화·인증 복호화·지연 재암호화 |

## 조직 키의 생명주기

- 키 슬롯은 `lm.orgKey.v1`, `lm.orgKey.v2` 순서다. 활성 포인터 `lm.orgKey.activeVersion`도 보안 저장소에 둔다.
- `initialize()`는 새 조직을 위한 명시적 호출이다. 보통 읽기·암호화 경로는 키를 만들지 않는다.
- 조직 키는 라이브러리의 CSPRNG로 32바이트를 생성한다. 키를 비밀번호나 기기 ID로 유도하지 않는다.
- 초기화·회전·읽기는 앱의 root isolate 안에서 직렬화한다. 다른 worker isolate는 키 관리자를 따로 실행하지 않고 root isolate의 서비스에 요청해야 한다. 같은 앱의 여러 프로세스는 앱 지원 디렉터리의 빈 lock 파일로 협력적 배타 접근을 수행한다. lock 파일에는 키·레코드를 쓰지 않는다.
- 새 키를 먼저 저장하고 재읽어 확인한 뒤 활성 포인터를 바꾼다. 이전 키는 삭제하지 않는다.
- 키 저장 후 포인터 기록에 실패하면 기존 키와 새 키를 모두 보존한다. 이후 활성 상태를 다시 읽어 복구한다. 포인터 기록은 성공했지만 확인 읽기에 실패한 경우에는 결과가 불확실하므로 회전을 무조건 반복하지 말고 현재 버전을 먼저 확인한다.
- 초기화 중 v1 키만 남은 경우 그 키를 재사용한다. 손상된 키·잘못된 포인터·회전 후 사라진 포인터를 새 키로 덮어쓰거나 v1으로 되돌리지 않는다.
- 운영용 메모리 저장소 폴백, 자동 키 삭제·재생성, 평문 파일 저장은 없다. 단위 테스트 대역은 `test/` 안에만 있다.

`OrganizationKey`와 `DatabaseKey`는 소유자가 사용 후 `destroy()`를 호출한다. 서비스는 직접 연 키와 유도 키를 `finally`에서 정리한다. 이는 소유 버퍼의 최선 노력 정리이며, Dart 문자열·라이브러리 내부·FFI/OS 복사본까지 완전히 지워진다는 보장은 아니다.

## OS별 저장 정책

| 플랫폼 | 구성 |
|---|---|
| iOS | private Keychain service, `unlocked_this_device`, iCloud 동기화 없음 |
| macOS | private login Keychain, 공유 그룹 없음, 동기화 없음. `usesDataProtectionKeychain=false`로 공유 capability·프로비저닝을 요구하지 않는 백엔드를 명시적으로 선택 |
| Android | 플러그인 기본 RSA-OAEP 키 래핑 + AES-GCM 저장, 서비스별 namespace, `resetOnError=false`, 자동 알고리즘 마이그레이션 없음. 앱 backup은 비활성 |
| Windows | 플러그인 4.2.2의 DPAPI 백엔드에 로컬 보존 정책 패치 적용, legacy compatibility 비활성. 서비스 이름을 실제 key 앞에 붙여 테스트·운영 namespace를 격리하고 앱 공용 백엔드 전체를 하나의 lock으로 보호 |

Windows의 실제 네이티브 검증은 사용자 승인에 따라 보류한다. macOS login Keychain 선택을 iOS의 ThisDeviceOnly·Secure Enclave와 동일한 하드웨어 정책으로 광고하지 않는다. 생체인증·앱 잠금·백그라운드 보호는 T5다. 현재 UI에서 보안 기능을 활성화된 것처럼 표시하지 않는다.

Windows upstream 4.2.2는 DPAPI/JSON 오류 시 저장 파일을 삭제하고 FormatException을 출력하는 경로가 있어 원문의 키 보존·로그 정책과 충돌했다. `packages/flutter_secure_storage_windows/`에 BSD 라이선스·원본 버전·해시와 함께 최소 패치를 보관하고 dependency override로 고정했다. DPAPI 암호 호출과 native C++ 플러그인은 바꾸지 않았다. 패치는 읽기 오류를 빈 저장소로 바꾸지 않고, 손상 파일을 보존하며, 값·경로 진단 출력을 제거하고, 전체 map 타입을 검증한다. 쓰기는 암호화된 임시 파일을 flush한 후 교체한다. 다른 플랫폼의 보안 저장소는 변경하지 않았다.

파일 읽기 정책은 현재 호스트에서도 검사하며, 손상된 DPAPI 파일 보존 검사는 Windows에서만 실행하도록 마련했다. 이 Windows 전용 검사는 현재 보류 상태다. upstream 업데이트 시 이 보존 정책을 재검증한 뒤 override를 제거해야 한다.

근거: [보안 저장소 패키지 구성과 macOS 선택](https://pub.dev/packages/flutter_secure_storage), [Keychain 접근성](https://pub.dev/documentation/flutter_secure_storage/latest/flutter_secure_storage/KeychainAccessibility.html), [Windows 4.2.2 실제 백엔드](https://pub.dev/packages/flutter_secure_storage_windows/versions/4.2.2).

## 필드 암호화 계약

```text
fieldKey = HKDF-SHA256(
  ikm = orgKey,
  salt = utf8(license.id),
  info = utf8("lm/field/num/v1"),
  length = 32
)

AAD = utf8("lm:v1:" + license.id + ":" + expirationDate_YYYY_MM_DD)
envelope = "v1." + base64url(nonce[12] || ciphertext || tag[16])
```

`FieldCipher.encrypt`는 호출마다 라이브러리 CSPRNG nonce를 만들며, 호출자가 nonce를 지정하는 API를 제공하지 않는다. 번호가 없으면 저장소에 접근하지 않고 `null`을 반환한다. 번호가 있는데 키가 없으면 명시적 오류를 반환하며 키를 자동 생성하지 않는다.

`decrypt`는 봉투에 지정된 조직 키 버전만 사용한다. 다른 버전의 키를 차례대로 시도하지 않는다. ID·만료일·nonce·암호문·tag가 바뀌거나, 키가 없거나, 저장소가 닫혀 있거나, 인증 후 텍스트가 올바르지 않으면 `null`을 반환한다. 예외에 입력값이나 backend 메시지를 포함하지 않는다.

AAD는 번호를 ID·만료일에 결합한다. 다른 메타데이터 전체를 인증하는 계약은 아니다. Google에 기록되는 이름·발급기관·날짜 등을 E2EE로 설명하지 않는다.

`encryptPayload`는 실제 암호화 후 T2의 payload 검증까지 거친다. 1KB 제한을 넘으면 저장용 결과를 내지 않는다. 복호화 실패 시 호출자는 기존 암호문을 보존하고 번호를 지운 것으로 간주해 덮어쓰지 않아야 한다.

근거: [AES-GCM API](https://pub.dev/documentation/cryptography/latest/cryptography/AesGcm-class.html), [HKDF API](https://pub.dev/documentation/cryptography/latest/cryptography/Hkdf-class.html).

## 키 회전과 호환성

원문 7.3의 `keyVersion`을 `EncryptedLicenseNumber.keyVersion`과 wire 메타데이터 `lm_key`로 구현했다. 봉투의 `v1.`은 **암호 형식** 버전이며 조직 키 버전과 별개다.

- 기존 payload에 `lm_key`가 없으면 조직 키 버전 1이다. 기존 v1 쓰기 형식은 그대로 유지한다.
- 버전 2 이상이면 문자열 `lm_key: "2"`처럼 기록한다. `lm_v`는 데이터 스키마 1로 유지한다.
- 키 버전은 1~2147483647의 정규 십진수이며, 암호문 없는 `lm_key`는 거부한다. 예전 T2 전용 클라이언트는 새 필드를 거부하므로 회전을 사용하려면 T3 지원 클라이언트로 업데이트해야 한다.
- `migrateIfNeeded`는 먼저 기존 값을 인증한다. 오래된 키라면 새 nonce와 활성 키로 재암호화한다. 검증 실패 시 `null`을 반환하고 이전 값은 바꾸지 않는다.
- 실제 cache/Calendar 갱신은 T4/T10 이후 저장 계층에서 수행한다. 여기서 네트워크 쓰기나 기존 키 삭제는 하지 않는다.
- 초대·키 전달·퇴사자 권한 회수 기능은 아직 연결하지 않았다. 지연 마이그레이션만으로 이전 키 보유자의 과거 데이터 접근을 즉시 차단한다고 주장하지 않는다.

## SQLCipher 키

`KeyDerivation.databaseKey(keys, keyVersion: ...)`는 명시한 버전으로 `HKDF-SHA256(orgKey, info="lm/db/v1")` 32바이트를 유도한다. `DatabaseKey.hex`는 런타임 주입용 64자 hex이며 로그·설정·DB 파일에 저장하지 않는다.

조직 키를 회전했다고 기존 DB를 새 키로 열어서는 안 된다. T4의 `LocalCache`는 DB 키 버전을 OS 보안 메타데이터에 보존한다. 현재 DB rekey API는 없으며 조직 키 회전만으로 DB 키를 바꾸지 않는다. 향후 SQLCipher rekey와 검증이 성공한 뒤에만 이 연결을 전환해야 한다. T3 암호 모듈 자체는 DB를 생성하거나 rekey하지 않는다.

## 검증과 실행

2026-11-21 실행 결과: `bash tool/verify.sh` 통과(150개 통과, Windows 전용 1개 보류). 동일 필드 키로 10,000회 암호화할 때 nonce 중복은 없었다. macOS·iOS Simulator·Android 에뮬레이터에서 아래 네이티브 검사를 통과했고, 검증 후 일반 앱 진입점으로 세 플랫폼을 재빌드했다. Windows 결과는 아직 없다.

```sh
bash tool/verify.sh
./tool/flutter test integration_test/crypto_smoke_test.dart -d macos
./tool/flutter test integration_test/crypto_smoke_test.dart -d <ios-or-android-device-id>
```

Windows에서는 `flutter test integration_test/crypto_smoke_test.dart -d windows`를 사용한다. native test는 실행마다 별도의 서비스 namespace를 사용하며 CSPRNG 키를 만들고, 생성한 두 키 슬롯·활성 포인터만 `finally`에서 삭제·재확인한다. 실제 사용자 키와 고정 조직 키 fixture를 사용하지 않는다. key·평문·backend 오류 메시지는 테스트 로그에 남기지 않는다.

수동 확인: native test 실행 → 생성·재읽기·회전·구버전 복호화·지연 재암호화·테스트 슬롯 삭제가 통과하는지 확인한다. 통합 테스트 후 일반 앱을 배포 산출물로 쓰려면 일반 진입점으로 다시 빌드한다.
