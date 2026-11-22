# 소규모 사업장 자격·컴플라이언스 관리

플래너 v1.2를 기준으로 개발 중인 Flutter 4플랫폼 앱입니다. **T6: 카메라 스트림·읽기 전용 파일 입력을 구현했습니다.** Android 합성 카메라 100프레임과 macOS 선택기·네이티브 pasteboard 100회 입력 후 앱 임시·캐시 문서 파일 0건을 확인했습니다. Windows와 실물 iOS 카메라 검증은 남아 있습니다.

실제 직원 정보 입력·저장, Google 연동, OCR, 알림 발송, 결제는 아직 연결하지 않았습니다. 서류 입력은 앱 잠금 해제와 별도 동의가 필요한 가상·비식별 문서 시험만 제공합니다. 기본 화면은 비어 있고, 사용자가 “예시로 둘러보기”를 선택할 때만 가상 자료를 보여줍니다.

[GitHub 저장소](https://github.com/slee1005/compliance_calendar) · [CI](https://github.com/slee1005/compliance_calendar/actions)

## 플랫폼별 폴더

| 플랫폼 | 별도 관리 폴더 | 담당 범위 |
|---|---|---|
| Android | [android/](android/README.md) | Kotlin, Manifest, Gradle, 권한·스토어 빌드 |
| iOS | [ios/](ios/README.md) | Swift, Info.plist, Xcode, 권한·서명 |
| macOS | [macos/](macos/README.md) | Swift, Xcode, entitlements, 데스크톱 배포 |
| Windows | [windows/](windows/README.md) | C++, CMake, Windows runner·패키징 |

화면과 업무 규칙은 `lib/` 한 곳에서 공유합니다. 플랫폼별로 앱 전체를 복제하지 않습니다.

## 실행

Flutter **3.50.1**, Dart **3.14.0**을 사용합니다. 이 작업 환경에는 `.tools/flutter/`에 프로젝트 전용 SDK를 설치했습니다. SDK와 빌드 산출물은 버전 관리 대상에서 제외합니다. 다른 개발 환경에서는 같은 버전의 Flutter를 PATH에 설치하거나 `.tools/flutter/`에 준비하세요.

```sh
./tool/flutter pub get --enforce-lockfile
./tool/flutter devices
./tool/flutter run -d macos
```

Android/iOS는 연결된 기기·에뮬레이터 ID로 실행합니다. Windows에서는 `flutter run -d windows`를 사용합니다. VS Code에서는 `.vscode/launch.json`의 플랫폼 구성을 사용할 수 있습니다.

```sh
bash tool/verify.sh
./tool/flutter test integration_test/app_smoke_test.dart -d macos
./tool/flutter test integration_test/crypto_smoke_test.dart -d macos
bash tool/capture_preview.sh macos
```

## 현재 확인할 수 있는 것

- 온보딩, 빈 상태, 선택형 예시 모드, 모바일·데스크톱 공통 탐색
- 대시보드의 상태 타일과 우선 확인 목록
- 라이선스 검색·유형/보유자 필터와 읽기 전용 상세
- 직원별 목록·상세, 알림 플랜·마스킹 캘린더·리포트 범위 미리보기
- 설정에서 구현 상태 확인·예시 초기화
- 375×667 / 1440×900, 기본/200% 글자 크기 레이아웃 테스트
- GitHub Actions의 분석·테스트와 4플랫폼 디버그 빌드 구성
- 운영용 License 모델, 엄격한 날짜·UUID·길이 검증, 평문 번호와 분리된 Calendar payload
- 32바이트 조직 키, HKDF-SHA256, AES-256-GCM 번호 암호화, 키 회전·구버전 지연 재암호화
- SQLCipher worker, 계정별 캐시·키 버전 연결, revision을 비교하는 변경 큐, append-only 감사 이력
- 앱 비밀번호·OS 기기 인증, 5분 배경 재잠금, 네이티브 화면 가리기와 접근성 보호
- 스트림·파일의 단일 소유 버퍼, 20MiB·10초 제한, 취소·잠금 시 제로화
- 234개 테스트 통과, 기존 Windows 전용 1개 보류. 동일 필드 키에서 1만 회 nonce 중복 없음
- macOS·Android profile에서 캐시·큐·감사 500건 삽입과 필터 합계 50ms 미만 확인

현재 화면은 한국어 우선입니다. 운영 데이터 모델과 저장소가 연결되기 전 UI 예시 모델은 `DemoCredential`로 명확히 분리했습니다.

## 구현 순서

사용자 승인에 따라 Windows 검증은 후속으로 남기고 T6까지 구현했습니다. 다음은 T7~T8 기기 내 OCR·후보 확인 → T9~T12 Google Calendar → 알림·리포트·출시·구매입니다. Windows 검증은 출시 전 완료해야 합니다. 암호화·저장소 모듈은 아직 입력 UI와 연결하지 않았습니다. iOS Simulator는 기능 검사이며 실물 iOS 성능은 미검증입니다.

- [실제 검증 결과와 남은 작업](docs/implementation-status.md)
- [공통 구조와 데이터 경로](docs/architecture.md)
- [T2 데이터 모델 계약과 검증](docs/data-model.md)
- [T3 암호화·키 관리 계약과 검증](docs/crypto-design.md)
- [T4 SQLCipher·변경 큐·성능 검증](docs/storage-design.md)
- [T5 앱 잠금·인증·백그라운드 보호](docs/app-lock-design.md)
- [T6 입력 수명·무저장 검증](docs/input-design.md)
- [플랫폼 실행·스크린샷 검증](docs/native-verification.md)
- [구현 명세 원문](docs/small-biz-compliance-planner.md)
- [읽기용 PDF](docs/small-biz-compliance-planner.pdf)

## 안전한 개발 기준

이미지·PDF·썸네일을 고객 데이터로 저장하지 않습니다. 보안 저장소 연결 전 평문 파일·SQLite로 대체하지 않습니다. 토큰·키·서명 파일은 커밋하지 않습니다. 개발용 앱은 스토어 배포·실제 사업장 운영용 빌드가 아닙니다.
