import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:license_manager/core/security/device_authenticator.dart';
import 'package:license_manager/core/security/os_device_authenticator.dart';
import 'package:license_manager/core/security/privacy_guard.dart';

final class _AuthPlatform extends LocalAuthPlatform {
  AuthenticationOptions? options;
  LocalAuthExceptionCode? failure;
  bool enrolled = true;
  @override
  Future<bool> isDeviceSupported() async => true;
  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async =>
      enrolled ? [BiometricType.strong] : [];
  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    this.options = options;
    if (failure != null) {
      throw LocalAuthException(
        code: failure!,
        description: 'PRIVATE-PLATFORM-DETAIL',
      );
    }
    return true;
  }

  @override
  Future<bool> stopAuthentication() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native auth allows OS passcode fallback and does not persist across background', () async {
    final previous = LocalAuthPlatform.instance;
    final platform = _AuthPlatform();
    LocalAuthPlatform.instance = platform;
    try {
      final auth = OsDeviceAuthenticator();
      expect(await auth.authenticate(), DeviceAuthOutcome.success);
      expect(platform.options!.biometricOnly, isFalse);
      expect(platform.options!.stickyAuth, isFalse);
      expect(platform.options!.sensitiveTransaction, isTrue);
      expect(platform.options!.useErrorDialogs, isFalse);
      platform.enrolled = false;
      final capabilities = await auth.capabilities();
      expect(capabilities.deviceCredential, isTrue);
      expect(capabilities.biometrics, isFalse);
      for (final (code, outcome) in [
        (LocalAuthExceptionCode.userCanceled, DeviceAuthOutcome.cancelled),
        (LocalAuthExceptionCode.temporaryLockout, DeviceAuthOutcome.lockedOut),
        (
          LocalAuthExceptionCode.noCredentialsSet,
          DeviceAuthOutcome.unavailable,
        ),
        (LocalAuthExceptionCode.unknownError, DeviceAuthOutcome.failed),
      ]) {
        platform.failure = code;
        expect(await auth.authenticate(), outcome);
      }
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        await auth.authenticate(biometricOnly: true),
        DeviceAuthOutcome.unavailable,
      );
    } finally {
      LocalAuthPlatform.instance = previous;
      debugDefaultTargetPlatformOverride = null;
    }
  });
  test(
    'native cover reveal uses newest epoch and ignores stale focus events',
    () async {
      const channel = MethodChannel('com.smallbizcompliance/privacy');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {
          'epoch': 5,
          'active': true,
          'cover': true,
          'capture': false,
          'files': false,
        };
      });
      final guard = NativePrivacyGuard();
      final events = <PrivacySignal>[];
      final subscription = guard.signals.listen(events.add);
      Future<void> signal(int epoch, String state) async {
        final done = Completer<void>();
        ServicesBinding.instance.channelBuffers.push(
          'com.smallbizcompliance/privacy',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('visibility', {'epoch': epoch, 'state': state}),
          ),
          (_) => done.complete(),
        );
        await done.future;
      }

      try {
        await guard.configure(lockEnabled: true);
        await signal(6, 'inactive');
        await signal(5, 'foreground');
        expect(events.last, PrivacySignal.inactive);
        await guard.reveal();
        expect((calls.last.arguments as Map)['epoch'], 6);
        expect((calls.first.arguments as Map)['enabled'], isTrue);
      } finally {
        await subscription.cancel();
        guard.dispose();
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );
}
