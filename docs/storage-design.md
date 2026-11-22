# T4 SQLCipher 로컬 캐시·변경 큐

원문 3.8과 T4의 `LicenseCache`, `CalendarRef`, `AppSettings`, `AuditLocal`을 구현한다. SQLCipher 캐시는 Google Calendar의 사본·오프라인 대기 작업이며, 네트워크 동기화는 T9~T12에서 연결한다. 앱 UI는 아직 메모리 예시 모드다. 실제 직원 입력·운영 데이터 연결은 T5 잠금과 필수 플랫폼 검증 이후에 연다.

## 구성과 암호화 경계

- `lib/core/storage/db.dart`: 연결·요청·종료. 한 worker isolate가 네이티브 DB 연결과 트랜잭션을 소유한다. UI isolate에서 SQL을 실행하지 않는다.
- `database_worker.dart`: 스키마 v1, 런타임 암호화 확인, 인덱스 조회, 원자적 변경·큐·감사 기록. 반복 쓰기는 prepared statement를 재사용한다.
- `license_repository.dart`: 플랫폼에 의존하지 않는 공개 저장소 인터페이스. `sqlcipher_repository.dart`가 이를 구현한다. 암호화 payload만 받으며 평문 `License.licenseNumber`를 저장하는 API가 없다.
- `cache_models.dart`: 캐시·필터·대기 작업·설정·동기화 참조의 불변 타입과 값 없는 오류.
- `local_cache.dart`: cache UUID별 파일과 OS 보안 저장소의 DB 키 버전 연결.

`sqlite3 3.9.1`의 native build hook에 `source: sqlcipher`를 지정했다. `sqlcipher_flutter_libs`는 사용하지 않는다. 같은 설정을 Android·iOS·macOS·Windows에 적용하며, 일반 SQLite로 폴백하지 않는다. 패키지는 릴리스 바이너리를 내장 SHA-256으로 확인한다. 기본 SQLite와 SQLCipher를 혼용하지 않는다. [패키지 공식 빌드 구성](https://pub.dev/documentation/sqlite3/latest/topics/hook-topic.html)

열기 순서는 다음과 같다.

1. 절대 경로와 명시한 `DatabaseKey`를 받는다. 기본값은 기존 파일만 열기이며 생성은 `createIfMissing: true`일 때만 허용한다.
2. SQLCipher 로그를 끄고 `cipher_version`을 확인한다. HKDF로 유도한 32바이트 raw key를 런타임 hex로 주입한다. 키를 SQL·오류 로그나 설정 파일에 기록하지 않는다.
3. 실제 스키마를 읽어 키를 확인하고 `cipher_status=1`, 평문 헤더 0바이트, 페이지 HMAC 활성 여부를 확인한다. 미지원 PRAGMA의 빈 응답도 실패다.
4. `cipher_memory_security=ON`, `temp_store=MEMORY`, 외래키, `secure_delete`, WAL, `synchronous=FULL`을 사용한다. 키·임시 정렬 데이터를 평문 파일에 내보내지 않는다.
5. application ID와 schema version을 확인하고, 최초 스키마를 트랜잭션 안에서 만든다. 새 버전·다른 앱의 DB를 자동 변경하지 않는다. 페이지 HMAC·DB 구조 무결성 검사 후 연결을 내준다.

키 주입 직후의 PRAGMA 성공만으로 올바른 키라고 판단하지 않는다. 잘못된 키·손상·알 수 없는 스키마는 파일을 보존하고 실패한다. plaintext import, 자동 삭제·재생성·버전 강제 하향·암호화 우회 기능은 없다. [SQLCipher 키·상태·무결성 API](https://www.zetetic.net/sqlcipher/sqlcipher-api/)

SQLCipher 메모리 정리를 켰지만 Dart 문자열·isolate 메시지·FFI 내부 복사본까지 완전 소거된다고 보장하지 않는다. 공개 예외는 `StorageException(code)`이며 경로·SQL·파라미터·키·backend 메시지를 포함하지 않는다.

Android API 36 ARM64 에뮬레이터는 실행할 수 없는 SVE 관련 기능을 광고해 OpenSSL 초기화에서 SIGILL이 발생했다. `android/`의 `MainActivity.onCreate`에서 ARM64 + ranchu/goldfish 환경에만 `OPENSSL_armcap=0`을 설정해 OpenSSL의 이식 가능한 구현을 선택한다. 지원하지 않는 CPU 가속 비트를 강제로 켜지 않으며 SQLCipher 암호·HMAC·키 길이는 그대로다. 실제 기기의 CPU 탐지는 바꾸지 않는다. 이 설정으로 같은 에뮬레이터의 profile 기능·성능 검사를 통과했다. [OpenSSL 공식 CPU 기능 설정](https://docs.openssl.org/master/man3/OPENSSL_armcap/), [사용된 버전의 초기화 소스](https://github.com/openssl/openssl/blob/openssl-4.0.3/crypto/armcap.c)

## DB 키 버전 연결

`LocalCache`는 `lm.cache.<cacheUuid>.keyVersion`을 OS 보안 저장소에 보관한다. 파일은 앱 지원 디렉터리의 `cache/<cacheUuid>.db`다. UUID와 실제 Google 계정의 연결은 추후 계정 구성 계층에서 관리한다. 계정마다 다른 UUID를 사용해야 한다.

- 같은 root isolate의 최초 열기를 직렬화하고 OS 저장소의 협력적 프로세스 잠금으로 연결 정보를 확인한다. worker에서 OS 키 관리를 따로 시작하지 않는다.
- 새 캐시 생성은 이미 초기화된 조직 키의 현재 버전을 명시적으로 연결한다. 이 경로가 조직 키를 새로 만들지는 않는다.
- 파일이 있는데 연결 정보가 없거나 손상됐으면 복구 오류다. 최신 조직 키로 추측하거나 기존 파일을 지우지 않는다.
- 조직 키가 v2로 회전해도 기존 DB는 연결된 v1 키로 열린다. 번호 필드는 v2 암호문을 같은 암호화 DB 안에 저장할 수 있다.
- 이 단계에는 기존 DB 키를 바꾸는 rekey API가 없다. 향후 rekey를 추가할 때 DB 전환·검증과 보안 메타데이터 전환의 중단 복구를 함께 구현해야 한다. 버전 포인터만 바꾸어 기존 DB를 여는 것은 금지한다.
- `ComplianceDatabase.open`을 직접 쓰는 호출자는 DB 키 버전 선택과 보안 연결 정보를 책임진다. 앱 구성에서는 `LocalCache`를 사용한다.

## 스키마 v1

| 테이블 | 내용 |
|---|---|
| `license_cache` | 검증된 wire payload, 상태 조회용 날짜·카테고리·유형·보유자 인덱스 컬럼, revision, UTC 수정 시각, tombstone |
| `change_queue` | 라이선스별 최신 작업 1개, 전송할 payload 사본 또는 삭제, revision, 재시도 횟수·시각·허용 오류 코드 |
| `calendar_event_map` | 라이선스와 만료 A·D-30 B 이벤트 ID·etag 매핑. 삭제 시에도 보존 |
| `calendar_ref` | 전용 캘린더 ID, 계정 메타데이터, 증분 sync cursor, 마지막 동기화 시각 |
| `app_settings` | 표시 이름·마스킹·조용한 시간·알림 기본값의 제한된 타입 |
| `audit_local` | append-only 시각·동작·대상 UUID·이전 payload SHA-256 |

OAuth access/refresh token과 조직 키는 어느 테이블에도 없다. `sync_cursor`는 Calendar API의 증분 조회 커서이며 인증 토큰이 아니다. 이미지·PDF·OCR 텍스트·첨부·임의 blob 저장용 컬럼이나 범용 설정 API를 만들지 않았다. 이름·날짜 등 인덱스 컬럼도 SQLCipher 내부에 있고, 번호는 `v1.` AES-GCM 봉투로만 저장한다.

`CalendarRef`의 계정·캘린더를 같은 캐시 안에서 바꾸려 하면 거부한다. 계정 전환은 별도 캐시로 해야 한다. 감사 테이블의 UPDATE/DELETE는 trigger로 거부하며 앱 API도 제공하지 않는다. 이는 앱 내부의 append-only 정책이다. DB 키를 가진 외부 도구에 대한 변조 방지 증명으로 설명하지 않는다. 이전 값 해시는 원문 필드를 복원하거나 표시하는 API가 아니다.

## 상태·검색 인덱스

상태를 저장하면 자정에 낡은 값이 되므로 만료일 범위를 인덱스로 조회한다. 날짜는 UTC 자정의 날짜 전용 값이며, 호출자가 오늘의 현지 달력 날짜를 UTC 자정으로 변환해 전달한다. UTC의 현재 시각을 그대로 오늘의 현지 날짜로 사용하지 않는다.

| 상태 | 남은 일수 |
|---|---|
| expired | 음수 |
| critical | 0~7 |
| urgent | 8~30 |
| upcoming | 31~90 |
| normal | 91 이상 |

`missing`은 요구되는 자격에 기록이 없는 경우이며 날짜가 없는 가짜 `License`를 만들지 않는다. 요구사항 대조는 T14에서 구현한다.

인덱스는 `(deleted_at, expiration_date, id)`, `(deleted_at, category, expiration_date, id)`, `(deleted_at, license_type, expiration_date, id)`다. 정렬은 만료일·ID 순으로 고정하고 페이지당 최대 1000건을 반환한다. 이름·유형·발급기관의 검색어는 바인딩한 literal substring이다. `%`, `_`, 따옴표를 SQL wildcard나 SQL로 실행하지 않는다. 기본 SQLite `lower`의 대소문자 무시는 ASCII 범위이며 다국어 완전 case folding을 보장하지 않는다. `explainFilter`는 인덱스 검증용이며 실제 필터 값·레코드를 진단에 포함하지 않는다.

## 로컬 변경과 동기화 대기 큐

- `upsert`와 `upsertAll`은 캐시·대기 작업·감사 행을 같은 트랜잭션에서 저장한다. 배치 중 한 건이라도 실패하면 앞선 변경도 전부 되돌린다. 한 배치는 최대 1000건이며 중복 UUID는 거부한다.
- `expectedRevision: 0`은 새 행, 양수는 해당 기존 버전만 변경한다. 생략하면 현재 로컬 행에 적용한다. 검토 화면에서 읽은 값을 수정할 때는 revision을 지정해야 한다.
- 동일 라이선스의 대기 작업은 최신 revision·암호문으로 합치고 재시도 상태를 초기화한다. 전송 중 받은 `PendingChange`는 바뀌지 않는 사본이다.
- `acknowledgeChange(id, revision)`와 `deferChange`는 일치하는 버전에만 적용한다. 전송 도중 새 수정이 생기면 과거 완료 응답·실패 응답이 새 작업을 지우거나 지연하지 못한다.
- 재시도는 30초부터 지수 증가하고 최대 30,720초로 제한한다. offline/unauthorized/rateLimited/conflict/unavailable 코드만 받으며 응답 본문을 기록하지 않는다.
- `softDelete`는 tombstone·큐의 delete·감사를 함께 저장한다. 반복 삭제는 변경하지 않는다. 캐시·이벤트 매핑을 보존하고 일반 upsert로 되살리는 것을 거부한다.
- 이 큐는 네트워크 호출·작업 성공을 흉내 내지 않는다. Calendar의 멱등 ID·etag·원격 충돌·원격 삭제 적용은 T10~T12에서 연결한다. 원격 상태를 적용할 때 로컬 쓰기 큐를 다시 생성하지 않는 별도 트랜잭션 계약도 그 단계에서 추가한다.

## 사용 예시

```dart
// 조직 키 초기화는 온보딩에서 명시적으로 수행한 뒤여야 한다.
final db = await LocalCache.openApplication(
  secureStore: store,
  cacheId: accountCacheUuid,
  createIfMissing: true,
);
try {
  final payload = await FieldCipher(KeyManager(store)).encryptPayload(license);
  final cached = await db.licenses.upsert(payload, expectedRevision: 0);
  final visible = await db.licenses.list(); // 번호 평문 없는 메타데이터
  // 번호가 필요할 때만 T3 FieldCipher로 복호화한다.
  // 복호화 실패 시 cached.payload의 기존 암호문을 보존해야 한다.
} finally {
  await db.close();
}
```

실제 앱 화면에는 아직 이 경로를 연결하지 않았다.

## 검증 명령

```sh
bash tool/verify.sh
./tool/flutter drive --driver=test_driver/storage_driver.dart \
  --target=integration_test/storage_smoke_test.dart -d macos \
  --profile --dart-define=ENFORCE_STORAGE_PERFORMANCE=true
./tool/flutter drive --driver=test_driver/storage_driver.dart \
  --target=integration_test/storage_smoke_test.dart -d <android-device-id> \
  --profile --dart-define=ENFORCE_STORAGE_PERFORMANCE=true
./tool/flutter drive --driver=test_driver/storage_driver.dart \
  --target=integration_test/storage_smoke_test.dart -d <ios-simulator-id>
```

iOS Simulator는 debug 기능 검사이며, profile 성능 측정은 실물 iOS 기기가 필요하다. Windows 환경이 준비되면 같은 네이티브 테스트를 실행한다. Windows는 현재 사용자 승인에 따라 보류 중이다.

500건 측정은 준비된 가상 payload로 공개 저장소 API를 호출해 검증·isolate 전달·세 인덱스·트랜잭션·변경 큐·감사 쓰기와 필터 결과 디코딩까지 포함한다. 키 생성·DB 최초 열기·fixture 준비는 제외한다. 최적화된 네이티브 profile 실행에서 삽입과 필터를 합해 50ms 미만을 검증한다. JIT 단위 테스트는 기능·행 수를 검사하며 50ms를 강제하지 않는다. 디버그 첫 실행과 병렬 테스트의 컴파일·경합 시간은 제품 실행 성능과 구분한다. [Flutter 공식 profile 측정 방법](https://docs.flutter.dev/cookbook/testing/integration/profiling)

검사는 고유 OS 서비스와 임시 캐시 폴더·런타임 CSPRNG 키를 사용한다. 키·고객 문서 fixture는 없다. 끝나면 생성한 파일과 두 키 슬롯·활성 포인터·DB 버전 연결만 삭제·재확인한다. 결과는 버전·시간·성공 여부만 `artifacts/t4/<platform>/<mode>.json`에 남기고 Git에서 제외한다. 실패한 검사는 성공 기록을 만들지 않는다.

수동 확인: 위 native test 실행 → SQLCipher 버전·500건 결과·큐 복원·키 회전 후 기존 DB 열기·평문 이름/번호 미검출·테스트 저장소 정리가 통과하는지 확인한다. 검증 후 일반 `lib/main.dart` 진입점으로 다시 빌드한다.

실제 플랫폼 결과는 `implementation-status.md`의 T4 기록을 따른다.
