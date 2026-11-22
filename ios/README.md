# iOS

iOS 전용 Swift 코드, Xcode 프로젝트, 권한·서명 설정을 이 폴더에서 관리합니다. 공통 화면은 루트 `lib/`를 사용합니다.

- 진입: `Runner/AppDelegate.swift`
- 앱 설정: `Runner/Info.plist`
- Xcode: `Runner.xcworkspace`
- 임시 개발 bundle ID: `com.smallbizcompliance.licenseManager`
- 현재 runner 최소 대상: iOS 15.0

루트에서 실행:

```sh
./tool/flutter build ios --simulator --debug --no-codesign
./tool/flutter run -d <ios-simulator-id>
```

macOS·Xcode·iOS Simulator가 필요합니다. 실제 기기에서는 개발자 팀·서명을 본인 환경에서 지정합니다. 개인 개발자 팀은 프로젝트에 고정하지 않았습니다. T3 private Keychain은 iPhone 18 Pro / iOS 27 Simulator에서 생성·재읽기·회전 검사를 통과했습니다. 실제 기기는 미검증이며 운영 UI에는 연결하지 않았습니다. Vision·StoreKit은 후속 단계에서 연결합니다.

T4 SQLCipher 4.20.0 캐시·변경 큐·키 회전 후 DB 재열기·평문 미검출 검사를 같은 시뮬레이터의 debug 앱에서 통과했습니다. 이 결과는 iOS 실물 기기 성능 검증을 대신하지 않습니다. 재현 명령은 루트의 `docs/storage-design.md`를 따릅니다.

T5는 `NSFaceIDUsageDescription`, 실제 LocalAuthentication, UIScene 기반 네이티브 덮개·epoch, 캡처 상태 감지와 SQLCipher 캐시 파일 보호를 연결했습니다. 시뮬레이터 가상 Face ID 검사는 실물 센서 검증을 대신하지 않습니다. iOS의 모든 스크린샷을 막을 수 있다고 표시하지 않습니다. 계약·실제 결과는 `docs/app-lock-design.md`와 `docs/implementation-status.md`를 따릅니다.

T6는 카메라 사용 문구와 AVFoundation BGRA 메모리 스트림을 연결했습니다. 마이크·사진첩 권한을 요청하지 않습니다. iOS 27 Simulator에서는 실제 플러그인이 카메라 없음으로 응답했고, 메모리 입력 100회 제로화·문서 파일 0건을 확인했습니다. 실물 스트림 성공으로 간주하지 않습니다. `docs/input-design.md`를 참고하세요.
