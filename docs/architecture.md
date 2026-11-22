# 저장소와 플랫폼 관리

```text
Compliance_mgr/
  android/                  Android runner · Manifest · Kotlin · Gradle
  ios/                      iOS runner · Info.plist · Swift · signing
  macos/                    macOS runner · entitlements · Swift · signing
  windows/                  Windows runner · C++ · CMake · packaging
  lib/
    app/                    앱 진입 · 탐색 · 테마
    core/                   암호화 · 저장 · OCR · 캘린더 · 알림 · 리포트
    features/               기능별 화면
    shared/                 공통 위젯 · 모델
  packages/ocr_engine/      추후 플랫폼 OCR 플러그인 경계
  packages/flutter_secure_storage_windows/  출처·라이선스를 보존한 OS 저장소 정책 패치
  test/                     위젯 · 단위 테스트
  integration_test/         네이티브 실행 테스트
  tool/                     검증 · 빌드 도구
  docs/                     원본 플래너 · 진행 상태 · 설계 기록
```

네 개 앱을 복제하지 않는다. Flutter 표준 runner 폴더를 플랫폼별 소유 경계로 사용한다. 화면·업무 규칙 변경은 `lib/` 한 곳에서 수행하고, OS 권한·OCR 브리지·서명 설정은 해당 플랫폼 폴더에서 관리한다.

## 의존 방향

- `features` → 공통 모델과 추상 서비스. 플랫폼 API를 화면에서 호출하지 않는다.
- `core/crypto` → 검증된 암호화 라이브러리와 보안 저장소. UI와 Calendar에 의존하지 않는다.
- `core/calendar` → OAuth와 Calendar API. UI와 로컬 DB에 의존하지 않는다.
- `core/ocr` → 휘발성 입력과 OS OCR. Calendar·DB·네트워크 전송에 의존하지 않는다.
- `core/storage` → SQLCipher와 저장소 인터페이스. UI에 의존하지 않는다.
- `core/security` → 인증·화면 보호 인터페이스와 T3 `KeyStore`. Calendar·SQLCipher·위젯에 의존하지 않는다. `features/security`는 서비스 인터페이스를 사용하고 `app/security_bootstrap.dart`가 실제 OS 어댑터를 조립한다.
- `core/notify` → 플랫폼 알림 인터페이스. Calendar를 직접 호출하지 않는다.
- 앱 구성 계층에서 서비스를 조립한다. 플랫폼 분기는 서비스 구현 선택에 한정한다.

## 초기 앱의 경계

초기 화면은 개발 검토용이다. T6는 잠금 해제와 별도 시험 동의 후 가상·비식별 문서의 카메라·로컬 파일 입력만 실행한다. 실제 직원 필드 입력·저장, OCR, 캘린더 쓰기, 구매, 내보내기는 실행하지 않는다. 각 화면에 필요한 연결 상태를 표시한다. 예시 자료는 가상 별칭만 사용하며 기본 화면에 자동으로 섞지 않는다.

T4의 SQLCipher는 별도 worker isolate가 소유한다. 앱 구성은 `LocalCache`로 계정별 cache UUID와 OS 키 버전을 연결하고, 저장소는 번호가 암호화된 `LicensePayload`만 받는다. 캐시·변경 큐·감사는 한 트랜잭션에서 변경한다. 운영 UI·Calendar 동기화와의 연결은 아직 없다. 상세 계약은 `storage-design.md`를 따른다.

T5의 잠금 경계는 앱 Navigator 바깥에 있다. 잠금 미등록은 가상 예시만 허용한다. 실제 고객 데이터 작업은 `AppLockController.requireAuthorization()`의 세대 값을 비동기 작업 전후로 확인하고, 조립 계층의 `onLock`으로 DB 핸들·복호화 상태를 폐기해야 한다. 현재 UI는 운영 DB를 열지 않는다. 인증 증명·실패 횟수·네이티브 epoch 계약은 `app-lock-design.md`를 따른다.

## 운영 데이터 경로 — 후속 구현

T6는 `core/ocr`의 `CameraInput`·`DesktopInput`·`InputAccess`와 단일 `EphemeralDocument`를 사용한다. 조립 계층의 카메라 어댑터와 macOS·Windows 읽기 전용 브리지만 원본에 접근한다. frame/bytes는 10초 이내 또는 취소·잠금 시 제로화하며 입력 경로에 DB·네트워크·이미지 파일 쓰기가 없다. 자세한 수명·상태·검증 한계는 `input-design.md`를 따른다.

```text
메모리 입력 → 기기 내 OCR → 후보 확인 → 원본 버퍼 폐기
                                  ↓
6개 필드 검증 → 번호 필드 암호화 → SQLCipher 캐시/변경 큐
                                  ↓
Google 전용 캘린더: 만료 이벤트 A + D-30 준비 이벤트 B
                                  ↓
캘린더 동기화 → 캐시 → 대시보드 / 로컬 알림 / 감사 리포트
```

고객 원본 문서의 저장소는 앱 외부다. 자체 백엔드·이미지 보관·평문 캐시를 추가하지 않는다.
