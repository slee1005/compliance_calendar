# 개발 진행 상태

기준 문서: `small-biz-compliance-planner.md` v1.2. 시작일: 2026-11-21.

## 현재 단계: T6 구현 완료 — 일부 실행 검증 보류, 다음 T7

- Flutter 공통 소스와 플랫폼별 네이티브 폴더를 분리한다.
- 초기 앱은 온보딩, 빈 상태, 명시적으로 선택한 예시 화면만 제공한다.
- T3 암호화·키 관리는 구현했으며 macOS·iOS·Android의 OS 저장소 검사를 통과했다. Windows 실행 검증은 보류 중이다.
- T4 SQLCipher 캐시·검색 인덱스·변경 큐·감사를 구현했다. UI와 실제 Calendar 동기화는 아직 연결하지 않았다.
- T5 앱 잠금·OS 인증·앱 비밀번호·네이티브 화면 보호를 루트 UI에 연결했다. Windows 실행 검증은 계속 보류 중이다.
- T6 카메라 스트림·읽기 전용 파일 입력을 가상·비식별 문서 시험 화면에 연결했다.
- 필수 플랫폼 검증과 운영 입력 흐름 연결 전에는 실제 직원 정보 입력·저장을 열지 않는다.
- 예시는 앱 메모리에만 존재하며 앱 종료 시 사라진다. 고객 캘린더에 쓰지 않는다.
- 분석, 테스트, 네이티브 빌드 결과를 아래에 실제 실행 기준으로 기록한다.

T1은 4플랫폼 빌드와 실행 확인까지 마쳐야 완료다. CI 파일 작성만으로 빌드 성공으로 간주하지 않는다. **2026-11-21 사용자 승인: Windows 검증은 나중에 진행하고 T2 데이터 모델부터 계속한다.** Windows 검증은 출시 전 필수 미완료 항목으로 유지하며, 이후 T2~T19의 순서는 따른다.

## 후속 마일스톤

| 단계 | 내용 | 상태 |
|---|---|---|
| T1 | 스캐폴드, 초기 화면, 분석·테스트, 4플랫폼 CI | Windows 검증 보류·미완료 |
| T2 | 6개 필드 모델·검증·Calendar payload | 완료 |
| T3 | 키 보관·HKDF·AES-GCM·회전 | 구현 완료·Windows 실행 검증 보류 |
| T4 | SQLCipher 캐시·큐·인덱스 | 구현 완료·Windows 실행 검증 보류 |
| T5 | 앱 잠금·백그라운드 보호 | 구현 완료·Windows 실행 검증 보류 |
| T6 | 카메라·로컬 파일 입력 무저장 | 구현 완료·Windows·실물 iOS 카메라·Finder 실제 제스처 미검증 |
| T7~T8 | OS OCR·후보 추출·사용자 확인 | 대기 |
| T9~T12 | OAuth·이벤트 A/B·증분 동기화 | 대기 |
| T13~T14 | 로컬 알림·운영 대시보드 | 대기 |
| T15~T16 | 감사 리포트·ICS | 대기 |
| T17~T18 | 접근성·번역·출시 패키징 | 대기 |
| T19 | Free 10건·Pro·구매 복원 | 대기 |

## 실제 계정 연동 전 해결할 사항

1. **증분 동기화 요청 수정.** 원문 7.5는 `syncToken`과 `privateExtendedProperty`를 함께 보낸다. Google API는 이 조합을 금지한다. 전용 캘린더 전체를 같은 매개변수로 동기화하고 앱 태그는 클라이언트에서 거른다. 삭제 이벤트는 속성이 없을 수 있어 이벤트 ID 매핑도 보존해야 한다.
2. **캘린더 권한 조회.** `calendar.app.created`만으로 캘린더 목록 조회까지 되는지 별도 검증한다. 기본 권한을 넓히지 말고, 최초 생성 ID를 보관하는 복원 전략을 검증한다.
3. **개인정보 표시.** `extendedProperties.private`는 암호화가 아니다. 원문의 이름·발급기관 등은 Google에서 평문으로 처리된다. 마스킹된 제목만 보고 전체 데이터가 암호화됐다고 안내하지 않는다.
4. **이메일·참석자 알림.** 소유자·공유자·참석자의 알림 설정은 같지 않다. D-30/D-7/D-1 이메일이 모든 지정 수신자에게 보장된다고 출시 전에 주장하지 않는다. 실계정 테스트가 필요하다.
5. **플랫폼 보안 검증.** SQLCipher 라이브러리와 보안 저장소의 4플랫폼 지원을 먼저 검증한다. 일반 SQLite나 평문 파일로 대체하지 않는다.
6. **iOS 화면 보호.** iOS에서 모든 스크린샷을 완전히 막을 수 있다는 전제를 두지 않는다. 백그라운드 스냅샷 보호·캡처 감지와 실제 OS 지원 범위를 검증한다.

공식 근거: [Calendar events.list](https://developers.google.com/workspace/calendar/api/v3/reference/events/list), [Calendar 권한](https://developers.google.com/workspace/calendar/api/auth), [Extended properties](https://developers.google.com/workspace/calendar/api/guides/extended-properties).

## 검증 기록

2026-11-21, Apple Silicon macOS / Xcode 27.2, Flutter 3.50.1 / Dart 3.14.0 기준.

| 항목 | 실제 결과 |
|---|---|
| Flutter 프로젝트 | Android·iOS·macOS·Windows runner 생성 |
| 정적 분석 | `flutter analyze`: 오류·경고 없음 |
| T3 전체 자동 테스트 | 150개 통과, Windows 전용 손상 DPAPI 파일 검사 1개 보류. vendor Dart 정적 분석도 지적 사항 없음 |
| T4 전체 자동 테스트 | 174개 통과, 기존 Windows 전용 1개 보류. 앱·vendor 정적 분석 지적 사항 없음 |
| T5 전체 자동 테스트 | 208개 통과, 기존 Windows 전용 1개 보류. 앱·vendor 정적 분석 지적 사항 없음 |
| T6 전체 자동 테스트 | 234개 통과, 기존 Windows 전용 1개 보류. 앱·vendor 정적 분석 지적 사항 없음 |
| 위젯 테스트 | 10개 통과. 온보딩·예시 선택/초기화·검색/필터·상세·모바일 메뉴·미연결 상태·레이아웃 검사 |
| 화면 크기 | 375×667 / 1440×900, 기본·200% 글자 크기에서 11개 화면 예외 없음 |
| macOS 빌드 | 디버그 `.app` 생성 성공 |
| macOS 통합 테스트 | 실제 네이티브 앱의 주요 8개 화면·상세 2개·초기화 검사 통과 |
| macOS 시각 확인 | 한글 온보딩·예시 대시보드·목록 3장 확보·검토, 1440×900 |
| iOS 빌드·실행 | iPhone 18 Pro / iOS 27 Simulator에서 네이티브 실행 검사 통과. 실물 기기는 미검증 |
| iOS 화면 | 공식 SDK 네이티브 캡처 3장 확보·검토, 1206×2622 |
| Android 빌드·실행 | Android API 36 에뮬레이터에서 네이티브 실행 검사 통과. 기존 AVD는 읽기 전용으로 사용. 실물 기기는 미검증 |
| Android 화면 | 공식 SDK 네이티브 캡처 3장 확보·검토, 1080×1920 |
| Windows 빌드·실행 | 미실행. 사용자에게 확인한 결과 사용할 Windows PC·VM·CI 환경이 없음 |
| CI | 4플랫폼 빌드 및 Windows·macOS 실행·캡처 작업 작성·YAML 문법 확인. 원격 저장소가 없어 실행하지 않음 |
| 키 보관 | T3 어댑터·생성·회전 구현. macOS·iOS·Android의 실제 OS 저장소 검사 통과, Windows 실행 보류. 운영 UI 미연결 |
| SQLCipher | worker isolate의 암호화 캐시·큐·인덱스·감사 구현. macOS·Android profile, iOS Simulator debug 기능 검사 통과 |
| 후속 서비스 | 잠금은 T5에 연결. OCR·Calendar·알림·파일 내보내기·결제는 미구현 |

T1은 **Windows 검증 보류·미완료**로 유지한다. 남은 완료 조건은 Windows 네이티브 빌드·실행·스크린샷 확보다. 나머지 세 플랫폼의 실행 화면은 확보했다. 플랫폼별 위젯 레이아웃 검사는 실제 OS 실행 검증을 대신하지 않는다. 사용자 승인에 따라 Windows 검증만 후속으로 남기고 T5까지 구현했다.

초기 UI는 원문의 화면 11개를 탐색할 수 있게 연결했으며, 잠금 외의 후속 태스크 기능은 준비 중으로 표시한다. 감사 리포트 내보내기처럼 실제 서비스가 필요한 버튼은 비활성 상태다.

수동 확인: `./tool/flutter run -d macos` → 예시로 둘러보기 → 라이선스 검색·상세 → 직원 상세 → 설정에서 예시 끄기.

산출물:

- macOS: `build/macos/Build/Products/Debug/Compliance Manager.app`
- iOS Simulator: `build/ios/iphonesimulator/Runner.app`
- Android: `build/app/outputs/flutter-apk/app-debug.apk`

SDK는 `.tools/flutter/`에 설치했으며 버전 관리에서 제외했다. 개인 개발자 팀·OAuth 자격 증명·서명 비밀값을 추가하지 않았다. 초기 T1 작업에서는 로컬 Git 저장소만 초기화했다. 이후 사용자 요청에 따른 원격 설정은 아래에 별도로 기록한다.

## 네이티브 검증 도구 추가

- `bash tool/capture_preview.sh <native-device-id>`: macOS·iOS·Android 실행 테스트와 캡처.
- `./tool/capture_preview.ps1 -DeviceId windows`: Windows 환경이 준비되면 같은 검사를 재현.
- `artifacts/t1/<platform>/`: 온보딩·대시보드·목록 PNG와 기기·캡처 방식·크기·시각·성공 여부를 담은 `manifest.json`. Git에서 제외.
- 모바일은 공식 SDK의 네이티브 캡처 API를 사용하고, 데스크톱은 실제 네이티브 앱의 렌더링을 캡처한다.
- 캡처 전에 상단 앱 제목과 예시 안내가 표시되는지 검사한다. 목록 캡처의 상단이 빠진 것으로 보였던 점은 원본 PNG 픽셀 확인에서 정상으로 확인했다.
- 테스트 실행은 앱 산출물을 테스트 진입점으로 다시 빌드하므로, 배포할 일반 앱은 이후 일반 진입점으로 재빌드한다. CI에도 이 복원 단계를 추가했다.
- 최종 검증 후 macOS·iOS Simulator·Android를 일반 `lib/main.dart` 진입점으로 재빌드했고 세 빌드 모두 성공했다.
- 이번 검증을 위해 기동한 iPhone 18 Pro 시뮬레이터는 종료했다. 다른 기기·시뮬레이터는 종료하지 않았다. Android 읽기 전용 검증 인스턴스도 더 이상 실행 중이지 않다.

자세한 사용법과 제약은 `native-verification.md`를 참고한다. 고객 문서나 실제 직원 정보는 이 검증에 사용하지 않았다.

## T2 완료 기록

2026-11-21: 사용자 승인에 따라 Windows 검증을 보류하고 T2를 구현했다. T1을 완료로 바꾸지는 않았다.

- `LicenseCategory`: 원문의 6개 카테고리와 정확한 enum/wire 이름.
- `License`: 원문 필드·타입, 불변 값 모델, UUID v4·문자열 길이·보유자 구분·schemaVersion 검증.
- `LicenseDate`: 실제 달력 날짜와 윤년 확인, UTC 자정만 허용, 발급일보다 이른 만료일 거부.
- `LicensePayload`: `fromLicense/fromMap/toMap/toLicense`, 문자열 전용 wire map과 JSON 왕복. 알 수 없는 필드·버전·잘못된 타입 거부.
- 번호 평문이 포함된 `License`에는 일반 Map/JSON 직렬화 API를 두지 않았다. payload를 만들려면 별도 타입의 암호문 봉투가 필요하며, payload 객체 자체에는 평문 번호를 남기지 않는다.
- 봉투 검사는 `v1.`·URL-safe base64·nonce/ciphertext/tag 길이의 **형식 검증만** 수행한다. T3 암호화·복호화·GCM 인증을 구현한 것으로 간주하지 않는다.
- 전체 payload를 UTF-8 JSON 기준으로 검사해 1024바이트는 허용하고 1025바이트는 거부한다. 잘라내기·자동 보정·지원하지 않는 값으로의 폴백은 없다.
- 진단 문자열과 검증 오류에는 이름·번호·발급기관·보관 위치·입력값을 넣지 않는다.
- 공통 모델은 Flutter UI·플랫폼 API에 의존하지 않는다. 새로운 외부 의존성을 추가하지 않았고 `pubspec.lock`도 유지했다.

검증: `bash tool/verify.sh` 통과. 포맷 변경 0건, 정적 분석 지적 사항 0건, **모델·payload 103개 + 기존 UI 10개 = 113개 테스트 통과**. 기존 모바일·데스크톱·200% 글자 크기 검사를 포함한다. 네이티브 UI와 플랫폼 설정을 변경하지 않아 T1의 네이티브 실행 검사를 다시 수행하지 않았다.

수동 확인: 프로젝트 루트에서 `./tool/flutter test test/models` 실행 → 왕복 직렬화와 잘못된 날짜·UUID·길이·번호 전송·1KB 경계 검사 통과 확인.

상세 계약과 API 사용법: `data-model.md`. T2 완료 시 운영 저장소와 실제 정보 입력은 활성화하지 않았으며, 다음 단계 T3의 결과는 아래에 기록한다.

## T3 완료 기록

2026-11-21: 원문 7.3의 암호화·키 관리 레이어를 구현했다. 사용자 지시에 따라 Windows 실행 검증은 후속으로 남긴다. T1은 계속 미완료이며 T4는 아직 시작하지 않았다.

- `KeyManager`: 라이브러리 CSPRNG의 32바이트 조직 키, `lm.orgKey.vN` 슬롯, 보안 저장소 안의 활성 버전 포인터, 저장 후 재읽기 검증. 기존 키를 삭제하지 않고 회전한다. 중단된 초기화·포인터 기록 실패 복구와 동시 요청 직렬화를 포함한다.
- `OsKeyStore`: iOS private ThisDeviceOnly Keychain, macOS private login Keychain, Android Keystore 기반 보관, Windows DPAPI 어댑터. OS 오류를 입력값·backend 메시지 없는 코드로 반환하며 평문 폴백·오류 시 재생성을 하지 않는다.
- `KeyDerivation`: 정확한 salt/info의 HKDF-SHA256 필드 키와 SQLCipher raw key(64자 hex) 유도. DB 키 버전은 명시적으로 지정하며, DB 열기·rekey는 T4에서 구현한다.
- `FieldCipher`: AES-256-GCM, 매번 새 12바이트 nonce, ID·만료일 AAD, 원문 `v1.<base64url>` 봉투. 인증·키 읽기 실패 시 `null`을 반환하고 기존 암호문을 보존한다. 번호가 없으면 OS 저장소에 접근하지 않는다.
- 조직 키 버전은 `EncryptedLicenseNumber.keyVersion`과 선택 wire 필드 `lm_key`로 전달한다. 기존 v1 payload는 같은 형식으로 유지하며 누락 버전은 1이다. 키 회전 후 기존 번호는 읽을 때 인증하고 지연 재암호화한다.
- Windows 플러그인 upstream 4.2.2에서 손상 시 키 파일 자동 삭제·예외 데이터 출력 경로를 확인해, BSD 라이선스를 보존한 로컬 패키지에 보존 정책 패치를 적용했다. DPAPI 암호 호출과 native C++는 변경하지 않았다. 파일 오류를 빈 저장소로 바꾸지 않으며, 암호화 파일을 flush 후 교체한다. 출처·원본 해시·변경 범위는 `packages/flutter_secure_storage_windows/UPSTREAM.md`에 기록했다.
- 보안 모듈은 UI·Calendar·SQLCipher와 분리했다. 예시 모드는 여전히 메모리 전용이며 실제 직원 입력·보안 활성화·키 초대·권한 회수를 제공하지 않는다. 앱 잠금은 T5다.

### T3 실제 검증

| 검사 | 결과 |
|---|---|
| `bash tool/verify.sh` | 통과. 포맷 변경 0건, 앱·Windows vendor 정적 분석 지적 사항 0건, 테스트 150개 통과·1개 보류 |
| 암호화·인증 | Unicode 왕복, 직접 라이브러리 호출과 상호운용, nonce·암호문·tag·ID·만료일 변조 거부 |
| nonce | 동일한 유도 필드 키로 10,000회 암호화 시 12바이트 nonce 중복 0건 |
| 키 생명주기 | 키 없음·손상 거부, 동시 초기화, 회전·이전 키 유지, 포인터 실패·재읽기 실패 복구, 버전 경계 통과 |
| 파생·payload | 정확한 HKDF salt/info, DB/필드 키 분리, 회전 버전 전송·기존 v1 호환·1KB 경계 통과 |
| Windows 보존 정책 | 현재 호스트에서 미존재·읽기 오류 검사 2개 통과. 실제 DPAPI 손상 파일 검사는 Windows 전용으로 보류 |
| macOS 네이티브 | `crypto_smoke_test.dart`: private login Keychain 생성·새 관리자 재읽기·회전·구/신 버전 복호화·DB 키 유도·테스트 슬롯 정리 통과 |
| iOS 네이티브 | iPhone 18 Pro / iOS 27 Simulator에서 같은 검사 통과. 실물 기기는 미검증 |
| Android 네이티브 | Android API 36 읽기 전용 에뮬레이터에서 같은 검사 통과. 실물 기기는 미검증 |
| Windows 네이티브 | 미실행. 사용자 승인에 따라 보류하며 성공으로 간주하지 않음 |
| 일반 앱 재빌드 | 최종 검증 후 macOS `.app`, iOS Simulator `.app`, Android debug APK 모두 일반 진입점으로 빌드 성공 |
| UI 회귀 | 기존 11개 화면, 375×667 / 1440×900, 기본·200% 글자 크기 검사 포함 |

네이티브 검사는 실행마다 별도 서비스 namespace와 런타임 CSPRNG 키를 사용하고, 생성한 두 키 슬롯·활성 포인터만 `finally`에서 삭제·재확인했다. 키·토큰 fixture나 고객 문서는 사용하지 않았다. 통합 테스트 명령과 한계는 `crypto-design.md`를 참고한다.

원본 Markdown·PDF의 SHA-256은 변경 전과 동일하다. 의존성과 로컬 패치는 `pubspec.lock`에 고정했다. 다음 작업은 T4 SQLCipher 캐시·변경 큐·인덱스다.

## T4 완료 기록

2026-11-21: SQLCipher 로컬 캐시·변경 큐·인덱스·감사를 구현했다. Windows 실행 보류 승인은 유지한다. 실제 직원 정보 입력과 Calendar 연동을 활성화하지 않았으며 T5는 시작하지 않았다.

- `sqlite3 3.9.1` native hook의 `source: sqlcipher`로 네 플랫폼을 같은 SQLCipher 구성에 고정했다. 실제 검증에서 SQLCipher 4.20.0 community를 확인했다. 일반 SQLite 폴백은 없다.
- `ComplianceDatabase`: 별도 worker isolate, 키 주입 후 실제 스키마 읽기·cipher status/HMAC/헤더 확인, 암호화 WAL, 메모리 임시 저장, 전체 동기 쓰기, 페이지·DB 무결성 검사. 키·SQL·파라미터를 오류나 로그에 내보내지 않는다.
- `LocalCache`: cache UUID와 DB 키 버전을 OS 보안 저장소에 연결한다. 조직 키 회전 후에도 기존 DB 키 버전을 유지하고, 파일이 있는데 연결 정보가 사라지면 복구 오류를 낸다. 같은 프로세스의 동시 최초 열기도 직렬화해 버전 선택이 엇갈리지 않게 한다. DB rekey는 아직 제공하지 않는다.
- `LicenseRepository`: 암호화된 `LicensePayload`만 저장한다. cache upsert·outbox·감사를 한 트랜잭션에서 처리하고, 번호 평문 컬럼을 만들지 않았다. 배치 최대 1000건, revision 비교, idempotent soft delete와 이벤트 매핑 보존을 포함한다.
- 대기 큐는 라이선스별 최신 사본을 보관하며 같은 revision의 완료·실패 응답만 반영한다. 전송 중 새 수정이 생겨도 과거 응답이 최신 작업을 지우지 못한다. 재시도 시간·허용 오류 코드도 암호화 DB에 보관한다. 실제 HTTP 요청은 없다.
- 날짜·카테고리·유형별 복합 인덱스를 만들었다. 상태는 오늘의 날짜와 만료일 범위를 이용해 계산하므로 자정 후 오래된 상태 값이 남지 않는다. 0/7/8/30/31/90/91일과 날짜 범위 끝을 검사한다. 누락 자격 대조는 T14다.
- `CalendarRef`, 제한된 타입의 설정, append-only 감사와 이전 payload 해시를 구현했다. 인증 토큰·키·이미지·PDF·OCR 텍스트·첨부 저장 API는 없다. Calendar sync cursor는 인증 토큰과 구분한다.
- Android ARM64 API 36 에뮬레이터가 지원하지 않는 SVE 기능을 광고해 OpenSSL 초기화가 종료되는 문제를 확인했다. ranchu/goldfish ARM64에서만 OpenSSL의 portable CPU 설정을 선택해 재검증했다. 실제 기기의 CPU 탐지는 바꾸지 않았다.

### T4 실제 검증

| 검사 | 실제 결과 |
|---|---|
| `bash tool/verify.sh` | 통과. 포맷 변경 0건, 앱·Windows vendor 정적 분석 지적 사항 0건, 174개 통과·기존 Windows 전용 1개 보류 |
| 암호화 파일 | DB·열린 WAL에서 가상 이름·평문 번호 미검출. 키 없는 읽기 거부, 잘못된 키·손상 파일 보존 검사 통과 |
| 캐시·큐·감사 | CRUD·필터·페이지·revision 충돌·배치 전체 롤백·삭제 후 부활 거부·이전 응답 보호·재시도·재실행 복원·감사 변경 거부 통과 |
| 인덱스·키 연결 | 실제 EXPLAIN QUERY PLAN으로 상태/만료일·카테고리·유형 인덱스 사용 확인. 동시 최초 열기·다중 연결·조직 키 회전 후 기존 DB 열기 통과 |
| macOS native profile | 실제 login Keychain + SQLCipher 생성·회전·재열기·큐 복원·평문 미검출·격리된 테스트 키 정리 통과. 500건 삽입 44.87ms + 필터 1.03ms = 45.90ms |
| Android native profile | API 36 ARM64 읽기 전용 에뮬레이터에서 같은 검사 통과. 500건 삽입 36.73ms + 필터 1.62ms = 38.35ms |
| iOS native debug | iPhone 18 Pro / iOS 27 Simulator에서 같은 기능 검사 통과. debug 측정 76.93ms + 5.14ms이며 50ms 성능 기준 통과로 간주하지 않음. 실물 iOS 성능은 미검증 |
| 네이티브 UI 회귀 | `integration_test/app_smoke_test.dart -d macos` 통과. 일반 자동 검사에 기존 11개 화면·375×667/1440×900·200% 글자 크기 포함 |
| Windows | 빌드·DLL 로딩·키 보관·캐시·성능 미실행. 사용자 승인에 따라 보류하며 성공으로 간주하지 않음 |
| CI | desktop SQLCipher 네이티브 검사·성능·결과 업로드 작업 추가, YAML 구문 검사 통과. 원격 CI는 실행하지 않음 |

500건 성능은 준비된 가상 payload에 대해 검증·isolate 전달·세 인덱스·큐·감사·commit·조회 디코딩까지 포함한 profile 앱의 공개 API 측정이다. 키 생성·DB 최초 열기는 제외한다. 단위 테스트의 JIT/병렬 실행 시간에 50ms를 강제하지 않는다. 실제 profile 기준은 삽입·필터 합계 50ms 미만으로 검사한다.

수동 확인: `storage-design.md`의 native test 명령 실행 → 암호화 버전·500건 결과·대기 큐 복원·키 정리 성공 확인. 결과는 키·SQL·레코드가 없는 `artifacts/t4/<platform>/<mode>.json`에 보관하며 Git에서 제외한다. 일반 앱은 테스트 후 일반 진입점으로 재빌드한다.

원본 Markdown·PDF의 SHA-256은 변경 전과 동일하다. `pubspec.lock`을 유지했다. 상세 스키마·공개 API·보안 한계는 `storage-design.md`를 따른다. 다음 작업은 T5 앱 잠금·백그라운드 보호다.

최종 정리: macOS·iOS Simulator·Android의 일반 진입점 디버그 빌드가 모두 성공했다. 이번에 켠 iPhone 18 Pro 시뮬레이터와 읽기 전용 Android 검증 인스턴스는 종료했으며, 기존에 실행 중이던 다른 시뮬레이터는 유지했다. 저장소의 공개 인터페이스는 네이티브 구현과 분리한 뒤 전체 분석·174개 테스트를 다시 통과했다.

## T5 구현 기록

2026-11-21: 사용자 요청에 따라 앱 잠금·OS 인증·앱 비밀번호·백그라운드 보호를 구현했다. Windows 빌드·실행은 기존 사용자 승인에 따라 보류한다. T1과 T5의 4플랫폼 실행 조건 전체를 통과했다고 간주하지 않는다.

- `core/security`: 기기 인증·네이티브 화면 보호 인터페이스, 실제 `local_auth` 어댑터, OS 저장소의 정책·검증값, 세션 controller를 분리했다. 일반 `main.dart`에서 실제 서비스를 조립한다.
- 루트 Navigator 밖에 잠금 경계를 두고 잠긴 업무 화면을 제거한다. 창·앱 비활성 때 화면과 접근성 내용을 즉시 가리고, 5분 이상 배경 전환·시계 되돌림·OS 화면 잠금·수동 잠금에 재인증을 요구한다.
- 공식 OS 인증은 생체인증과 기기 PIN/패스코드를 허용한다. OS 인증을 지원하지 않는 경우 앱 비밀번호를 명시적으로 설정할 수 있다. 기기 인증만 등록할 때도 실제 인증이 필요하다.
- 앱 비밀번호는 무작위 salt와 PBKDF2-HMAC-SHA256 600,000회 검증값으로만 OS 보안 저장소에 보관한다. 원문 비밀번호 저장·로그·고정 비밀번호 fixture는 없다. KDF는 별도 isolate에서 실행하고 실패 횟수·지연을 프로세스 재시작에도 유지한다.
- 정책 손실·손상·저장 실패는 잠금 해제나 재생성으로 처리하지 않는다. 증명은 인스턴스·설정 revision·2분·1회 사용에 묶인다. 늦게 도착한 성공·수동 잠금과의 경합을 거부한다.
- 잠금 설정 해제는 새 인증을 요구하고 보호 핸들·복호화 상태 정리를 기다린다. 설정 저장 중 수동 잠금이나 정리 실패는 화면을 열지 않는다. 미래 운영 데이터용 `requireAuthorization` 세대 검사·`onLock` 연결 지점을 제공한다. 현재 예시 UI는 운영 DB를 열지 않는다.
- Android는 FragmentActivity·AppCompat·USE_BIOMETRIC, FLAG_SECURE·네이티브 덮개를 연결했다. iOS는 Face ID 사용 문구, UIScene·캡처 감지·덮개·파일 보호를 추가했다. macOS는 창·앱·세션 덮개를, Windows는 Win32 덮개·WTS·절전·캡처 제외 요청을 구현했다. 오래된 reveal은 epoch 검사로 차단한다.
- T3 `OsKeyStore.withExclusiveAccess`가 callback의 인증 거부까지 저장소 오류로 바꾸던 문제를 수정했다. 파일 잠금 I/O 오류만 안전한 저장소 오류로 바꾸며, 서비스의 값 없는 도메인 오류는 유지한다. 실제 파일 잠금 회귀 테스트를 추가했다.

### T5 네이티브 검증

| 검사 | 실제 결과 |
|---|---|
| `bash tool/verify.sh` | 통과. 포맷 변경 0건, 앱·vendor 정적 분석 지적 사항 0건. 208개 통과·기존 Windows 전용 1개 보류 |
| 화면·경합 회귀 | 기존 11개 예시 화면과 잠금·설정·오류 화면을 375×667/1440×900 및 기본/200% 글자 크기에서 검사. 비밀번호 재시도, 정확히 5분·4분 59초, 시계 되돌림, 늦은 인증·설정 저장 경합, cleanup 실패 검사 포함 |
| macOS debug | 실제 login Keychain에 앱 비밀번호 등록·오류 거부·해제·controller 재시작 후 잠금·재인증·설정 해제·자체 슬롯 정리 통과. 네이티브 덮개와 오래된 epoch 거부 확인 |
| iOS 27 Simulator | iPhone 18 Pro에서 같은 비밀번호·저장·덮개 검사와 가상 Face ID 등록·잠금 해제 두 번의 실제 LocalAuthentication 호출 통과 |
| Android API 36 | 읽기 전용 에뮬레이터에서 같은 비밀번호·저장·덮개 검사 통과. 별도 임시 OS PIN으로 SystemUI의 실제 기기 자격증명 등록·해제 경로 두 번 통과 |
| 실제 5분 배경 전환 | Android를 HOME으로 보내 실제 5분 이상 지난 뒤 복귀해 잠금과 재인증 확인. fake clock 결과로 대체하지 않음 |
| 네이티브 UI 회귀 | 실제 잠금 서비스가 있는 `integration_test/app_smoke_test.dart -d macos` 통과. 예시 탐색·상세·초기화에 예외 없음 |
| iOS 파일 보호 | Simulator에서 기기 Data Protection을 검증했다고 표시하지 않도록 `files: false` 반환. 실물 기기는 Complete 메타데이터를 재확인하며, 실제 잠금 상태의 DB I/O는 추가 검증 필요 |
| 생체 센서·하드웨어 | iOS는 가상 Face ID만 확인. 실물 Face ID·Touch ID·Android 지문 센서와 iOS 패스코드 폴백은 미검증. Android는 실제 OS PIN 폴백 확인 |
| 캡처 제한 | Android FLAG_SECURE 설정 확인. iOS·macOS는 전체 스크린샷 차단을 지원한다고 표시하지 않음. Windows 캡처 제외는 실행 미검증 |
| Windows | 빌드·실행·Hello·앱 비밀번호·덮개·캡처 모두 보류. 성공으로 간주하지 않음 |
| CI | desktop 앱 비밀번호·네이티브 덮개 검사와 결과 업로드 단계 추가. YAML 구문 검사 통과. 원격 CI는 실행하지 않음 |
| 일반 앱 재빌드 | 통합 테스트 후 일반 `lib/main.dart` 진입점의 macOS debug `.app`, iOS Simulator debug `.app`, Android debug APK 모두 빌드 성공 |

네이티브 비밀번호 등록 양식은 공식 Flutter 테스트 입력기를 사용하며, 잠금 해제는 실제 controller·OS 저장소·PBKDF2로 확인한다. 양식의 편집·오류·재시도·Overlay는 위젯 테스트로 별도 검사한다. 하드웨어 IME 입력은 파일럿에서 확인한다. macOS DEBUG 테스트의 창 활성화 요청은 실제 AppKit focus 요청일 뿐 인증 결과나 가시성 값을 조작하지 않는다.

네이티브 테스트는 매번 별도 OS 저장소 namespace와 런타임 CSPRNG 비밀번호를 사용한다. 직접 만든 정책·등록 표식만 `finally`에서 삭제·재확인한다. Android 임시 PIN은 폐기할 에뮬레이터에서만 사용하고 값·명령 출력을 파일에 쓰지 않는다. 결과는 기능·지원 여부만 `artifacts/t5/<platform>/lock-*.json`에 보관하며 Git에서 제외한다.

상세 정책·공개 API·플랫폼 제약·재현 명령: `app-lock-design.md`. 실제 직원 정보 입력·OCR·Calendar 동기화는 여전히 연결하지 않았다. 다음 작업은 T6 카메라·파일 입력의 휘발성 처리다.

최종 정리: 테스트용 iPhone 18 Pro의 가상 생체 등록을 원래 값 0으로 복원·재확인하고 종료했다. 기존에 실행 중이던 다른 시뮬레이터 2개는 유지했다. 자체 읽기 전용 Android 인스턴스만 종료해 임시 상태를 폐기했다. 원본 Markdown·PDF의 SHA-256은 최초 기록과 동일하며 `pubspec.lock`을 유지했다.

## T6 구현·검증 기록

2026-11-21: 카메라·파일 입력을 무저장 경로로 구현했다. Flutter 공통 입력 계약과 화면은 `lib/`, 카메라 권한·데스크톱 브리지는 플랫폼별 runner에서 관리한다. T7 OCR·T8 후보 확인과 실제 직원 정보 저장은 연결하지 않았다.

- `EphemeralDocument`: mutable 소유 버퍼, 20MiB·raw 4096×4096·stride/회전 검증, 10초 절대 수명, 종료·오류·취소·잠금 시 제로화. 완료 정보는 형식·바이트 수뿐이다.
- `InputController`: 단일 처리, 중복 거부, 비동기 작업 전후 T5 세대 검사, 늦은 초기화·읽기·소비 결과 거부, 원본 capability의 finally 해제. 정리 실패를 성공으로 표시하지 않는다.
- 모바일: 공식 `camera 0.12.2`의 `startImageStream`, Android YUV420/iOS BGRA8888, medium 해상도, audio off. `takePicture`·동영상·갤러리 API를 호출하지 않아 삭제할 촬영 임시 파일도 만들지 않는다.
- Android 병합 manifest에서 RECORD_AUDIO·WRITE_EXTERNAL_STORAGE와 암묵적 READ_EXTERNAL_STORAGE를 제거했다. 카메라 권한은 사용자가 시작할 때만 필요하다. iOS에는 한국어 카메라 사용 문구만 추가했다.
- 데스크톱: macOS NSOpenPanel·NSDraggingDestination, Windows GetOpenFileNameW·WM_DROPFILES. 읽기 전용 로컬 정규 파일만 받고 가상 파일·폴더·링크·클라우드·네트워크 소스를 거부한다. 원본 삭제·복사·이동·쓰기 코드는 없다.
- source는 10초·단일 사용 토큰이며 경로·파일명·bookmark를 Flutter나 디스크에 저장하지 않는다. 네이티브 I/O는 UI thread 밖에서 실행한다. 플랫폼의 불변 코덱 뷰는 writable 소유 버퍼로 복사해 폐기한다. 이 경계의 회귀 검사도 추가했다.
- 스캔 화면은 잠금 해제와 별도 가상·비식별 문서 시험 동의를 요구한다. 화면 이탈·비활성 때 버퍼를 폐기하고 카메라를 닫는다. 잠금 시 native 파일 토큰도 철회한다. 인식·저장·결제를 성공했다고 표시하지 않는다.

| 검사 | 실제 결과 |
|---|---|
| 전체 품질 검사 | `bash tool/verify.sh`: 234개 통과·기존 Windows 전용 1개 보류, 포맷 변경·앱/vendor 분석 지적 사항 0건 |
| 버퍼·경합·화면 | 100회 합성 입력 제로화, 만료·오류·중복·늦은 읽기·잠금·원본 해제 실패, stride·형식·크기 거부, 375×667/1440×900 및 200% 글자 크기 통과 |
| Android API 36 | 읽기 전용 AVD의 SDK 합성 카메라로 실제 CameraX 프레임 100개 + 메모리 입력 100회 처리. 소유 버퍼 제로화, app temp/cache 문서 파일 0건. 실제 웹캠·고객 서류 사용 없음 |
| macOS native | 실제 OS 선택기에서 기존 기획 PDF를 읽기 전용으로 선택. 같은 파일을 실제 native pasteboard 수신 경로로 100회 처리하고 버퍼 제로화·문서 파일 0건·토큰 해제 확인 |
| iOS 27 Simulator | 실제 플러그인에서 카메라 없음(unavailable) 확인. 메모리 입력 100회 제로화·app temp/cache 문서 파일 0건. 실물 카메라 스트림 100회 성공으로 간주하지 않음 |
| Finder 실제 마우스 드래그 | 별도 자동 UI 동선을 시도했지만 드래그 전달을 확정하지 못해 4분 대기 검사 시간 초과. 성공한 native pasteboard 100회 검사와 구분하며 미검증으로 유지 |
| Windows | 소스·읽기 전용 브리지·검사 진입점 구현. 빌드·파일 선택·드롭·잔여 파일 실행 검증은 기존 사용자 승인에 따라 보류 |

macOS 네이티브 검사에서 코덱의 불변 버퍼와 제로화할 소유 버퍼를 분리했다. 자동 UI 검사로 OS 접근성이 활성화될 때는 native가 의미 트리를 소유하게 하고 테스트 종료 때 해당 핸들을 해제한다. 제품의 접근성·인증을 끄거나 성공값을 주입하지 않는다. 실물 VoiceOver/TalkBack 동선은 T17 검증 대상이다.

성공 근거는 `artifacts/t6/android/input-stream.json`, `artifacts/t6/macos/input-selection.json`, `artifacts/t6/ios/input-stream.json`이며 Git에서 제외한다. 개수·지원 여부·시각만 저장하고 입력 바이트·경로·키는 넣지 않는다. 오류·시간 초과 검사도 자체 OS 저장소 정책·표식만 finally에서 정리했다. 새 이미지·PDF fixture를 만들지 않았으며 기존 기획 PDF 원본은 보존했다.

자세한 계약·재현 방법·플랫폼/메모리 소거 한계는 `input-design.md`를 따른다. Windows, 실물 iOS 카메라, Finder 실제 마우스 전달은 완료로 간주하지 않는다.

최종 회귀 검사: 실제 macOS runner의 `integration_test/app_smoke_test.dart`가 통과했다. 이후 일반 `lib/main.dart` 진입점으로 macOS debug `.app`, iOS Simulator debug `.app`, Android debug APK를 모두 다시 빌드했다. 최종 Android 병합 manifest에 마이크·외부 저장소 읽기/쓰기 권한이 없는 것을 확인했다. 이번 검증용 iPhone 18 Pro와 읽기 전용 Android 인스턴스만 종료하고, 기존 다른 iOS 시뮬레이터 2개는 유지했다. 원본 기획 Markdown·PDF의 SHA-256은 최초 기록과 동일하다.

## GitHub 저장소 설정

2026-11-21 사용자 요청: `https://github.com/slee1005/compliance_calendar.git`를 이 작업공간의 `origin`으로 연결했다. 기존 브랜치가 없는 빈 공개 저장소와 사용자 push 권한을 확인했다. 기존 Git 작성자 설정을 사용한다.

초기 소스는 SDK·빌드·캡처·로컬 설정·서명/키 파일을 제외한다. `pubspec.lock`과 원본 기획 Markdown/PDF는 포함한다. GitHub CI의 바이너리 artifact 업로드는 기본 비활성화하고 수동 실행에서만 선택할 수 있게 했다. 원격 연결만으로 Windows 검사 통과를 주장하지 않는다.
