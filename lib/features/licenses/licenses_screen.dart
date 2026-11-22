import 'package:material_ui/material_ui.dart';

import '../../app/app_controller.dart';
import '../../app/router.dart';
import '../../shared/models/demo_credential.dart';
import '../../shared/widgets/credential_tile.dart';
import '../../shared/widgets/section_card.dart';

/// Read-only registry preview with search and category/holder filters.
class LicensesScreen extends StatefulWidget {
  /// Displays only explicitly enabled fictional records.
  const LicensesScreen({super.key, required this.controller});

  /// Navigation and preview state.
  final AppController controller;

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends State<LicensesScreen> {
  String _query = '';
  String _category = '전체';
  String _holder = '전체';

  @override
  Widget build(BuildContext context) {
    final selected = widget.controller.selectedCredential;
    if (selected != null) {
      return _CredentialDetail(controller: widget.controller, record: selected);
    }
    final records = widget.controller.records.where((record) {
      final text = '${record.type} ${record.holder} ${record.category}'
          .toLowerCase();
      return text.contains(_query.toLowerCase()) &&
          (_category == '전체' || record.category == _category) &&
          (_holder == '전체' || (_holder == '사업장') == record.isBusiness);
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DevelopmentNotice(
          message: '읽기 전용 화면 미리보기입니다. 실제 항목 등록은 모델·암호화·보안 저장소 검증 후 연결합니다.',
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('registry-search'),
          onChanged: (value) => setState(() => _query = value.trim()),
          decoration: const InputDecoration(
            labelText: '라이선스·보유자 검색',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in [
              '전체',
              '사업 허가',
              '전문 면허',
              '보험',
              '안전·보수교육',
              '시설 허가',
            ])
              FilterChip(
                label: Text(category),
                selected: _category == category,
                onSelected: (_) => setState(() => _category = category),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final holder in ['전체', '사업장', '직원'])
              ChoiceChip(
                label: Text('보유자: $holder'),
                selected: _holder == holder,
                onSelected: (_) => setState(() => _holder = holder),
              ),
          ],
        ),
        const SizedBox(height: 20),
        SectionCard(
          title: '${records.length}건 · 만료 임박순',
          child: records.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('표시할 항목이 없습니다. 예시 모드 또는 검색 조건을 확인하세요.'),
                )
              : Column(
                  children: [
                    for (final record in records)
                      CredentialTile(
                        record: record,
                        onTap: () => widget.controller.showCredential(record),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CredentialDetail extends StatelessWidget {
  const _CredentialDetail({required this.controller, required this.record});
  final AppController controller;
  final DemoCredential record;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => controller.navigate(AppDestination.licenses),
          icon: const Icon(Icons.arrow_back),
          label: const Text('목록으로'),
        ),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: record.type,
        subtitle: '${record.status} · ${record.countdown} · 예시 자료',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DetailLine(
              label: '보유자',
              value: '${record.holder} (${record.isBusiness ? '사업장' : '직원'})',
            ),
            _DetailLine(label: '유형', value: record.category),
            _DetailLine(
              label: '만료일',
              value: record
                  .expiryAt(DateTime.now())
                  .toIso8601String()
                  .split('T')
                  .first,
            ),
            const _DetailLine(label: '발급기관', value: '예시 발급기관'),
            const _DetailLine(label: '라이선스 번호', value: '미입력'),
            const _DetailLine(label: '원본 위치', value: '예시: 사무실 서류함'),
            const Divider(height: 32),
            const Text('알림 계획: D-30 · D-7 · D-1'),
            const SizedBox(height: 12),
            const Text('갱신 이력은 아직 없습니다. 이 화면은 고객 캘린더와 연결되지 않았습니다.'),
          ],
        ),
      ),
    ],
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}
