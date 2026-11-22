import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:license_manager/app/app.dart';
import 'package:license_manager/app/app_controller.dart';
import 'package:license_manager/app/router.dart';
import 'package:license_manager/core/security/app_lock_controller.dart';
import 'package:license_manager/core/security/lock_credentials.dart';
import 'package:license_manager/core/security/privacy_guard.dart';

import '../support/lock_support.dart';

void main() {
  Future<(AppLockController, TestLockCredentials, AppController)> mount(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    double scale = 1,
    bool enabled = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final credentials = TestLockCredentials(
      policy: enabled
          ? const LockPolicy.enabled(password: true, device: true)
          : const LockPolicy.disabled(),
    );
    final lock = AppLockController(
      credentials: credentials,
      privacy: TestPrivacyGuard(),
      clock: TestLockClock(),
    );
    final app = AppController()
      ..start(example: true)
      ..navigate(AppDestination.settings);
    addTearDown(app.dispose);
    addTearDown(lock.dispose);
    await tester.pumpWidget(
      ComplianceApp(controller: app, lockController: lock),
    );
    await tester.pumpAndSettle();
    return (lock, credentials, app);
  }

  testWidgets(
    'root lock hides routes, aliases and accessibility until real service authorizes',
    (tester) async {
      final (lock, credentials, _) = await mount(tester);
      expect(find.text('앱이 잠겨 있습니다'), findsOneWidget);
      expect(find.textContaining('A. Han'), findsNothing);
      expect(find.byKey(const Key('nav-settings')), findsNothing);
      credentials.error = LockFailure.cancelled;
      await tester.tap(find.byKey(const Key('unlock-device')));
      await tester.pumpAndSettle();
      expect(find.text('인증이 취소되었습니다.'), findsOneWidget);
      credentials.error = null;
      await tester.enterText(
        find.byKey(const Key('unlock-password')),
        'UI-ONLY-NOT-A-CREDENTIAL',
      );
      await tester.tap(find.byKey(const Key('unlock-password-submit')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('앱 잠금 · 사용 중'), findsOneWidget);
      expect(lock.authorized, isTrue);
      lock.visibility(PrivacySignal.inactive);
      await tester.pump();
      expect(find.text('앱 잠금 · 사용 중'), findsNothing);
      expect(find.bySemanticsLabel('화면 보호 중'), findsOneWidget);
      lock.visibility(PrivacySignal.foreground);
      await tester.pumpAndSettle();
      lock.lock();
      await tester.pumpAndSettle();
      expect(find.text('앱이 잠겨 있습니다'), findsOneWidget);
    },
  );
  testWidgets(
    'a denied password clears editing and a fresh attempt can unlock',
    (tester) async {
      final (lock, credentials, _) = await mount(tester);
      final input = find.byKey(const Key('unlock-password'));
      credentials.error = LockFailure.denied;
      await tester.enterText(input, 'UI-ONLY-NOT-A-CREDENTIAL');
      await tester.tap(find.byKey(const Key('unlock-password-submit')));
      await tester.pumpAndSettle();
      expect(lock.authorized, isFalse);
      expect(tester.widget<TextField>(input).controller!.text.isEmpty, isTrue);
      expect(tester.testTextInput.isVisible, isFalse);
      credentials.error = null;
      await tester.enterText(input, 'UI-ONLY-FRESH-INPUT');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input).controller!.text ==
            'UI-ONLY-FRESH-INPUT',
        isTrue,
      );
      await tester.tap(find.byKey(const Key('unlock-password-submit')));
      await tester.pumpAndSettle();
      expect(lock.authorized, isTrue);
    },
  );
  testWidgets(
    'setup is explicit, validates confirmation, and disable asks for fresh proof',
    (tester) async {
      final (lock, credentials, _) = await mount(tester, enabled: false);
      expect(find.text('앱 잠금 · 꺼짐'), findsOneWidget);
      final setup = find.byKey(const Key('setup-password-lock'));
      await tester.ensureVisible(setup);
      await tester.tap(setup);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('security-password')),
        'UNUSED-UI-TEST-VALUE',
      );
      await tester.tap(find.byKey(const Key('security-password-submit')));
      await tester.pumpAndSettle();
      expect(find.text('두 비밀번호가 일치하지 않습니다.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('security-password-confirm')),
        'UNUSED-UI-TEST-VALUE',
      );
      await tester.tap(find.byKey(const Key('security-password-submit')));
      await tester.pumpAndSettle();
      expect(lock.policy.enabled, isTrue);
      final disable = find.byKey(const Key('disable-lock'));
      await tester.ensureVisible(disable);
      await tester.tap(disable);
      await tester.pumpAndSettle();
      credentials.error = LockFailure.denied;
      await tester.enterText(
        find.byKey(const Key('security-password')),
        'UNUSED-UI-TEST-VALUE',
      );
      await tester.tap(find.byKey(const Key('security-password-submit')));
      await tester.pumpAndSettle();
      expect(lock.policy.enabled, isTrue);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('인증되지 않았습니다. 다시 확인해 주세요.'),
        ),
        findsOneWidget,
      );
    },
  );
  for (final size in const [Size(375, 667), Size(1440, 900)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('lock, error and settings fit $size at $scale text', (
        tester,
      ) async {
        final (lock, credentials, _) = await mount(
          tester,
          size: size,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        credentials.error = LockFailure.denied;
        await lock.unlockDevice();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        credentials.error = null;
        await lock.unlockDevice();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final button = find.byKey(const Key('disable-lock'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
