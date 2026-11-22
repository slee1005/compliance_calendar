import 'package:material_ui/material_ui.dart';

import '../../app/app_controller.dart';
import '../../core/security/app_lock_controller.dart';
import '../security/lock_view.dart';
import '../../shared/widgets/section_card.dart';

/// Explicit security readiness and preview controls for the initial scaffold.
class SettingsScreen extends StatelessWidget {
  /// Never presents an unimplemented security control as active.
  const SettingsScreen({
    super.key,
    required this.controller,
    this.lockController,
  });

  /// Actual lock service, absent only in the UI-only preview.
  final AppLockController? lockController;

  /// Preview state to clear or re-enter onboarding.
  final AppController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionCard(
        title: '보안 연결 상태',
        subtitle: '실제 개인정보 저장은 아직 활성화되지 않았습니다.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('SQLCipher 캐시 · 준비 중'),
            SizedBox(height: 14),
            Text('OS 키 보관 · 준비 중'),
            SizedBox(height: 14),
            Text('운영 정보 연결 · 준비 중'),
            SizedBox(height: 14),
            Text('복구·키 회전·감사 로그 · 준비 중'),
          ],
        ),
      ),
      const SizedBox(height: 20),
      SectionCard(
        title: '앱 잠금',
        child: LockSettings(controller: lockController),
      ),
      const SizedBox(height: 20),
      const SectionCard(
        title: '수집하지 않을 정보',
        child: Text(
          '문서 이미지·PDF·썸네일, 주민번호·SSN, 생년월일, 주소·전화번호, 건강정보 상세, 신원조회 보고서 원문을 저장하지 않는 설계입니다.',
        ),
      ),
      const SizedBox(height: 20),
      SectionCard(
        title: '화면 미리보기',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('가상 예시 표시'),
              subtitle: const Text('이 기기의 메모리에만 표시됩니다.'),
              value: controller.example,
              onChanged: controller.setExample,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: controller.restart,
              child: const Text('처음 화면으로 돌아가기'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const SectionCard(
        title: '요금제 · 계획',
        child: Text(
          'Free: 활성 10건, 캘린더 동기화·3단계 알림 포함\nPro: 연 \$24, 무제한·OCR·감사 리포트\n\n현재 구매·과금·구매 복원 기능은 연결되지 않았습니다.',
        ),
      ),
    ],
  );
}
