import 'package:material_ui/material_ui.dart';

import '../features/calendar_sync/calendar_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/licenses/licenses_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/reminders/reminders_screen.dart';
import '../features/report/report_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/staff/staff_screen.dart';
import '../core/security/app_lock_controller.dart';
import '../features/security/lock_view.dart';
import '../core/ocr/input_controller.dart';
import 'app_controller.dart';
import 'router.dart';
import 'theme.dart';

/// Common application entry shared by all four native platform runners.
class ComplianceApp extends StatefulWidget {
  /// Optionally accepts process-local state for native smoke tests.
  const ComplianceApp({
    super.key,
    this.controller,
    this.lockController,
    this.inputController,
    this.cameraPreview,
  });

  /// Optional T6 input owner, supplied by the normal entrypoint.
  final InputController? inputController;

  /// Injected native preview builder; feature code has no platform API.
  final WidgetBuilder? cameraPreview;

  /// Optional only for UI-only preview composition; main always supplies it.
  final AppLockController? lockController;

  /// Injected controller; ownership stays with the caller when supplied.
  final AppController? controller;

  @override
  State<ComplianceApp> createState() => _ComplianceAppState();
}

class _ComplianceAppState extends State<ComplianceApp> {
  late final AppController _controller = widget.controller ?? AppController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '자격·컴플라이언스',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    builder: (context, child) => widget.lockController == null
        ? child!
        : AppLockBoundary(controller: widget.lockController!, child: child!),
    home: ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _controller.started
          ? _AppShell(
              controller: _controller,
              lockController: widget.lockController,
              inputController: widget.inputController,
              cameraPreview: widget.cameraPreview,
            )
          : OnboardingScreen(controller: _controller),
    ),
  );
}

class _AppShell extends StatefulWidget {
  const _AppShell({
    required this.controller,
    this.lockController,
    this.inputController,
    this.cameraPreview,
  });

  /// Optional T6 input owner, supplied by the normal entrypoint.
  final InputController? inputController;

  /// Injected native preview builder; feature code has no platform API.
  final WidgetBuilder? cameraPreview;
  final AppLockController? lockController;
  final AppController controller;

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  AppController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text(
          '자격·컴플라이언스',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        automaticallyImplyLeading: !desktop,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Chip(label: Text('개발 v0.1')),
          ),
        ],
      ),
      drawer: desktop
          ? null
          : Drawer(child: SafeArea(child: _navigation(closeDrawer: true))),
      bottomNavigationBar: desktop
          ? null
          : NavigationBar(
              selectedIndex: switch (controller.destination) {
                AppDestination.dashboard => 0,
                AppDestination.licenses => 1,
                AppDestination.staff => 2,
                _ => 3,
              },
              onDestinationSelected: (index) {
                if (index == 3) {
                  _scaffoldKey.currentState?.openDrawer();
                } else {
                  controller.navigate(
                    [
                      AppDestination.dashboard,
                      AppDestination.licenses,
                      AppDestination.staff,
                    ][index],
                  );
                }
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.space_dashboard_outlined),
                  label: '오늘',
                ),
                NavigationDestination(
                  icon: Icon(Icons.fact_check_outlined),
                  label: '라이선스',
                ),
                NavigationDestination(
                  icon: Icon(Icons.people_outline),
                  label: '직원',
                ),
                NavigationDestination(icon: Icon(Icons.menu), label: '더보기'),
              ],
            ),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (desktop)
              SizedBox(
                width: 240,
                child: Material(color: Colors.white, child: _navigation()),
              ),
            Expanded(
              child: SingleChildScrollView(
                key: ValueKey(
                  '${controller.destination.name}:${controller.selectedCredential?.type}:${controller.selectedCredential?.holder}:${controller.selectedStaff}',
                ),
                padding: EdgeInsets.all(desktop ? 32 : 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _previewBanner(),
                        const SizedBox(height: 24),
                        Text(
                          controller.destination.label,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: const Color(0xFF526570)),
                        ),
                        const SizedBox(height: 20),
                        _screen(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navigation({bool closeDrawer = false}) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.verified_user_outlined,
              color: Color(0xFF16776B),
              size: 36,
            ),
            SizedBox(height: 16),
            Text(
              '갱신 관리',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text('작은 사업장의 안심 루틴'),
          ],
        ),
      ),
      const SizedBox(height: 20),
      for (final destination in AppDestination.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            key: Key('nav-${destination.name}'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            selectedTileColor: const Color(0xFFE2F0EC),
            selectedColor: const Color(0xFF125F55),
            selected: controller.destination == destination,
            leading: Icon(destination.icon, size: 22),
            title: Text(destination.label),
            onTap: () {
              if (closeDrawer) Navigator.of(context).pop();
              controller.navigate(destination);
            },
          ),
        ),
      const Divider(height: 32),
      const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          '서류 무저장 · 최소 정보\n4플랫폼 공통 앱',
          style: TextStyle(fontSize: 12, height: 1.8),
        ),
      ),
    ],
  );

  Widget _previewBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFE2F0EC),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          controller.example ? '예시 모드 · 가상 자료입니다' : '개발 미리보기 · 실제 정보 입력 전',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text('기기에 저장하거나 외부로 전송하지 않습니다.'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => controller.setExample(!controller.example),
            child: Text(controller.example ? '예시 끄기' : '예시 켜기'),
          ),
        ),
      ],
    ),
  );

  Widget _screen() => switch (controller.destination) {
    AppDestination.dashboard => DashboardScreen(controller: controller),
    AppDestination.licenses => LicensesScreen(controller: controller),
    AppDestination.staff => StaffScreen(controller: controller),
    AppDestination.scan => ScanScreen(
      input: widget.inputController,
      lock: widget.lockController,
      cameraPreview: widget.cameraPreview,
    ),
    AppDestination.reminders => const RemindersScreen(),
    AppDestination.calendar => CalendarScreen(controller: controller),
    AppDestination.report => ReportScreen(controller: controller),
    AppDestination.settings => SettingsScreen(
      controller: controller,
      lockController: widget.lockController,
    ),
  };
}
