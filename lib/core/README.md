# 보안·동기화 코어

T3 암호화·키 관리와 T4 SQLCipher 캐시·변경 큐 서비스를 구현했다. 운영 데이터 UI와는 아직 연결하지 않았다. T5 앱 잠금은 실제 OS 인증·보안 저장소·네이티브 화면 보호를 루트 UI에 연결했다. 초기 앱의 메모리 예시 상태는 실제 고객 캐시를 사용하지 않는다. T6 메모리 입력은 잠금·동의를 요구하는 시험 화면에 연결했다. Calendar·OCR·알림 등은 후속 구현이다.

T2 운영 데이터 모델·payload는 `lib/shared/models/`에 구현했으며, 암호화·저장·네트워크 I/O와 분리되어 있다. 계약은 `docs/data-model.md`를 따른다.

암호화 계약과 플랫폼별 검증 범위는 `docs/crypto-design.md`를 따른다. macOS·iOS·Android의 실제 키 보관 검사는 통과했으며 Windows 실행 검증은 보류 중이다.

저장소 계약·키 버전 연결·원자적 변경 큐는 `docs/storage-design.md`, 잠금·인증·플랫폼 보호는 `docs/app-lock-design.md`를 따른다. 실제 정보 입력은 필수 플랫폼 검증과 입력 흐름 연결 전까지 열지 않는다.

| 모듈 | 담당 태스크 | 계약 |
|---|---|---|
| crypto | T3 | OS 보안 저장소, HKDF-SHA256, AES-256-GCM, 키 회전 |
| storage | T4 | SQLCipher 검증 후 캐시·큐·인덱스·감사 로그 |
| security | T5 | 앱 세션·OS 인증·앱 비밀번호·백그라운드 보호 |
| ocr | T6~T8 | 메모리 입력, OS OCR, 사용자 확인, finally 폐기 |
| calendar | T9~T12 | 최소 OAuth 권한, 이벤트 A/B, 멱등 쓰기, 동기화 |
| notify | T13 | 안정적 ID, D-30/D-7/D-1, 취소·재예약 |
| report | T15~T16 | 이미지 없는 감사 PDF·CSV·ICS |
| log | T3~ | 허용된 사건만 기록, 개인정보·경로·OCR 텍스트 제외 |

원문 7.1의 의존 방향을 따른다. UI와 결제 SDK를 암호화 모듈에 넣지 않는다. 지원되지 않는 플랫폼에서 평문 저장으로 폴백하지 않는다.
