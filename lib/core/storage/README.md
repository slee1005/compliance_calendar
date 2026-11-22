# storage

T4 SQLCipher 캐시·변경 큐·인덱스·감사 로그를 구현했습니다. 운영 UI에는 아직 연결하지 않았습니다.

- `LocalCache`: 계정별 cache UUID와 OS 보안 저장소의 DB 키 버전 연결.
- `ComplianceDatabase`: SQLCipher 런타임 확인과 worker isolate의 연결·트랜잭션.
- `LicenseRepository`: 암호화 payload upsert/list/filter/softDelete, revision 비교, 원자적 outbox·감사 쓰기.
- `cache_models.dart`: 상태·검색·대기 작업·설정·동기화 참조 타입.

일반 SQLite·평문 파일 폴백과 UI 의존은 없습니다. 잘못된 키·손상 파일을 삭제하거나 키를 자동 생성하지 않습니다. 운영 구성은 `LocalCache`를 사용해 조직 키 회전 후에도 기존 DB 키 버전을 보존해야 합니다. DB rekey와 실제 Calendar 동기화는 아직 제공하지 않습니다.

정확한 계약과 검증 명령은 루트의 `docs/storage-design.md`, 실제 실행 결과는 `docs/implementation-status.md`를 따릅니다. Windows 실행 검증은 사용자 승인에 따라 보류 중입니다.
