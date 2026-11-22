import 'package:material_ui/material_ui.dart';

/// Fictional UI preview data; never a persistence or Calendar payload model.
class DemoCredential {
  /// Creates a preview row with a relative expiry for repeatable demonstrations.
  const DemoCredential({
    required this.type,
    required this.category,
    required this.holder,
    required this.isBusiness,
    required this.daysLeft,
  });

  /// Human-readable credential type.
  final String type;

  /// Preview category label.
  final String category;

  /// Fictional alias; no real staff data is bundled.
  final String holder;

  /// Whether the preview row belongs to a business.
  final bool isBusiness;

  /// Calendar-day offset relative to the preview date.
  final int daysLeft;

  /// Display-only status matching the planner's boundaries.
  String get status => switch (daysLeft) {
    < 0 => '만료',
    <= 7 => '초긴급',
    <= 30 => '긴급',
    <= 90 => '임박',
    _ => '정상',
  };

  /// Status is always paired with text and an icon in the UI.
  Color get color => switch (daysLeft) {
    <= 7 => const Color(0xFFB1323C),
    <= 30 => const Color(0xFF9E520E),
    <= 90 => const Color(0xFF826600),
    _ => const Color(0xFF16776B),
  };

  /// Text alternative to the status color.
  IconData get icon => switch (daysLeft) {
    < 0 => Icons.error_outline,
    <= 30 => Icons.schedule,
    <= 90 => Icons.timelapse,
    _ => Icons.check_circle_outline,
  };

  /// Display-only countdown.
  String get countdown => daysLeft < 0 ? '${-daysLeft}일 경과' : 'D-$daysLeft';

  /// Creates a calendar date without elapsed-hour DST arithmetic.
  DateTime expiryAt(DateTime today) =>
      DateTime(today.year, today.month, today.day + daysLeft);
}

/// Explicitly opt-in fictional records for the scaffold's UI preview.
const demoCredentials = <DemoCredential>[
  DemoCredential(
    type: 'CPR / BLS',
    category: '안전·보수교육',
    holder: 'A. Han',
    isBusiness: false,
    daysLeft: -12,
  ),
  DemoCredential(
    type: '전문 면허',
    category: '전문 면허',
    holder: 'B. Seo',
    isBusiness: false,
    daysLeft: 3,
  ),
  DemoCredential(
    type: '책임보험',
    category: '보험',
    holder: '예시 사업장',
    isBusiness: true,
    daysLeft: 14,
  ),
  DemoCredential(
    type: '사업 허가',
    category: '사업 허가',
    holder: '예시 사업장',
    isBusiness: true,
    daysLeft: 25,
  ),
  DemoCredential(
    type: '안전 교육',
    category: '안전·보수교육',
    holder: 'C. Lee',
    isBusiness: false,
    daysLeft: 54,
  ),
  DemoCredential(
    type: '시설 허가',
    category: '시설 허가',
    holder: '예시 사업장',
    isBusiness: true,
    daysLeft: 120,
  ),
  DemoCredential(
    type: '전문 면허',
    category: '전문 면허',
    holder: 'A. Han',
    isBusiness: false,
    daysLeft: 200,
  ),
];
