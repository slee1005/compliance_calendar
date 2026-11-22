# ocr_engine — T7 예정

플랫폼별 네이티브 OCR 코드를 담을 Flutter 플러그인 경계다. 현재 OCR 플러그인은 생성하지 않았다. T6의 스트림·읽기 전용 파일 입력은 `lib/core/ocr`, `lib/app/document_inputs.dart`, 플랫폼 runner에 구현했으며 별도 시험 동의와 잠금 해제 후에만 입력한다.

- iOS / macOS: Apple Vision
- Android: on-device ML Kit
- Windows: Windows.Media.Ocr

외부 계약은 메모리 바이트 입력·후보 텍스트 반환·취소·오류 처리다. 문서·프리뷰의 디스크 저장, 이미지 네트워크 전송, 자동 확정은 허용하지 않는다. 이미지·PDF 입력을 처리하는 실제 OS 브리지는 플랫폼별 잔여 파일 검사와 함께 추가한다.
