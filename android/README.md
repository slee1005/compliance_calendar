# Android

Android 전용 네이티브 코드와 빌드 설정을 이 폴더에서 관리합니다. 공통 화면은 루트 `lib/`를 사용합니다.

- 네이티브 진입: `app/src/main/kotlin/com/smallbizcompliance/license_manager/MainActivity.kt`
- 권한·앱 이름: `app/src/main/AndroidManifest.xml`
- 빌드: `app/build.gradle.kts`, `settings.gradle.kts`
- 임시 개발 applicationId: `com.smallbizcompliance.license_manager`

루트에서 실행:

```sh
./tool/flutter build apk --debug
./tool/flutter run -d <android-device-id>
```

Java 17과 Android SDK가 필요합니다. T3 OS 키 저장소는 Android API 36 에뮬레이터에서 생성·재읽기·회전 검사를 통과했습니다. 실제 기기는 미검증이며 운영 UI에는 연결하지 않았습니다. OCR·알림·Play Billing은 미연결입니다. 후속 네이티브 서비스는 이 경계와 `packages/ocr_engine`에 추가합니다. `local.properties`, Keystore, `key.properties`는 로컬 전용입니다. 릴리스 서명은 별도 설정해야 합니다.

T4 SQLCipher 4.20.0 캐시·변경 큐·키 회전 후 DB 재열기·평문 미검출 검사를 같은 에뮬레이터의 profile 앱에서 통과했습니다. 500건 삽입 36.73ms + 필터 1.62ms입니다. ARM64 ranchu/goldfish의 잘못된 SVE 기능 보고 때문에 OpenSSL이 종료되는 문제는 `MainActivity.onCreate`의 에뮬레이터 전용 `OPENSSL_armcap=0` 설정으로 우회했습니다. 실제 CPU의 탐지 설정은 바꾸지 않습니다. 정확한 범위와 재현 명령은 루트의 `docs/storage-design.md`를 따릅니다.

T5는 `FlutterFragmentActivity`·AppCompat·USE_BIOMETRIC으로 실제 기기 인증을 연결하고, FLAG_SECURE·focus/pause/screen-off 덮개를 추가했습니다. API 36의 실제 OS PIN 입력과 5분 이상 배경 전환 후 재인증을 검사했습니다. 테스트는 자체 읽기 전용 에뮬레이터에서 수행하며 실제 기기 생체 센서는 미검증입니다. 상세 계약은 `docs/app-lock-design.md`를 따릅니다.

T6는 공식 CameraX image stream으로 연결했습니다. audio off이며 마이크·외부 저장소 권한을 병합에서 제거합니다. API 36 읽기 전용 합성 카메라에서 실제 100프레임 제로화와 app temp/cache 문서 파일 0건을 확인했습니다. 사진 촬영·동영상·갤러리 저장 API는 호출하지 않습니다. 실제 기기 센서는 미검증입니다. `docs/input-design.md`를 참고하세요.
