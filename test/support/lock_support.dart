import 'dart:async';

import 'package:license_manager/core/security/app_lock_controller.dart';
import 'package:license_manager/core/security/device_authenticator.dart';
import 'package:license_manager/core/security/lock_credentials.dart';
import 'package:license_manager/core/security/privacy_guard.dart';

/// Test-only time source, independent of real device clocks.
final class TestLockClock implements LockClock {
  /// Initial fictional UTC timestamp.
  @override
  DateTime now = DateTime.utc(2026, 11, 21);

  /// Monotonic test duration.
  @override
  Duration elapsed = Duration.zero;

  /// Moves both clocks; callers may separately model a wall-clock change.
  void advance(Duration duration) {
    now = now.add(duration);
    elapsed += duration;
  }
}

/// Controller tests only; this proof is rejected by SecureLockCredentials.
final class TestAuthorization implements LockAuthorization {}

/// UI/state-machine test double; never imported by production.
final class TestLockCredentials implements LockCredentials {
  /// Initial fake policy.
  TestLockCredentials({
    this.policy = const LockPolicy.enabled(password: true, device: true),
  });

  /// Mutable scripted policy.
  LockPolicy policy;

  /// Optional scripted failure.
  LockFailure? error;

  /// Optional pause to exercise stale authentication races.
  Completer<LockAuthorization>? authentication;

  /// Optional pause between authentication and proof validation.
  Completer<LockPolicy>? validation;

  /// Optional pause while a disable operation commits.
  Completer<LockPolicy>? disabling;

  /// Recorded cancellations.
  int cancellations = 0;
  @override
  Future<LockPolicy> load() async {
    if (error != null) throw LockException(error!);
    return policy;
  }

  @override
  Future<DeviceAuthCapabilities> capabilities() async =>
      const DeviceAuthCapabilities(deviceCredential: true, biometrics: true);
  @override
  Future<LockAuthorization> authorizePassword(String password) async {
    if (error != null) throw LockException(error!);
    return authentication?.future ?? TestAuthorization();
  }

  @override
  Future<LockAuthorization> authorizeDevice({bool enrolling = false}) =>
      authorizePassword('');
  @override
  Future<LockPolicy> validate(LockAuthorization authorization) async =>
      validation?.future ?? policy;
  @override
  Future<LockPolicy> setPassword(
    String password, {
    bool allowDevice = false,
    LockAuthorization? authorization,
  }) async {
    if (error != null) throw LockException(error!);
    return policy = LockPolicy.enabled(password: true, device: allowDevice);
  }

  @override
  Future<LockPolicy> enableDevice(LockAuthorization authorization) async =>
      policy = const LockPolicy.enabled(password: false, device: true);
  @override
  Future<LockPolicy> disable(LockAuthorization authorization) async => policy =
      await (disabling?.future ?? Future.value(const LockPolicy.disabled()));
  @override
  Future<void> cancel() async {
    cancellations++;
  }
}

/// Scripted native cover, used only for unit and widget tests.
final class TestPrivacyGuard implements PrivacyGuard {
  final _events = StreamController<PrivacySignal>.broadcast(sync: true);

  /// Configurations attempted by the controller.
  final List<bool> configurations = [];

  /// Simulates a missing or failed bridge.
  bool fail = false;

  /// Simulates reveal errors without triggering a rebuild loop.
  bool failReveal = false;

  /// Number of safe-frame reveal calls.
  int reveals = 0;

  /// Number of cover requests.
  int covers = 0;
  @override
  Stream<PrivacySignal> get signals => _events.stream;

  /// Emits a native signal independently of Flutter lifecycle.
  void signal(PrivacySignal signal) => _events.add(signal);
  @override
  Future<PrivacyCapabilities> configure({required bool lockEnabled}) async {
    configurations.add(lockEnabled);
    if (fail) throw StateError('SIMULATED-PRIVATE-DETAIL');
    return const PrivacyCapabilities(
      nativeCover: true,
      captureProtection: false,
      fileProtection: false,
    );
  }

  @override
  Future<void> reveal() async {
    reveals++;
    if (failReveal) throw StateError('SIMULATED-PRIVATE-DETAIL');
  }

  @override
  Future<void> cover() async {
    covers++;
  }

  @override
  void dispose() {
    unawaited(_events.close());
  }
}

/// Authentication adapter double for testing the real OS credential store logic.
final class TestDeviceAuthenticator implements DeviceAuthenticator {
  /// Scripted native outcome, not a production implementation.
  DeviceAuthOutcome outcome = DeviceAuthOutcome.success;

  /// Scripted OS support.
  DeviceAuthCapabilities support = const DeviceAuthCapabilities(
    deviceCredential: true,
    biometrics: true,
  );
  @override
  Future<DeviceAuthCapabilities> capabilities() async => support;
  @override
  Future<DeviceAuthOutcome> authenticate({bool biometricOnly = false}) async =>
      outcome;
  @override
  Future<void> cancel() async {}
}
