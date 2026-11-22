# Windows

Windows 전용 C++ runner, CMake, 창·리소스 설정을 이 폴더에서 관리합니다. 공통 화면은 루트 `lib/`를 사용합니다.

- 진입·창: `runner/main.cpp`, `runner/flutter_window.cpp`
- 앱 리소스: `runner/Runner.rc`
- 빌드: `CMakeLists.txt`, `runner/CMakeLists.txt`

Windows에서 Flutter 3.50.1과 Visual Studio의 Desktop development with C++ 워크로드를 설치한 뒤 루트에서 실행합니다.

```powershell
flutter pub get --enforce-lockfile
flutter run -d windows
flutter build windows --debug
flutter test integration_test/crypto_smoke_test.dart -d windows
./tool/capture_preview.ps1 -DeviceId windows
```

산출물: `build/windows/x64/runner/Debug/`. 캡처 도구는 루트의 `tool/` 경로를 사용합니다. 캡처 실행 후 일반 앱 산출물이 필요하면 `flutter build windows --debug`를 다시 실행합니다.

macOS에서는 Windows 네이티브 빌드를 수행할 수 없습니다. GitHub Actions의 Windows 작업으로 별도 검증하도록 준비했으며, 아직 실행하지 않았습니다. 사용자 승인에 따라 Windows 검증은 보류 중입니다.

T3 OS 키 저장소 어댑터와 DPAPI 백엔드 보존 정책 패치를 구현했습니다. `packages/flutter_secure_storage_windows/UPSTREAM.md`에 출처와 변경 범위를 기록했습니다. 읽기 오류 시 키 파일을 삭제하거나 빈 저장소로 취급하지 않습니다. Windows 전용 손상 파일 검사와 네이티브 생성·회전 검사는 Windows 환경에서 실행해야 하며, 현재 통과로 간주하지 않습니다. Windows.Media.Ocr·토스트·MSIX·코드 서명은 후속 단계에서 연결합니다.

T4는 공통 `sqlite3` native hook의 `source: sqlcipher`로 Windows 빌드를 지정했습니다. Windows DLL 로딩·DB 보관·변경 큐·성능은 아직 실행 검증하지 않았습니다. 환경이 준비되면 루트의 `docs/storage-design.md`와 `test_driver/storage_driver.dart`로 확인합니다. CI 작업 작성만으로 실행 성공으로 간주하지 않습니다.

T5 공통 앱 비밀번호·Windows Hello 어댑터와 Win32 덮개·epoch·WTS 세션 잠금·절전 신호, `WDA_EXCLUDEFROMCAPTURE` 요청을 추가했습니다. 빌드·실행·잠금 해제·캡처 제한 모두 Windows 검증 보류 항목입니다. 환경이 준비되면 `flutter drive --driver=test_driver/lock_driver.dart --target=integration_test/lock_smoke_test.dart -d windows`와 실제 Windows Hello를 검증합니다. 계약은 `docs/app-lock-design.md`를 따릅니다.

T6는 GetOpenFileNameW·WM_DROPFILES·읽기 전용 worker를 구현했습니다. 가상 파일·네트워크·reparse point를 거부하고 단일 사용 capability만 Flutter에 전달합니다. shell32·comdlg32를 연결했습니다. Windows 빌드·선택·드롭·원본 보존은 아직 실행 미검증이며 `docs/input-design.md`와 input_smoke_test.dart로 확인해야 합니다.
