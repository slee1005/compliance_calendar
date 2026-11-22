import 'package:flutter_test/flutter_test.dart';
import 'package:license_manager/app/app.dart';
import 'package:license_manager/app/app_controller.dart';
import 'package:license_manager/app/router.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<AppController> mount(
    WidgetTester tester, {
    bool example = false,
    bool started = true,
    Size size = const Size(1440, 900),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final controller = AppController();
    addTearDown(controller.dispose);
    if (started) controller.start(example: example);
    await tester.pumpWidget(ComplianceApp(controller: controller));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('first launch never silently loads fictional records', (
    tester,
  ) async {
    final controller = await mount(tester, started: false);
    expect(find.byKey(const Key('start-empty')), findsOneWidget);
    expect(controller.records, isEmpty);
    await tester.tap(find.byKey(const Key('start-empty')));
    await tester.pumpAndSettle();
    expect(find.text('아직 등록된 라이선스가 없습니다.'), findsOneWidget);
    expect(controller.example, isFalse);
  });

  testWidgets('example data requires explicit opt-in and can be removed', (
    tester,
  ) async {
    final controller = await mount(tester, started: false);
    await tester.tap(find.byKey(const Key('start-example')));
    await tester.pumpAndSettle();
    expect(controller.records, hasLength(7));
    expect(find.text('예시 모드 · 가상 자료입니다'), findsOneWidget);
    await tester.tap(find.text('예시 끄기'));
    await tester.pumpAndSettle();
    expect(controller.records, isEmpty);
    expect(find.text('아직 등록된 라이선스가 없습니다.'), findsOneWidget);
    expect(find.textContaining('A. Han'), findsNothing);
  });

  testWidgets('registry combines case-insensitive search and category filter', (
    tester,
  ) async {
    final controller = await mount(tester, example: true);
    await tester.tap(find.byKey(const Key('nav-licenses')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('registry-search')), 'a. han');
    await tester.pumpAndSettle();
    expect(find.text('2건 · 만료 임박순'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, '전문 면허'));
    await tester.pumpAndSettle();
    expect(find.text('1건 · 만료 임박순'), findsOneWidget);
    expect(controller.records, hasLength(7));
  });

  testWidgets(
    'preview detail navigation and clearing never retain a selected alias',
    (tester) async {
      final controller = await mount(tester, example: true);
      controller.showCredential(controller.records.first);
      await tester.pumpAndSettle();
      expect(find.text('목록으로'), findsOneWidget);
      expect(find.text('미입력'), findsOneWidget);
      await tester.tap(find.text('목록으로'));
      await tester.pumpAndSettle();
      expect(controller.selectedCredential, isNull);
      controller.showStaff('A. Han');
      await tester.pumpAndSettle();
      expect(find.text('A. Han · 예시'), findsOneWidget);
      controller.setExample(false);
      await tester.pumpAndSettle();
      expect(controller.selectedStaff, isNull);
      expect(find.textContaining('A. Han'), findsNothing);
    },
  );

  testWidgets('mobile more menu reaches secondary features', (tester) async {
    final controller = await mount(tester, size: const Size(375, 667));
    await tester.tap(find.text('더보기'));
    await tester.pumpAndSettle();
    final calendar = find.byKey(const Key('nav-calendar'));
    await tester.ensureVisible(calendar);
    await tester.tap(calendar);
    await tester.pumpAndSettle();
    expect(controller.destination, AppDestination.calendar);
    expect(find.text('연결 안 됨'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(375, 667), Size(1440, 900)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'all 11 preview screens fit ${size.width}x${size.height} at text scale $scale',
        (tester) async {
          final controller = await mount(
            tester,
            size: size,
            textScale: scale,
            started: false,
          );
          expect(tester.takeException(), isNull);
          controller.start(example: true);
          for (final destination in AppDestination.values) {
            controller.navigate(destination);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: destination.name);
          }
          controller.showCredential(controller.records.first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'credential detail');
          controller.showStaff('A. Han');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'staff detail');
        },
      );
    }
  }

  testWidgets('unconnected services never appear enabled', (tester) async {
    final controller = await mount(tester, example: true);
    controller.navigate(AppDestination.settings);
    await tester.pumpAndSettle();
    expect(find.text('SQLCipher 캐시 · 준비 중'), findsOneWidget);
    controller.navigate(AppDestination.report);
    await tester.pumpAndSettle();
    final export = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'PDF / CSV 내보내기 · 준비 중'),
    );
    expect(export.onPressed, isNull);
  });
}
