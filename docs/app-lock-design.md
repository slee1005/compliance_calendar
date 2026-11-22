# T5 앱 잠금·생체인증·백그라운드 보호

기준: 플래너 v1.2 7장 T5. 공통 상태·인증 계약은 `lib/core/security/`, 화면은 `lib/features/security/`, 실제 서비스 조립은 `lib/app/security_bootstrap.dart`에 둔다. 플랫폼별 화면 가리기는 각 runner에 구현한다.

## 세션과 화면 경계

`AppLockController`는 loading → preview 또는 locked 상태로 시작한다. 정책을 읽거나 네이티브 보호를 설정하지 못하면 blocked 상태를 유지한다. 등록된 잠금은 프로세스 재시작마다 다시 인증해야 한다. 잠금 미등록 preview는 가상 자료 탐색만 허용하며 `authorized`는 항상 false다.

루트 `AppLockBoundary`는 Navigator 바깥에서 동작한다. 잠금 시 보호 화면 트리를 제거하고, 비활성 시 화면·포인터·접근성 의미 정보를 가린다. 잠금 화면은 비밀번호 선택·편집을 위한 자체 Overlay를 가진다. 잠금 해제 버튼이나 딥링크가 기존 업무 경로를 직접 열 수 없다.

백그라운드·창 포커스 상실 때 즉시 화면을 가린다. 5분 이상이면 재잠금한다. 타이머와 복귀 시 UTC 경과 시간·단조 시계를 함께 확인하므로 프로세스 정지나 시계 되돌리기로 세션을 연장하지 않는다. 짧은 비활성화는 화면만 가린다. OS 화면 잠금 신호와 수동 잠금은 즉시 세션을 무효화한다. 시간은 현재 명세 기본값 5분으로 고정한다.

Flutter lifecycle과 네이티브 가시성은 모두 전경이어야 한다. Flutter resumed만으로 녹화·OS 잠금·창 비활성 상태를 해제하지 않는다. OS 인증 중 잠깐 비활성화되는 경우 성공을 보류했다가 전경에서 적용한다. 취소·실패·시간 초과·수동 잠금 뒤 도착한 응답은 잠금을 풀지 못한다.

미래의 운영 데이터 작업은 `requireAuthorization()`이 반환한 세대 값을 보관하고, 비동기 결과를 사용하기 전에 같은 세대로 다시 검사해야 한다. `onLock`은 DB 핸들 닫기와 복호화 UI 상태 폐기의 조립 지점이다. 현재 예시 UI는 실제 SQLCipher 핸들을 열지 않으며 운영 데이터 연결을 완료했다고 주장하지 않는다. 이 앱 게이트는 T3 조직 키의 OS 접근 제어 정책 자체를 생체인증 전용으로 바꾸지 않는다.

## 인증·비밀번호 보관

- `DeviceAuthenticator`는 공식 `local_auth` 어댑터를 통해 실제 OS 인증을 요청한다. `biometricOnly: false`로 기기 PIN·패스코드 폴백을 허용한다. 취소 후 자동 재개하지 않으며 원시 플랫폼 오류를 노출하지 않는다. Windows는 이 API에서 생체인증만 강제할 수 없다.
- 기기 인증만으로 잠금을 등록할 때도 실제 인증을 먼저 요구한다. 지원되지 않는 장치는 앱 비밀번호를 사용할 수 있다. 앱 비밀번호는 12~128 Unicode scalar, 최대 UTF-8 512바이트이며 제어 문자·비정상 surrogate를 거부한다.
- 비밀번호는 PBKDF2-HMAC-SHA256 600,000회, 무작위 16바이트 salt, 32바이트 검증값으로 확인한다. KDF는 worker isolate에서 실행하며 소유한 바이트 버퍼는 가능한 범위에서 지운다. Dart 문자열의 완전한 메모리 소거는 보장하지 않는다.
- 정책·salt·검증값·재시도 메타데이터는 T3 `KeyStore` 안의 `lm.lock.policy.v1`에만 둔다. 소스·로그·일반 파일·SQLCipher 설정·분석 도구에 비밀번호를 쓰지 않는다. 등록 표식 `lm.lock.enrolled.v1`이 있는데 정책이 없으면 잠금을 해제하지 않는다.
- 초기 등록은 정책 쓰기·재읽기 검증 후 표식을 기록한다. 이후 명시적인 비활성화 기록을 쓰며, 표식을 지워서 등록 전 상태로 되돌리지 않는다. 조직 키·고객 캐시도 삭제하지 않는다.
- 검증 전 시도 횟수를 OS 저장소에 예약한다. 5회 이후 30초부터 지수형 지연을 적용하며 최대 8분이다. 성공 시 초기화하고 프로세스를 다시 열어도 재시도 제한을 보존한다.
- 인증 증명은 생성한 서비스 인스턴스·정책 revision에 묶이며 2분 이내 1회만 소비된다. 다른 인스턴스·오래된 설정·이미 사용한 증명은 거부한다. 정책 변경과 잠금 해제는 저장소의 프로세스 간 파일 잠금 안에서 재확인한다. OS 인증 창은 파일 잠금 밖에서 실행한다.
- 잠금 해제·설정 변경에 일반 `bool` 성공값을 주입하는 API는 없다. 설정 해제는 새 비밀번호 또는 OS 인증을 요구하고 보호 핸들·복호화 상태 정리를 기다린다. 설정 저장 중 수동 잠금이나 정리 실패가 발생하면 blocked 상태를 유지한다. 인증 오류와 저장소 오류는 구분하며, T3 `OsKeyStore.withExclusiveAccess`도 callback의 안전한 도메인 오류를 그대로 전달하도록 수정했다.

## 플랫폼 보호와 한계

| 플랫폼 | 구현 | 검증·제약 |
|---|---|---|
| Android | FragmentActivity, AppCompat, USE_BIOMETRIC; FLAG_SECURE; pause·focus loss·screen-off 네이티브 덮개 | API 36 에뮬레이터. 실제 하드웨어·벤더별 캡처 정책은 별도 검증 필요 |
| iOS | Face ID 사용 문구; UIScene 비활성·백그라운드·보호 데이터 신호; 화면 캡처 상태에 따른 덮개; Application Support/cache 디렉터리와 기존 DB 파일에 Complete 파일 보호 | iOS 27 Simulator에서는 파일 보호를 미검증(false)으로 반환. 모든 스크린샷 차단을 보장하지 않으며 실물 잠금 상태의 파일 I/O는 미검증 |
| macOS | NSView 덮개, 앱·창 비활성, NSWorkspace 화면 잠금·세션 신호 | 실제 네이티브 앱의 앱 비밀번호 경로 검증. 화면 캡처 차단은 지원한다고 표시하지 않음 |
| Windows | Win32 네이티브 덮개, 창 활성·WTS 세션·절전 신호, WDA_EXCLUDEFROMCAPTURE 요청 | 구현했으나 Windows 빌드·실행은 사용자 승인에 따라 보류. 캡처 제한도 아직 검증하지 않음 |

네이티브 덮개에는 개인정보 없는 고정 문구만 들어간다. focus loss 직후 OS callback에서 먼저 가리고, Dart가 안전한 프레임을 만든 뒤 현재 epoch가 일치할 때만 해제한다. 이전 프레임의 지연된 reveal은 새 덮개를 없애지 못한다. 실제 지원 결과는 화면에 표시하며 지원하지 않는 기능을 활성화했다고 안내하지 않는다.

비밀번호 입력창은 자동완성·제안·자동수정·IME 학습을 끄고, 비활성·다이얼로그 종료 시 내용을 비운다. 고객 문서·OCR·키·토큰을 이 보호 검증에 사용하지 않는다.

## 검증과 재현

```sh
bash tool/verify.sh
./tool/flutter drive --driver=test_driver/lock_driver.dart \
  --target=integration_test/lock_smoke_test.dart -d macos
```

같은 통합 검사를 iOS·Android·Windows의 실제 native device ID로 실행한다. 실행마다 별도 OS 저장소 namespace와 런타임 CSPRNG 비밀번호를 사용하고, finally에서 만든 정책·표식만 삭제·재확인한다. 테스트 입력값은 출력하지 않는다. 결과의 기능·지원 여부만 `artifacts/t5/<platform>/lock-*.json`에 남긴다. 해당 경로는 Git에서 제외한다.

`VERIFY_REAL_BACKGROUND=true` 실행은 실제 OS에서 앱을 5분 넘게 배경으로 전환했다가 복귀해야 끝난다. Android에서 실제 5분 이상 경과 후 재인증을 확인했다. 단위 테스트는 4분 59초·정확히 5분·시계 되돌림·반복 전환도 검사한다.

`VERIFY_NATIVE_BIOMETRICS=true`는 등록된 가상/실물 생체인증으로 등록·잠금 해제 두 번을 실제 OS API에서 승인해야 한다. iOS Simulator의 가상 Face ID로 이 경로를 확인했다. 시뮬레이터의 생체인증 알림은 개발 도구용이며 제품 코드에 포함하지 않는다. 이 결과는 실물 Face ID·Touch ID 센서 검증을 대신하지 않는다.

Android의 `tool/run_android_lock_test.py --device <id> --ephemeral-emulator`는 명시적으로 폐기할 에뮬레이터에서만 실행한다. 런타임 임시 PIN을 설정하고 확인된 OS 자격증명 창에만 입력한 뒤 삭제한다. 값을 로그에 쓰지 않는다. 개인·공유 기기에는 사용하지 않는다. 실행한 에뮬레이터를 종료해 임시 상태를 폐기한다.

macOS DEBUG runner에는 테스트가 실제 창을 활성화하도록 요청하는 `activateTestWindow`가 있다. OS focus를 실제로 요청할 뿐 인증 성공·가시성 값을 조작하지 않는다. profile/release에는 포함하지 않는다. CI는 비대화형 앱 비밀번호 경로를 사용하며 생체인증 성공을 가정하지 않는다.

네이티브 검사에서 비밀번호 등록 양식은 Flutter 테스트 텍스트 클라이언트를 사용한다. 잠금 해제 검사는 실제 controller·OS 저장소·PBKDF2를 호출한다. 양식의 편집·오류·재시도는 별도 위젯 검사로 확인하며, 실제 하드웨어 IME 입력 호환성은 파일럿에서 추가 검증한다.

테스트는 정책 손실·손상, 재시도 제한, 증명 만료·재사용·revision, 늦은 응답, cleanup 실패, 네이티브 epoch, 전체 탐색 우회 방지, 비밀번호 편집 Overlay, 375×667 / 1440×900 및 200% 글자 크기를 포함한다. 실제 실행 결과는 `implementation-status.md`를 따른다. 통합 테스트 후 일반 진입점으로 앱을 다시 빌드한다.

공식 근거: [Apple 파일 암호화·잠금 시 파일 핸들 관리](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files), [local_auth](https://pub.dev/packages/local_auth), [Android 구성](https://pub.dev/packages/local_auth_android), [Darwin 구성](https://pub.dev/packages/local_auth_darwin), [Apple sceneCaptureState](https://developer.apple.com/documentation/uikit/uitraitcollection/scenecapturestate), [Windows SetWindowDisplayAffinity](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity).
