import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import 'device_authenticator.dart';

/// Official local_auth adapter; no authentication success is synthesized.
final class OsDeviceAuthenticator implements DeviceAuthenticator {
  /// The OS dialog owns all biometric/device-password input.
  OsDeviceAuthenticator();
  final LocalAuthentication _auth = LocalAuthentication();
  @override
  Future<DeviceAuthCapabilities> capabilities() async {
    var device = false;
    var biometrics = false;
    try {
      device = await _auth.isDeviceSupported();
    } catch (_) {
      /* unavailable */
    }
    try {
      biometrics = (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      /* unenrolled */
    }
    return DeviceAuthCapabilities(
      deviceCredential: device,
      biometrics: biometrics,
    );
  }

  @override
  Future<DeviceAuthOutcome> authenticate({bool biometricOnly = false}) async {
    if (kIsWeb ||
        (biometricOnly && defaultTargetPlatform == TargetPlatform.windows)) {
      return DeviceAuthOutcome.unavailable;
    }
    try {
      final ok = await _auth.authenticate(
        localizedReason: '자격·컴플라이언스 앱 잠금을 해제합니다.',
        biometricOnly: biometricOnly,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: false,
      );
      return ok ? DeviceAuthOutcome.success : DeviceAuthOutcome.denied;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled => DeviceAuthOutcome.cancelled,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout => DeviceAuthOutcome.lockedOut,
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noCredentialsSet =>
          DeviceAuthOutcome.unavailable,
        _ => DeviceAuthOutcome.failed,
      };
    } catch (_) {
      return DeviceAuthOutcome.failed;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _auth.stopAuthentication();
    } catch (_) {
      /* Remain locked. */
    }
  }
}
