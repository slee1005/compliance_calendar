import 'package:material_ui/material_ui.dart';

/// Top-level destinations corresponding to the planner's screen inventory.
enum AppDestination {
  /// Today's overview.
  dashboard('대시보드', Icons.space_dashboard_outlined),

  /// Business and staff credential registry.
  licenses('라이선스', Icons.fact_check_outlined),

  /// Credentials grouped by staff alias.
  staff('직원', Icons.people_outline),

  /// On-device document extraction entry.
  scan('스캔·추출', Icons.document_scanner_outlined),

  /// Three-stage reminder plan.
  reminders('알림 플랜', Icons.notifications_none),

  /// Dedicated Google calendar connection.
  calendar('캘린더 연동', Icons.calendar_month_outlined),

  /// Audit summary preview and future export.
  report('실사 리포트', Icons.assessment_outlined),

  /// Security and application settings.
  settings('설정·보안', Icons.shield_outlined);

  const AppDestination(this.label, this.icon);

  /// Korean navigation label for the initial shell.
  final String label;

  /// An icon used alongside the text label.
  final IconData icon;
}
