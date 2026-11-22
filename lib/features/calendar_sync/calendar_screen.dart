import 'package:material_ui/material_ui.dart';

import '../../app/app_controller.dart';
import '../../shared/widgets/section_card.dart';

/// Dedicated-calendar connection state and masked event preview.
class CalendarScreen extends StatelessWidget {
  /// Uses fictional rows only; never opens OAuth or writes events.
  const CalendarScreen({super.key, required this.controller});

  /// Opt-in preview state.
  final AppController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionCard(
        title: 'Google Calendar',
        subtitle: '연결 안 됨',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('고객 소유의 전용 보조 캘린더 “자격·컴플라이언스”를 단일 원본으로 사용합니다.'),
            SizedBox(height: 16),
            DevelopmentNotice(
              message: 'OAuth 클라이언트와 최소 권한 검증 후 계정 연결을 제공합니다. 현재 Google에 전송되는 데이터는 없습니다.',
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      SectionCard(
        title: '캘린더에 표시될 내용',
        subtitle: '제목은 보유자 참조로 마스킹합니다. 아래는 전송되지 않는 화면 예시입니다.',
        child: controller.records.isEmpty
            ? const Text('예시 모드를 켜면 이벤트 제목을 미리 볼 수 있습니다.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final record
                      in controller.records
                          .where((r) => r.daysLeft >= 0)
                          .take(3))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '[갱신] ${record.type} · 보유자 참조',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${record.expiryAt(DateTime.now()).toIso8601String().split('T').first} · 09:00',
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      const SizedBox(height: 20),
      const SectionCard(
        title: '알아둘 점',
        child: Text(
          'Google Calendar는 종단간 암호화 저장소가 아닙니다. 이름·날짜·발급기관 등 최소 필드는 Google에서 처리하고, 라이선스 번호는 별도로 암호화하는 설계입니다. ICS 내보내기는 후속 단계에서 제공합니다.',
        ),
      ),
    ],
  );
}
