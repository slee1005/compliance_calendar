# crypto

T3 암호화·키 관리 모듈입니다. UI·Calendar·DB I/O와 분리되어 있습니다.

- `KeyStore` / `OsKeyStore`: 값 없는 오류와 OS별 보안 저장소·배타 접근.
- `KeyManager`: 32바이트 CSPRNG 조직 키 생성·재읽기·회전, 이전 슬롯 보존.
- `KeyDerivation`: 필드별 HKDF-SHA256과 명시한 버전의 DB raw key 유도.
- `FieldCipher`: 번호 AES-256-GCM·AAD 인증·버전별 복호화·지연 재암호화.

정확한 계약은 루트의 `docs/crypto-design.md`와 원문 7.3을 따릅니다. 키는 명시적으로 초기화하며, 정상 읽기 경로에서 유실된 키를 자동 재생성하지 않습니다. 호출자는 직접 연 키 핸들을 사용 후 `destroy()`해야 합니다. SQLCipher 연결·앱 잠금은 T4/T5의 범위입니다.

macOS·iOS Simulator·Android 에뮬레이터의 네이티브 검사를 통과했습니다. Windows는 보존 정책 패치를 적용했으며 실제 실행은 보류 상태입니다. 운영 UI의 보안 기능은 아직 활성화하지 않았습니다.
