import 'package:material_ui/material_ui.dart';

import '../../app/app_controller.dart';
import '../../app/router.dart';
import '../../shared/widgets/credential_tile.dart';
import '../../shared/widgets/section_card.dart';

/// Staff overview and staff-detail preview without a separate PII directory.
class StaffScreen extends StatelessWidget {
  /// Groups only the fictional staff aliases selected for preview.
  const StaffScreen({super.key, required this.controller});

  /// Application preview state.
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedStaff;
    final records = controller.records.where((r) => !r.isBusiness).toList();
    if (selected != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => controller.navigate(AppDestination.staff),
              icon: const Icon(Icons.arrow_back),
              label: const Text('직원 목록으로'),
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '$selected · 예시',
            subtitle: '요구 자격 목록을 설정하기 전에는 준수율을 계산하지 않습니다.',
            child: Column(
              children: [
                for (final record in records.where((r) => r.holder == selected))
                  CredentialTile(
                    record: record,
                    onTap: () => controller.showCredential(record),
                  ),
              ],
            ),
          ),
        ],
      );
    }
    final aliases = records.map((r) => r.holder).toSet().toList()..sort();
    return SectionCard(
      title: '사람별 자격 확인',
      subtitle: '실명 대신 별칭을 사용할 수 있습니다.',
      child: aliases.isEmpty
          ? const Text('아직 등록된 직원 자격이 없습니다.')
          : Column(
              children: [
                for (final alias in aliases)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_outline),
                    ),
                    title: Text(alias),
                    subtitle: Text(
                      '${records.where((r) => r.holder == alias).length}건 · 가상 별칭',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => controller.showStaff(alias),
                  ),
              ],
            ),
    );
  }
}
