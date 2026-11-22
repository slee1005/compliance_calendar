import 'package:material_ui/material_ui.dart';

import '../../shared/widgets/section_card.dart';

/// Read-only three-stage notification plan preview.
class RemindersScreen extends StatelessWidget {
  /// No alarms are scheduled by the scaffold.
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '기본 계획 · 오전 9:00',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
      ),
      const SizedBox(height: 12),
      const Text('무료 요금제에도 동일한 3단계 알림을 제공합니다.'),
      const SizedBox(height: 24),
      for (final stage in const [
        ('D-30', '갱신 준비', '한 달 전에 갱신 절차를 확인하세요.'),
        ('D-7', '마지막 주 확인', '갱신 서류와 진행 상태를 점검하세요.'),
        ('D-1', '만료 전 최종 확인', '내일 만료될 항목을 다시 확인하세요.'),
      ]) ...[
        SectionCard(
          title: '${stage.$1} · ${stage.$2}',
          subtitle: stage.$3,
          child: const Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Chip(
                avatar: Icon(Icons.notifications_none, size: 18),
                label: Text('푸시 예정'),
              ),
              Chip(
                avatar: Icon(Icons.mail_outline, size: 18),
                label: Text('이메일 예정'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
      const DevelopmentNotice(
        message: '아직 예약된 알림은 없습니다. Google 연결과 기기 알림 권한 설정 후 발송 경로를 검증합니다.',
      ),
    ],
  );
}
