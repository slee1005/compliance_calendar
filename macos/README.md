# macOS

macOS 전용 Swift 코드, Xcode 프로젝트, sandbox·공증 설정을 이 폴더에서 관리합니다. 공통 화면은 루트 `lib/`를 사용합니다.

- 창·진입: `Runner/MainFlutterWindow.swift`, `Runner/AppDelegate.swift`
- 앱 이름·bundle ID: `Runner/Configs/AppInfo.xcconfig`
- 권한: `Runner/DebugProfile.entitlements`, `Runner/Release.entitlements`
- 현재 runner 최소 대상: macOS 12.0

루트에서 실행:

```sh
./tool/flutter run -d macos
./tool/flutter build macos --debug
```

산출물: `build/macos/Build/Products/Debug/Compliance Manager.app`.

개발용 빌드는 공증된 배포본이 아닙니다. T3 private login Keychain은 네이티브 앱에서 생성·재읽기·회전 검사를 통과했습니다. 공유 그룹·프로비저닝이 필요 없는 백엔드이며, iOS ThisDeviceOnly와 같은 하드웨어 정책으로 설명하지 않습니다. 운영 UI에는 아직 연결하지 않았습니다. Vision·로컬 알림은 후속 구현입니다. 필요해진 시점에만 네트워크·파일 접근 권한을 추가하고 실제 sandbox 동작을 검증합니다.

T4 SQLCipher 4.20.0 캐시·변경 큐·키 회전 후 DB 재열기·평문 미검출 검사를 네이티브 profile 앱에서 통과했습니다. 500건 삽입 44.87ms + 필터 1.03ms입니다. 재현 명령은 루트의 `docs/storage-design.md`를 따릅니다.

T5는 실제 OS 인증 또는 앱 비밀번호, NSView 덮개·epoch, 앱·창 비활성 및 화면 잠금 신호를 연결했습니다. 실제 앱 비밀번호 등록·재시작·해제를 검사하며 Touch ID 센서 승인은 별도입니다. DEBUG 전용 `activateTestWindow`는 테스트 창을 실제 활성화하는 요청이며 인증을 우회하지 않습니다. 캡처 차단은 지원한다고 표시하지 않습니다. 상세 계약은 `docs/app-lock-design.md`를 따릅니다.

T6는 NSOpenPanel·NSDraggingDestination과 user-selected read-only entitlement를 추가했습니다. 로컬 정규 파일만 worker에서 읽고 원본·복사본·bookmark를 앱 저장소에 쓰지 않습니다. 실제 선택기와 native pasteboard 100회 입력·제로화·문서 파일 0건을 확인했습니다. 실제 Finder 마우스 드래그는 별도 미검증입니다. DEBUG의 stageTestDrop은 동일 receiver를 테스트하며 권한·전경 검사를 우회하지 않습니다. `docs/input-design.md`를 참고하세요.
