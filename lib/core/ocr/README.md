# 입력·OCR 경계

T6 메모리 입력 계약과 controller를 구현했다. `EphemeralDocument`는 20MiB·10초 제한의 단일 소유 버퍼이며 처리·오류·취소·잠금 시 제로화한다. 모바일은 카메라 스트림, 데스크톱은 읽기 전용 파일 capability를 사용한다. 사진 파일·썸네일·OCR 텍스트·경로를 저장하거나 전송하지 않는다.

실제 어댑터 선택은 `app/document_inputs.dart`와 bootstrap에서 수행한다. feature는 플랫폼 API를 호출하지 않는다. 현재는 잠금과 별도 동의가 필요한 가상·비식별 문서 입력 시험만 제공한다. T7 OS OCR, T8 후보 추출·확인은 아직 구현하지 않았다. 네트워크·DB·캘린더 접근 금지는 유지한다.

정확한 계약은 `docs/small-biz-compliance-planner.md` 7장과 `docs/input-design.md`를 따른다.
