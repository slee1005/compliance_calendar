import 'package:material_ui/material_ui.dart';

import '../../app/app_controller.dart';
import '../../app/router.dart';
import '../../shared/widgets/credential_tile.dart';
import '../../shared/widgets/section_card.dart';

/// Responsive starting overview with a true empty state by default.
class DashboardScreen extends StatelessWidget {
  /// Reads ephemeral preview state only.
  const DashboardScreen({super.key, required this.controller});

  /// Shell state and navigation.
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final records = controller.records;
    final expired = records.where((r) => r.daysLeft < 0).length;
    final urgent = records
        .where((r) => r.daysLeft >= 0 && r.daysLeft <= 30)
        .length;
    final upcoming = records
        .where((r) => r.daysLeft > 30 && r.daysLeft <= 90)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '갱신할 날짜,\n한눈에 확인하세요.',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700, height: 1.3),
        ),
        const SizedBox(height: 12),
        const Text('사업장 라이선스와 직원 자격을 함께 살펴봅니다.'),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 920 ? 4 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Metric(
                  width: width,
                  label: '만료',
                  value: '$expired',
                  hint: '기한이 지난 항목',
                  color: const Color(0xFFB1323C),
                  icon: Icons.error_outline,
                ),
                _Metric(
                  width: width,
                  label: '30일 내',
                  value: '$urgent',
                  hint: '오늘부터 30일까지',
                  color: const Color(0xFF9E520E),
                  icon: Icons.schedule,
                ),
                _Metric(
                  width: width,
                  label: '90일 내',
                  value: '$upcoming',
                  hint: '31~90일 사이',
                  color: const Color(0xFF826600),
                  icon: Icons.timelapse,
                ),
                _Metric(
                  width: width,
                  label: '누락',
                  value: '—',
                  hint: '요구 자격 설정 전',
                  color: const Color(0xFF526570),
                  icon: Icons.playlist_add_check,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        SectionCard(
          title: '먼저 챙길 항목',
          subtitle: '만료일이 가까운 순서로 최대 5건을 보여줍니다.',
          child: records.isEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.event_available_outlined,
                      size: 40,
                      color: Color(0xFF16776B),
                    ),
                    const SizedBox(height: 16),
                    const Text('아직 등록된 라이선스가 없습니다.'),
                    const SizedBox(height: 8),
                    const Text(
                      '보안 저장소 연결 후 실제 항목을 등록할 수 있습니다. 지금은 가상 자료로 화면을 살펴보세요.',
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: () => controller.setExample(true),
                      child: const Text('예시로 보기'),
                    ),
                  ],
                )
              : Column(
                  children: [
                    for (final record in records.take(5))
                      CredentialTile(
                        record: record,
                        onTap: () => controller.showCredential(record),
                      ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            controller.navigate(AppDestination.licenses),
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: const Text('라이선스 전체 보기'),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 20),
        const SectionCard(
          title: '서류 원본은 고객이 보관합니다',
          child: Text(
            '앱은 만료일과 핵심 정보만 관리하도록 설계합니다. 실사 때 원본을 찾을 수 있도록 보관 위치를 함께 기록할 예정입니다.',
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
    required this.icon,
  });
  final double width;
  final String label;
  final String value;
  final String hint;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineLarge
                  ?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(hint, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}
