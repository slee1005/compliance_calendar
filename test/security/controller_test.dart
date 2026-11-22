import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:license_manager/core/security/app_lock_controller.dart';
import 'package:license_manager/core/security/lock_credentials.dart';
import 'package:license_manager/core/security/privacy_guard.dart';

import '../support/lock_support.dart';

void main() {
  late TestLockCredentials credentials;
  late TestPrivacyGuard privacy;
  late TestLockClock clock;
  late AppLockController lock;
  setUp(() {
    credentials = TestLockCredentials();
    privacy = TestPrivacyGuard();
    clock = TestLockClock();
    lock = AppLockController(
      credentials: credentials,
      privacy: privacy,
      clock: clock,
    );
  });
  tearDown(() => lock.dispose());
  test(
    'launch never exposes configured content before authentication',
    () async {
      expect(lock.canShowContent, isFalse);
      await lock.initialize();
      expect(lock.phase, LockPhase.locked);
      expect(lock.canShowContent, isFalse);
      expect(privacy.configurations, [true, true]);
      expect(await lock.unlockDevice(), isTrue);
      expect(lock.authorized, isTrue);
      final generation = lock.requireAuthorization();
      lock.lock();
      expect(
        () => lock.requireAuthorization(generation: generation),
        throwsA(isA<LockException>()),
      );
    },
  );
  test(
    'disable clears protected resources and blocks if cleanup fails',
    () async {
      lock.dispose();
      lock = AppLockController(
        credentials: credentials,
        privacy: privacy,
        clock: clock,
        onLock: () async => throw StateError('TEST-CLEANUP-FAILED'),
      );
      await lock.initialize();
      await lock.unlockDevice();
      expect(await lock.disablePassword('UNUSED-UI-TEST-VALUE'), isFalse);
      expect(lock.phase, LockPhase.blocked);
      expect(lock.canShowContent, isFalse);
      expect(lock.authorized, isFalse);
    },
  );
  test(
    'manual lock during disable commit cannot restore visible preview',
    () async {
      await lock.initialize();
      await lock.unlockDevice();
      credentials.disabling = Completer<LockPolicy>();
      final disabling = lock.disablePassword('UNUSED-UI-TEST-VALUE');
      await Future<void>.delayed(Duration.zero);
      lock.lock();
      credentials.disabling!.complete(const LockPolicy.disabled());
      expect(await disabling, isFalse);
      expect(lock.phase, LockPhase.blocked);
      expect(lock.canShowContent, isFalse);
    },
  );
  test(
    'disabled policy allows fictional preview but never authorizes real data',
    () async {
      credentials.policy = const LockPolicy.disabled();
      await lock.initialize();
      expect(lock.canShowContent, isTrue);
      expect(lock.authorized, isFalse);
      expect(privacy.configurations, [true, false]);
      expect(() => lock.requireAuthorization(), throwsA(isA<LockException>()));
    },
  );
  test('storage and native bridge failures block rather than falling back to preview', () async {
    credentials.error = LockFailure.corruptConfiguration;
    await lock.initialize();
    expect(lock.phase, LockPhase.blocked);
    expect(lock.canShowContent, isFalse);
    credentials.error = null;
    privacy.fail = true;
    await lock.retry();
    expect(lock.phase, LockPhase.blocked);
    privacy.fail = false;
    await lock.retry();
    expect(lock.phase, LockPhase.locked);
  });
  test(
    'cancelled, denied and rate-limited authentication retain the lock',
    () async {
      await lock.initialize();
      for (final reason in [
        LockFailure.cancelled,
        LockFailure.denied,
        LockFailure.rateLimited,
        LockFailure.unavailable,
      ]) {
        credentials.error = reason;
        expect(await lock.unlockDevice(), isFalse);
        expect(lock.phase, LockPhase.locked);
        expect(lock.failure, reason);
      }
    },
  );
  test('manual lock invalidates a late successful prompt', () async {
    await lock.initialize();
    credentials.authentication = Completer<LockAuthorization>();
    final result = lock.unlockDevice();
    lock.lock();
    credentials.authentication!.complete(TestAuthorization());
    expect(await result, isFalse);
    expect(lock.authorized, isFalse);
  });
  test(
    'manual lock while validating a successful proof cannot unlock',
    () async {
      await lock.initialize();
      credentials.validation = Completer<LockPolicy>();
      final result = lock.unlockDevice();
      await Future<void>.delayed(Duration.zero);
      lock.lock();
      credentials.validation!.complete(credentials.policy);
      expect(await result, isFalse);
      expect(lock.authorized, isFalse);
    },
  );
  test(
    'absence shorter than five minutes preserves authorization behind a cover',
    () async {
      await lock.initialize();
      await lock.unlockDevice();
      lock.visibility(PrivacySignal.inactive);
      expect(lock.canShowContent, isFalse);
      clock.advance(const Duration(minutes: 4, seconds: 59));
      lock.visibility(PrivacySignal.foreground);
      expect(lock.authorized, isTrue);
      lock.visibility(PrivacySignal.background);
      clock.advance(const Duration(minutes: 5));
      lock.visibility(PrivacySignal.foreground);
      expect(lock.phase, LockPhase.locked);
    },
  );
  test(
    'wall-clock rollback fails closed even without five monotonic minutes',
    () async {
      await lock.initialize();
      await lock.unlockDevice();
      lock.visibility(PrivacySignal.background);
      clock.now = clock.now.subtract(const Duration(days: 1));
      lock.visibility(PrivacySignal.foreground);
      expect(lock.phase, LockPhase.locked);
    },
  );
  test(
    'native recording/focus loss cannot be overridden by Flutter resumed',
    () async {
      await lock.initialize();
      await lock.unlockDevice();
      privacy.signal(PrivacySignal.inactive);
      lock.visibility(PrivacySignal.foreground);
      expect(lock.canShowContent, isFalse);
      privacy.signal(PrivacySignal.foreground);
      expect(lock.authorized, isTrue);
      privacy.signal(PrivacySignal.locked);
      privacy.signal(PrivacySignal.foreground);
      expect(lock.phase, LockPhase.locked);
    },
  );
  test('native credential fallback may finish inactive but reveals only after resume', () async {
    await lock.initialize();
    credentials.authentication = Completer<LockAuthorization>();
    final result = lock.unlockDevice();
    lock.visibility(PrivacySignal.inactive);
    credentials.authentication!.complete(TestAuthorization());
    expect(await result, isTrue);
    expect(lock.authorized, isFalse);
    lock.visibility(PrivacySignal.foreground);
    expect(lock.authorized, isTrue);
  });
  test('five-minute absence rejects pending authentication success', () async {
    await lock.initialize();
    credentials.authentication = Completer<LockAuthorization>();
    final result = lock.unlockDevice();
    lock.visibility(PrivacySignal.background);
    clock.advance(const Duration(minutes: 5));
    lock.visibility(PrivacySignal.foreground);
    credentials.authentication!.complete(TestAuthorization());
    expect(await result, isFalse);
    expect(lock.authorized, isFalse);
  });
  test('repeated absences schedule a fresh background timer each time', () {
    lock.dispose();
    fakeAsync((async) {
      final c = TestLockCredentials();
      final p = TestPrivacyGuard();
      final t = TestLockClock();
      final controller = AppLockController(
        credentials: c,
        privacy: p,
        clock: t,
      );
      controller.initialize();
      async.flushMicrotasks();
      controller.unlockDevice();
      async.flushMicrotasks();
      controller.visibility(PrivacySignal.background);
      async.elapse(const Duration(seconds: 1));
      t.advance(const Duration(seconds: 1));
      controller.visibility(PrivacySignal.foreground);
      controller.visibility(PrivacySignal.background);
      t.advance(const Duration(minutes: 5));
      async.elapse(const Duration(minutes: 5));
      async.flushMicrotasks();
      expect(controller.phase, LockPhase.locked);
      expect(p.covers, greaterThan(0));
      controller.dispose();
    });
    // tearDown owns a fresh instance; avoid double disposal of ChangeNotifier.
    privacy = TestPrivacyGuard();
    lock = AppLockController(credentials: credentials, privacy: privacy);
  });
  test(
    'failed resource cleanup prevents a parallel unlock from revealing content',
    () async {
      lock.dispose();
      final cleanup = Completer<void>();
      privacy = TestPrivacyGuard();
      lock = AppLockController(
        credentials: credentials,
        privacy: privacy,
        clock: clock,
        onLock: () => cleanup.future,
      );
      await lock.initialize();
      lock.lock();
      final result = lock.unlockDevice();
      await Future<void>.delayed(Duration.zero);
      cleanup.completeError(StateError('PRIVATE-RESOURCE-ERROR'));
      expect(await result, isFalse);
      expect(lock.phase, LockPhase.blocked);
    },
  );
  test('enrollment errors distinguish invalid input from uncertain committed writes', () async {
    credentials.policy = const LockPolicy.disabled();
    await lock.initialize();
    credentials.error = LockFailure.weakPassword;
    expect(await lock.enablePassword(''), isFalse);
    expect(lock.phase, LockPhase.preview);
    credentials.error = LockFailure.storageUnavailable;
    expect(await lock.enablePassword(''), isFalse);
    expect(lock.phase, LockPhase.blocked);
  });
}
