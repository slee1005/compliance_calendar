# 네이티브 실행 및 화면 검증

T1의 실행 증거는 실제 네이티브 runner에서 수집한다. 일반 `flutter test`의 위젯 렌더링을 플랫폼 실행 증거로 대체하지 않는다.

## 수집 내용

`integration_test/app_smoke_test.dart`는 온보딩에서 예시를 명시적으로 선택하고, 8개 주요 화면·라이선스 상세·직원 상세를 연 뒤 예시 상태를 초기화한다. `CAPTURE_PREVIEW=true`인 경우 온보딩·예시 대시보드·라이선스 목록 3장을 추가로 캡처한다.

모바일은 Flutter SDK의 `integration_test` 네이티브 화면 캡처를 사용한다. Android는 SDK 요구에 따라 먼저 렌더링 표면을 이미지 표면으로 전환한다. 데스크톱은 해당 SDK의 네이티브 캡처 지원 대상이 아니므로 실제 앱 안에서 `RenderRepaintBoundary.toImage`를 사용한다. 다른 앱 화면이나 데스크톱 창 테두리는 포함하지 않는다. 위젯 테스트의 가상 화면이나 디자인 시안이 아니다.

참고: [Flutter 공식 네이티브 통합 테스트](https://docs.flutter.dev/testing/integration-tests), [SDK 화면 캡처 지원과 사용법](https://github.com/flutter/flutter/blob/stable/packages/integration_test/README.md#screenshots).

모바일 캡처는 기기의 네이티브 해상도, 데스크톱은 논리 화면 크기·배율 1로 수집한다. 실제 캡처 방식·배율·PNG 크기는 `manifest.json`에 기록한다. 캡처 전에 앱 제목과 예시 모드 안내가 실제로 보이는지도 검사한다.

앱 쪽에는 파일 쓰기·캡처 공유 API를 추가하지 않는다. 테스트 드라이버가 **통과한 테스트에서 반환한 데이터만** 호스트의 `artifacts/t1/<platform>/`에 기록한다. 이 폴더는 Git에서 제외된다. 고객 문서는 사용하지 않는다.

캡처 실행은 빌드 산출물을 테스트 진입점으로 다시 만든다. 일반 앱을 다시 열 때는 `flutter run`으로 실행하거나 해당 플랫폼을 다시 빌드한다. CI는 화면 검증 후 일반 진입점으로 재빌드한 앱을 업로드한다.

출력:

```text
artifacts/t1/<platform>/
  onboarding.png
  dashboard.png
  licenses.png
  manifest.json
```

`manifest.json`에는 네이티브 대상 플랫폼, 기기 ID, 호스트 플랫폼, 캡처 시각, 화면별 크기, 테스트 성공 여부와 구성된 SDK 버전을 기록한다. 플랫폼은 허용 목록으로 확인하며, PNG 헤더와 크기를 확인한 뒤 저장한다. 이 파일만으로 코드 서명이나 출시 보안이 검증되는 것은 아니다.

## macOS / iOS / Android

루트에서 실행한다. 먼저 해당 시뮬레이터·에뮬레이터가 기동되어 있어야 한다.

```sh
bash tool/verify.sh
./tool/flutter devices
bash tool/capture_preview.sh macos
bash tool/capture_preview.sh <ios-simulator-id>
bash tool/capture_preview.sh <android-emulator-id>
```

캡처 없이 같은 동선을 검사하려면 다음을 사용한다.

```sh
./tool/flutter test integration_test/app_smoke_test.dart -d <native-device-id>
```

## Windows

Windows PC와 Visual Studio의 C++ 데스크톱 개발 도구가 필요하다. Flutter 3.50.1 / Dart 3.14.0을 설치하고 프로젝트 소스를 준비한 뒤 PowerShell에서 실행한다.

```powershell
flutter --suppress-analytics pub get --enforce-lockfile
flutter --suppress-analytics analyze --fatal-infos --fatal-warnings
flutter --suppress-analytics test
flutter --suppress-analytics build windows --debug
./tool/capture_preview.ps1 -DeviceId windows
```

CI에도 Windows·macOS 네이티브 실행·화면 수집을 추가했다. 실제 실행 전에는 미검증 상태를 유지한다. Windows 실행 환경이 없으면 T1을 완료로 표시하거나 자동으로 다음 마일스톤으로 넘어가지 않는다.

## 확인 절차

각 PNG를 열어 한글·아이콘·레이아웃과 예시 표시가 실제로 보이는지 확인한다. 실행 결과와 시각 검토를 모두 `implementation-status.md`에 기록한다. 실패 로그는 성공으로 바꾸지 않고 원인을 해결한 뒤 재실행한다.
