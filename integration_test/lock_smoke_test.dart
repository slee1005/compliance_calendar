import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:license_manager/app/app.dart';
import 'package:license_manager/app/app_controller.dart';
import 'package:license_manager/app/router.dart';
import 'package:license_manager/core/crypto/os_key_store.dart';
import 'package:license_manager/core/security/app_lock_controller.dart';
import 'package:license_manager/core/security/lock_credentials.dart';
import 'package:license_manager/core/security/os_device_authenticator.dart';
import 'package:license_manager/core/security/privacy_guard.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _wait(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final watch = Stopwatch()..start();
  while (true) {
    if (watch.elapsed > timeout) fail('Native lock condition timed out');
    var nativeActive = true;
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      final status = await const MethodChannel('com.smallbizcompliance/privacy')
          .invokeMapMethod<String, Object?>('activateTestWindow');
      nativeActive = status?['active'] == true;
    }
    if (predicate() && nativeActive) {
      await tester.pumpAndSettle();
      if (predicate()) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  }
}

String _password() {
  final random = SecretKeyData.random(length: 24);
  try {
    return base64Url.encode(random.bytes);
  } finally {
    random.destroy();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native lock enrolls, persists, conceals, authenticates and cleans its own slots',
    (tester) async {
      // Flutter's integration binding leaves the real IME connected by default.
      // Use the supported test text client to avoid native IME echoes replacing
      // injected editing values. OS authentication and KeyStore remain real.
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final store = OsKeyStore(
        service:
            'com.smallbizcompliance.t5.${DateTime.now().microsecondsSinceEpoch}',
      );
      final auth = OsDeviceAuthenticator();
      final app = AppController()
        ..start(example: true)
        ..navigate(AppDestination.settings);
      AppLockController create() => AppLockController(
        credentials: SecureLockCredentials(store, auth),
        privacy: NativePrivacyGuard(),
      );
      var lock = create();
      final password = _password();
      const channel = MethodChannel('com.smallbizcompliance/privacy');
      final caps = await auth.capabilities();
      try {
        await tester.pumpWidget(
          ComplianceApp(controller: app, lockController: lock),
        );
        // Real native focus is required. Desktop automation may activate the app.
        debugPrint('T5_READY_TO_FOREGROUND');
        lock.addListener(
          () => debugPrint(
            'T5_STATE ${lock.phase.name} visible=${lock.visible} busy=${lock.busy} failure=${lock.failure?.name}',
          ),
        );
        await _wait(
          tester,
          () => lock.phase == LockPhase.preview && lock.visible,
        );
        final setup = find.byKey(const Key('setup-password-lock'));
        await tester.ensureVisible(setup);
        await tester.tap(setup);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('security-password')),
          password,
        );
        await tester.enterText(
          find.byKey(const Key('security-password-confirm')),
          password,
        );
        await tester.tap(find.byKey(const Key('security-password-submit')));
        await _wait(tester, () => !lock.busy && lock.policy.enabled);
        expect(lock.authorized, isTrue);
        expect(
          (await store.read(SecureLockCredentials.policySlot))!
              .contains(password),
          isFalse,
        );
        lock.lock();
        await _wait(
          tester,
          () => !lock.busy && lock.phase == LockPhase.locked && lock.visible,
        );
        expect(await lock.unlockPassword(_password()), isFalse);
        await _wait(tester, () => !lock.busy && lock.visible);
        expect(lock.phase, LockPhase.locked);
        expect(lock.failure, LockFailure.denied);
        // Native contract check uses the actual verifier, not a UI editing
        // injection that can race desktop focus. Widget tests cover the form.
        expect(await lock.unlockPassword(password), isTrue);
        await _wait(tester, () => lock.authorized);

        // Exercise the real native epoch check without any auth-success test seam.
        lock.visibility(PrivacySignal.inactive);
        await tester.pump();
        final old = await channel.invokeMapMethod<String, Object?>('status');
        await lock.privacy.cover();
        await channel.invokeMethod<Object?>('reveal', {'epoch': old!['epoch']});
        final covered = await channel.invokeMapMethod<String, Object?>(
          'status',
        );
        expect(covered!['covered'], isTrue);
        lock.visibility(PrivacySignal.foreground);
        await tester.pumpAndSettle();

        if (const bool.fromEnvironment('VERIFY_REAL_BACKGROUND')) {
          debugPrint('T5_READY_FOR_REAL_BACKGROUND');
          await _wait(tester, () => !lock.visible);
          final start = DateTime.now().toUtc();
          await Future<void>.delayed(const Duration(minutes: 5, seconds: 1));
          debugPrint('T5_READY_TO_RETURN');
          await _wait(
            tester,
            () => lock.visible,
            timeout: const Duration(minutes: 3),
          );
          expect(
            DateTime.now().toUtc().difference(start),
            greaterThanOrEqualTo(const Duration(minutes: 5)),
          );
          expect(lock.phase, LockPhase.locked);
          expect(await lock.unlockPassword(password), isTrue);
          await _wait(tester, () => lock.authorized);
        }

        await tester.pumpWidget(const SizedBox.shrink());
        lock.dispose();
        lock = create();
        await tester.pumpWidget(
          ComplianceApp(controller: app, lockController: lock),
        );
        await _wait(
          tester,
          () => lock.phase == LockPhase.locked && lock.visible,
        );
        expect(find.byKey(const Key('nav-settings')), findsNothing);
        expect(await lock.unlockPassword(password), isTrue);
        await _wait(tester, () => lock.authorized);
        expect(await lock.disablePassword(password), isTrue);
        await tester.pumpAndSettle();

        var nativeBiometricsVerified = false;
        var nativeDeviceCredentialVerified = false;
        if (const bool.fromEnvironment('VERIFY_NATIVE_BIOMETRICS') ||
            const bool.fromEnvironment('VERIFY_NATIVE_DEVICE_CREDENTIAL')) {
          expect(caps.deviceCredential, isTrue);
          if (const bool.fromEnvironment('VERIFY_NATIVE_BIOMETRICS')) {
            expect(
              caps.biometrics,
              isTrue,
              reason: 'Enroll simulator biometrics before this test.',
            );
          }
          debugPrint('T5_READY_FOR_NATIVE_ENROLL_AUTH');
          final enrollment = lock.enableDevice();
          expect(await enrollment, isTrue);
          await _wait(tester, () => lock.visible && lock.authorized);
          lock.lock();
          await tester.pumpAndSettle();
          debugPrint('T5_READY_FOR_NATIVE_UNLOCK_AUTH');
          expect(await lock.unlockDevice(), isTrue);
          await _wait(tester, () => lock.authorized);
          nativeBiometricsVerified = const bool.fromEnvironment(
            'VERIFY_NATIVE_BIOMETRICS',
          );
          nativeDeviceCredentialVerified = true;
        }
        final status = await channel.invokeMapMethod<String, Object?>('status');
        expect(status!['cover'], isTrue);
        if (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.windows) {
          // Capture restriction is disabled after explicit disable, unless OS-only
          // enrollment above enabled it again. No unsupported success is inferred.
          expect(status['capture'], lock.policy.enabled);
        }
        binding.reportData = {
          'lock': {
            'platform': defaultTargetPlatform.name,
            'nativeDeviceAuthenticationAvailable': caps.deviceCredential,
            'nativeBiometricsEnrolled': caps.biometrics,
            'nativeBiometricsVerified': nativeBiometricsVerified,
            'nativeDeviceCredentialVerified': nativeDeviceCredentialVerified,
            'nativeCoverVerified': covered['covered'] == true,
            'cacheFileProtectionConfigured': status['files'] == true,
            'realFiveMinuteBackgroundVerified': const bool.fromEnvironment(
              'VERIFY_REAL_BACKGROUND',
            ),
            'passwordPersistenceVerified': true,
            'verifiedAtUtc': DateTime.now().toUtc().toIso8601String(),
          },
        };
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        lock.dispose();
        app.dispose();
        await store.withExclusiveAccess(() async {
          for (final slot in [
            SecureLockCredentials.policySlot,
            SecureLockCredentials.markerSlot,
          ]) {
            await store.delete(slot);
            expect(await store.read(slot) == null, isTrue);
          }
        });
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
