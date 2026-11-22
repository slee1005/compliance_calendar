import 'package:material_ui/material_ui.dart';

import '../../app/app_controller.dart';
import '../../shared/widgets/section_card.dart';

/// Image-free audit report scope and fictional summary preview.
class ReportScreen extends StatefulWidget {
  /// Displays no actual export or generated document until T15.
  const ReportScreen({super.key, required this.controller});

  /// Preview source.
  final AppController controller;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String _scope = '전체';

  @override
  Widget build(BuildContext context) {
    final records = widget.controller.records
        .where((r) => _scope == '전체' || (_scope == '사업장') == r.isBusiness)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: '실사 준비 요약',
          subtitle: '원본 이미지를 포함하지 않는 리포트를 준비합니다.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final scope in ['전체', '사업장', '직원'])
                    ChoiceChip(
                      label: Text(scope),
                      selected: _scope == scope,
                      onSelected: (_) => setState(() => _scope = scope),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                '대상 ${records.length}건',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                '만료 ${records.where((r) => r.daysLeft < 0).length}건 · 30일 내 ${records.where((r) => r.daysLeft >= 0 && r.daysLeft <= 30).length}건',
              ),
              const SizedBox(height: 24),
              const Text(
                '포함 예정: 요약 · 자격 현황 · 원본 보관 위치 · 수신자·목적 워터마크 · SHA-256',
              ),
              const SizedBox(height: 24),
              const OutlinedButton(
                onPressed: null,
                child: Text('PDF / CSV 내보내기 · 준비 중'),
              ),
              const SizedBox(height: 16),
              const DevelopmentNotice(
                message: '현재는 화면 요약만 제공합니다. 감사 PDF·CSV 내보내기는 Pro 기능으로 예정되어 있으며, 개인정보 마스킹과 내보내기 감사 기록을 함께 구현합니다.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
