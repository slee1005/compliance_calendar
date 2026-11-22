import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:license_manager/core/security/device_authenticator.dart';
import 'package:license_manager/core/security/lock_credentials.dart';

import '../support/crypto_support.dart';
import '../support/lock_support.dart';

String _password() {
  final random = SecretKeyData.random(length: 24);
  try {
    return base64Url.encode(random.bytes);
  } finally {
    random.destroy();
  }
}

Matcher _failure(LockFailure code) =>
    throwsA(isA<LockException>().having((e) => e.code, 'code', code));
void main() {
  late TestKeyStore store;
  late TestDeviceAuthenticator auth;
  late SecureLockCredentials credentials;
  late DateTime now;
  setUp(() {
    store = TestKeyStore();
    auth = TestDeviceAuthenticator();
    now = DateTime.utc(2026, 11, 21);
    credentials = SecureLockCredentials(store, auth, now: () => now);
  });
  tearDown(() => store.values.clear());
  test(
    'fresh preview is unconfigured; corrupt or lost enrollment fails closed',
    () async {
      expect((await credentials.load()).enabled, isFalse);
      store.values[SecureLockCredentials.markerSlot] = '1';
      await expectLater(
        credentials.load(),
        _failure(LockFailure.corruptConfiguration),
      );
      store.values[SecureLockCredentials.policySlot] = 'CORRUPT';
      await expectLater(
        credentials.load(),
        _failure(LockFailure.corruptConfiguration),
      );
      expect(store.values[SecureLockCredentials.policySlot], 'CORRUPT');
    },
  );
  test('device enrollment requires genuine adapter success, cancellation never enrolls', () async {
    auth.outcome = DeviceAuthOutcome.cancelled;
    await expectLater(
      credentials.authorizeDevice(enrolling: true),
      _failure(LockFailure.cancelled),
    );
    expect(store.values, isEmpty);
    auth.outcome = DeviceAuthOutcome.success;
    final grant = await credentials.authorizeDevice(enrolling: true);
    expect((await credentials.enableDevice(grant)).enabled, isTrue);
    final reloaded = SecureLockCredentials(store, auth, now: () => now);
    expect((await reloaded.load()).device, isTrue);
    await expectLater(
      credentials.disable(grant),
      _failure(LockFailure.authorizationRequired),
    );
    final fresh = await credentials.authorizeDevice();
    await credentials.disable(fresh);
    expect((await credentials.load()).enabled, isFalse);
    expect(store.values.containsKey(SecureLockCredentials.markerSlot), isTrue);
    store.values.remove(SecureLockCredentials.policySlot);
    await expectLater(
      credentials.load(),
      _failure(LockFailure.corruptConfiguration),
    );
  });
  test('password uses salted PBKDF2, rejects guesses, reloads and consumes authorization once', () async {
    final password = _password();
    final policy = await credentials.setPassword(password, allowDevice: true);
    expect(policy.password, isTrue);
    expect(policy.device, isTrue);
    final stored = store.values[SecureLockCredentials.policySlot]!;
    expect(stored.contains(password), isFalse);
    expect(jsonDecode(stored)['iterations'], 600000);
    await expectLater(
      credentials.authorizePassword(_password()),
      _failure(LockFailure.denied),
    );
    final grant = await credentials.authorizePassword(password);
    expect((await credentials.validate(grant)).enabled, isTrue);
    await expectLater(
      credentials.disable(grant),
      _failure(LockFailure.authorizationRequired),
    );
    final reloaded = SecureLockCredentials(store, auth, now: () => now);
    final fresh = await reloaded.authorizePassword(password);
    await reloaded.disable(fresh);
    expect((await credentials.load()).enabled, isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));
  test(
    'native grants expire and cross-service or forged grants are rejected',
    () async {
      final grant = await credentials.authorizeDevice(enrolling: true);
      now = now.add(const Duration(minutes: 3));
      await expectLater(
        credentials.enableDevice(grant),
        _failure(LockFailure.authorizationRequired),
      );
      await expectLater(
        credentials.enableDevice(TestAuthorization()),
        _failure(LockFailure.authorizationRequired),
      );
      final current = await credentials.authorizeDevice(enrolling: true);
      final other = SecureLockCredentials(store, auth, now: () => now);
      await expectLater(
        other.enableDevice(current),
        _failure(LockFailure.authorizationRequired),
      );
    },
  );
  test('policy revision changes invalidate an earlier OS proof', () async {
    final stale = await credentials.authorizeDevice(enrolling: true);
    final current = await credentials.authorizeDevice(enrolling: true);
    await credentials.enableDevice(current);
    await expectLater(
      credentials.validate(stale),
      _failure(LockFailure.authorizationRequired),
    );
  });
  test('invalid passwords never persist; unavailable OS credentials are not enabled', () async {
    for (final password in [
      '',
      'short',
      List.filled(129, 'a').join(),
      'long-invalid\nvalue',
    ]) {
      await expectLater(
        credentials.setPassword(password),
        _failure(LockFailure.weakPassword),
      );
    }
    expect(store.values, isEmpty);
    auth.support = const DeviceAuthCapabilities(
      deviceCredential: false,
      biometrics: false,
    );
    await expectLater(
      credentials.authorizeDevice(enrolling: true),
      _failure(LockFailure.unavailable),
    );
    await expectLater(
      credentials.setPassword(_password(), allowDevice: true),
      _failure(LockFailure.unavailable),
    );
    expect(store.values, isEmpty);
  });
  test(
    'failed writes and backend errors never leak details or report success',
    () async {
      store.failReads = true;
      try {
        await credentials.load();
        fail('expected error');
      } on LockException catch (e) {
        expect(e.code, LockFailure.storageUnavailable);
        expect(e.toString().contains('SIMULATED-PRIVATE'), isFalse);
      }
      store.failReads = false;
      store.discardWrites = true;
      final grant = await credentials.authorizeDevice(enrolling: true);
      await expectLater(
        credentials.enableDevice(grant),
        _failure(LockFailure.storageUnavailable),
      );
      expect(store.values, isEmpty);
    },
  );
  test('durable password retry limit survives service recreation', () async {
    final password = _password();
    await credentials.setPassword(password);
    // Persisted retry state is metadata; preserve the runtime verifier unchanged.
    final map = jsonDecode(
      store.values[SecureLockCredentials.policySlot]!,
    ) as Map<String, dynamic>;
    map['attempts'] = 4;
    store.values[SecureLockCredentials.policySlot] = jsonEncode(map);
    await expectLater(
      credentials.authorizePassword(_password()),
      _failure(LockFailure.denied),
    );
    final next = SecureLockCredentials(store, auth, now: () => now);
    await expectLater(
      next.authorizePassword(password),
      _failure(LockFailure.rateLimited),
    );
    now = now.add(const Duration(seconds: 31));
    final grant = await next.authorizePassword(password);
    await next.validate(grant);
    expect(
      jsonDecode(store.values[SecureLockCredentials.policySlot]!)['attempts'],
      0,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
