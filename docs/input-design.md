# T6 카메라·파일 입력 — 문서 무저장

플래너 v1.2 7.4와 T6를 구현한다. T7 문자 인식·T8 후보 확인·운영 데이터 저장은 연결하지 않는다. 화면의 완료 문구는 입력 버퍼 확인·폐기만 뜻하며 OCR 성공을 의미하지 않는다.

## 공통 소유권과 접근 계약

`core/ocr/document_input.dart`는 `CameraInput`, `DesktopInput`, `DocumentFile`, `InputAccess`, `EphemeralDocument`를 정의한다. `InputController`가 한 번에 하나의 입력을 소유한다. 플랫폼 구현 선택은 `app/security_bootstrap.dart`, 카메라·채널 어댑터는 `app/document_inputs.dart`에 있다. feature는 플랫폼 API와 `Platform.isX`를 사용하지 않는다. OCR·Calendar·SQLCipher·네트워크·결제 의존성을 입력 서비스에 넣지 않는다.

입력은 앱 잠금이 등록되고 현재 전경 세션이 인증됐을 때만 실행한다. `InputAccess`는 T5 `requireAuthorization`의 세대를 작업 전후로 검사한다. 취소·잠금·화면 이탈·백그라운드 전환 뒤 도착한 프레임은 결과로 사용하지 않고 폐기한다. 잠금 해제 설정 변경도 이전 작업의 세대를 무효화한다. 잠금 시 조립 계층에서 입력을 중단하고 데스크톱의 읽지 않은 선택 토큰을 철회한다.

현재 앱은 입력 시험 단계다. 사용자는 앱 잠금 설정·해제 후 스캔 화면에서 **가상·비식별 문서 시험**을 명시적으로 켜야 한다. 자동 카메라 시작, 실제 직원 필드 입력·저장, 인식 결과 시뮬레이션은 없다. 화면을 나가면 시험 동의와 네이티브 드롭 등록을 해제한다. 카메라는 복귀 시 자동 재시작하지 않는다.

`EphemeralDocument`는 소유권을 넘겨받은 mutable 버퍼만 처리한다. 파일은 총 20MiB 이하, raw 프레임은 최대 4096×4096 및 총 20MiB로 제한한다. raw BGRA 또는 YUV420의 row/pixel stride와 마지막 픽셀 범위를 확인하며 회전 0/90/180/270을 전달한다. 플랫폼 코덱이 불변 뷰를 전달할 수 있어 네이티브 파일 바이트는 writable 소유 버퍼로 복사한 뒤 처리한다. 파일은 PNG/JPEG/HEIC/PDF 헤더만 구분한다. 파일 전체의 디코딩·페이지 처리·유효성 판정은 T7 범위다.

소유 버퍼에는 **10초 절대 수명**을 둔다. 정상 종료, 소비자 예외, 취소, 접근 권한 변경, 타임아웃, 화면 이탈·잠금 시 `fillRange`로 즉시 제로화하고 수명 타이머를 취소한다. 중복 입력은 큐에 쌓지 않는다. 소비자는 callback이 끝난 뒤 바이트·별도 복사본을 보관하면 안 된다. 만료된 문서의 `planes` 접근은 실패한다. 완료 메타데이터는 형식과 바이트 수뿐이며 원본·경로·OCR 텍스트를 포함하지 않는다.

이 계약은 앱이 소유한 버퍼의 수명과 폐기에 관한 것이다. Dart 문자열, 플랫폼 채널 코덱, 카메라 드라이버, GPU·OS 내부 복사본 전체의 물리적 메모리 소거까지 보장하지 않는다. T7의 네이티브 인식기 역시 별도로 취소·자원 해제해야 한다. 이미지 디스크 캐시나 오류 시 파일 폴백으로 바꾸지 않는다.

## 모바일 카메라

공식 `camera 0.12.2`의 `startImageStream`만 사용한다. 공개 입력 인터페이스에 사진 촬영·동영상·갤러리 API가 없다. `takePicture`, 사진첩 저장, MediaStore insert를 호출하지 않는다. 따라서 촬영 임시 파일을 만들고 나중에 삭제하는 경로 자체가 없다.

- Android: CameraX YUV420, iOS: AVFoundation BGRA8888. `ResolutionPreset.medium`, `enableAudio: false`.
- 프레임은 요청이 있을 때만 한 개를 소유 버퍼로 복사한다. 요청하지 않은 프레임도 플러그인 전달 버퍼를 가능한 범위에서 제로화하고 참조를 버린다.
- preview는 네이티브 카메라 surface다. `Image.file`, 썸네일 생성, 디스크 캐시를 사용하지 않는다.
- 카메라 초기화 도중 취소돼도 늦게 완성된 controller를 종료한다. 카메라 권한 거부·장치 없음은 값 없는 오류로 표시한다. 권한 팝업으로 비활성화돼 초기화가 취소되면 허용 후 다시 시작한다.
- Android는 CAMERA만 추가하며 플러그인이 선언한 RECORD_AUDIO·WRITE_EXTERNAL_STORAGE·암묵적으로 병합된 READ_EXTERNAL_STORAGE를 manifest merge에서 제거한다. 카메라 없는 장치도 설치할 수 있다. 기존 T5 FLAG_SECURE가 등록된 잠금을 보호한다.
- iOS는 한국어 `NSCameraUsageDescription`을 추가한다. 마이크·사진첩 권한을 요청하지 않는다. T5 UIScene 덮개와 캡처 감지를 유지하며, 모든 스크린샷 차단을 보장하지 않는다.

카메라 스트림·수명 관리 공식 근거: [Flutter camera](https://pub.dev/packages/camera). 실제로 고정한 CameraX의 analyzer는 image planes를 전달하고 ImageProxy를 닫으며, AVFoundation의 stream은 video data output 경로다. 파일 저장 기능과 분리된 호출 경로를 확인했다. 패키지 버전은 `pubspec.lock`에 고정한다.

## 데스크톱 파일 선택·드롭

macOS·Windows의 네이티브 runner에서 직접 읽기 전용 입력을 구현한다. 파일 드롭 플러그인의 가상 파일 materialization이나 임시 복사에 의존하지 않는다. 외부 원본은 읽기만 하며 이동·덮어쓰기·삭제하지 않는다.

| 플랫폼 | 선택·드롭 | 읽기 정책 |
|---|---|---|
| macOS | NSOpenPanel, NSDraggingDestination, `.fileURL` pasteboard | 로컬 정규 파일·확장자 확인, security-scoped access를 읽는 동안만 사용, O_RDONLY/O_NOFOLLOW, background queue I/O |
| Windows | GetOpenFileNameW, WM_DROPFILES | 로컬 fixed/removable drive, GENERIC_READ, 정규 디스크 파일·크기 확인, worker thread I/O |

두 플랫폼은 한 개의 PNG/JPEG/HEIC/PDF만 받는다. 폴더, 심볼릭 링크·reparse point, URL 다운로드, 네트워크 드라이브, 클라우드 provider 파일은 거부한다. macOS는 NSFilePromiseReceiver를 등록하거나 실행하지 않는다. Windows는 가상 파일 OLE를 받지 않는다. 앱에 쓰기·갤러리·광범위 저장소 권한을 추가하지 않는다. macOS entitlement는 `user-selected.read-only`다.

Flutter에는 파일명·경로·bookmark 대신 **10초 유효한 단일 사용 토큰**만 넘긴다. native `read`는 토큰·수명·현재 전경 창을 다시 확인하고 최대 20MiB+1 범위로 읽는다. 이후 `release` 또는 만료·취소·잠금이 토큰을 철회한다. 네이티브 파일 읽기는 UI thread를 막지 않아 T5 덮개가 즉시 반응할 수 있게 한다. Flutter consumer가 실패해도 `finally`에서 원본 capability를 해제한다. 읽기·해제 실패가 성공 결과로 표시되지 않는다.

파일 선택기나 Finder가 포커스를 가지는 동안 원본 바이트를 읽지 않는다. 선택이 끝나면 현재 전경·기존 세대를 확인한 뒤 읽는다. 드롭은 실제 앱 창 활성화를 요청한 후 전경 확인을 기다린다. 세션·동의·화면이 바뀌면 읽지 않고 capability를 해제한다. 사용자 파일을 삭제하거나 앱 캐시를 일괄 삭제하는 정리 코드는 없다.

AppKit window 드롭의 공식 근거: [registerForDraggedTypes](https://developer.apple.com/documentation/appkit/nswindow/registerfordraggedtypes(_:)), [드래그 수신](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DragandDrop/Tasks/acceptingdrags.html). Windows는 로컬 shell 파일 드롭과 공통 파일 대화상자만 사용한다.

## 검증 방법

```sh
bash tool/verify.sh
./tool/flutter drive --driver=test_driver/input_driver.dart \
  --target=integration_test/input_smoke_test.dart -d <native-device-id>
```

자동 검사는 100회 소유 버퍼 처리, 모든 바이트 제로화, 10초 만료, 패딩된 plane, 크기·형식 거부, 비동기 초기화·읽기·소비 중 취소, 권한 세대 변경, 중복 입력, 원본 해제 실패를 검사한다. 화면은 375×667 / 1440×900 및 200% 글자 크기로 검사한다.

네이티브 검사는 앱의 temp, application cache, application support/cache를 실제 탐색하고 확장자뿐 아니라 PNG/JPEG/HEIF/PDF 헤더도 확인한다. 시작·종료 시 문서 파일이 0건이어야 통과한다. Windows GetTempPath는 공용이므로 다른 앱의 파일을 읽지 않고 예약된 앱 scratch 하위 경로와 앱 cache만 검사한다. T6 Windows 어댑터는 scratch 파일을 생성하지 않는다. Flutter 위젯·합성 버퍼 결과를 실제 카메라 성공으로 간주하지 않는다. Android 에뮬레이터는 실제 웹캠 대신 SDK의 합성 카메라를 사용한다. iOS Simulator에서 카메라가 없으면 unavailable로 남기며 실물 검증을 대신하지 않는다.

macOS의 선택기 검사는 원래 제공된 기획 PDF를 읽기 전용으로 선택한다. 추가 이미지·PDF fixture를 디스크에 만들지 않는다. `VERIFY_DESKTOP_SELECTION=true`와 `DESKTOP_TEST_SOURCE=<existing-planner-pdf>` 옵션은 실제 선택 후 같은 파일을 native pasteboard 수신 경로로 100회 읽는다. DEBUG 전용 `stageTestDrop`은 기존 파일 URL을 별도 pasteboard에 넣어 동일 receiver를 호출한다. sandbox 권한·T5 인증·전경 검사를 우회하지 않는다. 이 자동 검사는 실제 마우스 드래그 제스처 검증과 구분한다.

결과는 `artifacts/t6/<platform>/input.json`에 개수·지원 여부·UTC 시각만 기록한다. 소스 이름·경로·바이트·자격 증명을 기록하지 않는다. 임시 조직 키·고객 문서는 사용하지 않으며, T5 검증값은 실행마다 별도 namespace·CSPRNG 비밀번호로 만들고 자체 슬롯만 정리한다. 통합 테스트 후 일반 진입점으로 재빌드한다. 실제 결과와 Windows·실물 기기 보류 항목은 `implementation-status.md`를 따른다.
