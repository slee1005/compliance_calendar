# 개발 도구

Flutter 3.50.1 / Dart 3.14.0을 사용한다. `pubspec.lock`은 커밋 대상이다. `tool/flutter`는 프로젝트의 `.tools/flutter` SDK를 우선 사용한다.

```sh
bash tool/verify.sh
./tool/flutter devices
./tool/flutter run -d macos
```

다른 기기는 `flutter devices`의 ID로 실행한다. Windows 빌드는 Windows 호스트에서 수행한다. 앱을 스토어에 올리거나 서명 인증서를 만들지 않는다.

네이티브 실행 검사:

```sh
./tool/flutter test integration_test/app_smoke_test.dart -d macos
```

UI 수동 확인: 첫 실행 → 빈 화면 → 예시 켜기 → 목록 검색 → 상세 → 직원 상세 → 더보기의 5개 화면 → 설정에서 예시 끄기. 샘플이 사라지고 연결 전 서비스가 준비 중으로 표시되는지 확인한다.

네이티브 화면 캡처는 `bash tool/capture_preview.sh <native-device-id>`로 실행한다. Windows에서는 `./tool/capture_preview.ps1 -DeviceId windows`를 사용한다. 통과한 실행의 화면 3장과 기기·화면 크기·시각을 `artifacts/t1/<platform>/`에 저장한다. 자세한 절차는 `docs/native-verification.md`를 따른다.

OS 보안 저장소 검사는 `./tool/flutter test integration_test/crypto_smoke_test.dart -d <native-device-id>`로 실행한다. 실행마다 격리된 테스트 namespace에 런타임 키를 만들고, 생성한 슬롯만 삭제·확인한다. 운영 키나 고정 조직 키 fixture를 사용하지 않는다. 이 검사도 일반 앱 산출물을 테스트 진입점으로 바꾸므로 이후 일반 앱을 다시 빌드한다.

SQLCipher와 변경 큐의 네이티브 검사는 다음과 같이 실행한다. macOS·Android는 profile 빌드에서 500건 삽입과 필터의 합계 50ms 기준도 검사한다. iOS Simulator의 debug 검사는 성능 기준을 강제하지 않는다. 실제 iOS 성능 검사는 실물 기기가 필요하다.

```sh
./tool/flutter drive --driver=test_driver/storage_driver.dart \
  --target=integration_test/storage_smoke_test.dart -d macos \
  --profile --dart-define=ENFORCE_STORAGE_PERFORMANCE=true
```

통과한 실행의 버전·측정값은 `artifacts/t4/<platform>/<mode>.json`에 보관한다. 키·SQL·레코드 값은 넣지 않는다. 자세한 계약과 다른 플랫폼 명령은 `docs/storage-design.md`를 따른다. 통합 테스트 후 일반 진입점으로 앱을 다시 빌드한다.

T5 네이티브 잠금 검사는 다음과 같다. 실제 OS 저장소에 임시 namespace를 만들고 런타임 무작위 비밀번호로 등록·오류·해제·재시작·네이티브 덮개를 확인한 뒤 자체 슬롯만 정리한다.

```sh
./tool/flutter drive --driver=test_driver/lock_driver.dart \
  --target=integration_test/lock_smoke_test.dart -d macos
```

네이티브 빌드·실행은 같은 작업공간에서 순차 수행한다. `VERIFY_NATIVE_BIOMETRICS=true`는 실제 OS 인증 승인을 두 번 요구한다. `VERIFY_REAL_BACKGROUND=true`는 OS에서 실제 5분 이상 배경 전환해야 한다. CI는 이 대화형 옵션 없이 앱 비밀번호 경로만 검사한다. macOS DEBUG의 테스트용 실제 창 활성화 요청은 인증을 대체하지 않는다.

폐기할 Android 에뮬레이터에서 OS PIN 폴백도 검사하려면 `python3 tool/run_android_lock_test.py --device <emulator-id> --ephemeral-emulator`를 실행한다. 임시 PIN은 메모리에만 유지하고 확인된 OS 자격증명 입력창에만 전송하며 마지막에 삭제한다. 개인·공유 기기에는 사용하지 않는다. 결과는 `artifacts/t5/<platform>/lock.json`과 password/device/biometric/background별 JSON에 지원 여부·성공 여부만 남긴다. 상세 제약은 `docs/app-lock-design.md`를 따른다.


T6 입력 수명·잔여 파일 검사는 다음과 같다. Android는 먼저 폐기할 합성 카메라 에뮬레이터에 테스트 앱을 설치하고 CAMERA만 허용한다. 실제 웹캠·고객 서류를 사용하지 않는다. iOS Simulator는 카메라 없음 처리를 확인하며 실물 스트림 성공으로 간주하지 않는다.

```sh
./tool/flutter drive --driver=test_driver/input_driver.dart \
  --target=integration_test/input_smoke_test.dart -d <native-device-id>
```

macOS 실제 선택기와 native pasteboard 100회 검사는 `VERIFY_DESKTOP_SELECTION=true`, `DESKTOP_TEST_SOURCE=<기존 기획 PDF 절대 경로>`를 추가한다. 선택기에서 그 원본을 한 번 선택해야 한다. `VERIFY_NATIVE_MOUSE_DROP=true`는 별도 Finder 마우스 드롭을 4분간 기다리는 수동 동선이다. 현재 이 동선은 검증 완료로 기록하지 않았다.

성공 결과는 `artifacts/t6/<platform>/input-*.json`에 개수·지원 여부만 보관한다. engine의 불변 바이트는 writable 소유 버퍼로 복사한 뒤 제로화한다. native AX를 사용하는 통합 검사는 OS가 의미 트리를 소유하도록 하고 종료 시 테스트 핸들을 해제한다. 자세한 한계는 `docs/input-design.md`를 따른다.

GitHub CI는 표준 러너를 사용한다. 기본 push/PR에서는 빌드 바이너리를 artifact 저장소에 올리지 않는다. 수동 실행의 `upload_artifacts`를 켜면 저장소 artifact 용량을 사용한다. 실제 실행 결과와 Windows 보류 상태는 진행 문서에 기록한다.
