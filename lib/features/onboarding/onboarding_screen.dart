import 'package:material_ui/material_ui.dart';

import '../../app/app_controller.dart';

/// First-run introduction with an explicit, optional fictional preview.
class OnboardingScreen extends StatelessWidget {
  /// Uses only process-local navigation state.
  const OnboardingScreen({super.key, required this.controller});

  /// Application navigation and preview state.
  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: Color(0xFFDDEFEA),
                    child: Icon(
                      Icons.verified_user_outlined,
                      size: 32,
                      color: Color(0xFF16776B),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  '서류 대신,\n갱신할 날짜만.',
                  style: Theme.of(context).textTheme.displaySmall
                      ?.copyWith(fontWeight: FontWeight.w700, height: 1.3),
                ),
                const SizedBox(height: 20),
                Text(
                  '작은 사업장을 위한 자격·컴플라이언스 관리',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                const _Promise(
                  icon: Icons.business_outlined,
                  text: '사업장 허가와 직원 자격을 한 화면에서',
                ),
                const _Promise(
                  icon: Icons.notifications_active_outlined,
                  text: 'D-30 · D-7 · D-1, 세 번의 갱신 알림',
                ),
                const _Promise(
                  icon: Icons.no_photography_outlined,
                  text: '서류 원본을 보관하지 않는 설계',
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    '개발 초기 미리보기\n아직 실제 정보를 입력하거나 저장할 수 없습니다. 예시는 가상 자료이며, 앱을 종료하면 초기화됩니다.',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('start-empty'),
                  onPressed: () => controller.start(),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('빈 화면으로 시작'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('start-example'),
                  onPressed: () => controller.start(example: true),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('예시로 둘러보기'),
                ),
                const SizedBox(height: 20),
                Text(
                  '계획된 요금제  ·  무료 10건  /  Pro 연 \$24\nWindows · macOS · iOS · Android',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
