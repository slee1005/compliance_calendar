import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';

import '../crypto/key_store.dart';
import 'device_authenticator.dart';

/// Value-free lock failures safe for translation in the UI.
enum LockFailure {
  /// OS secure storage is inaccessible.
  storageUnavailable,

  /// A missing/invalid enrolled policy must not become an unlocked app.
  corruptConfiguration,

  /// The operation requires a recent authentication for the same policy.
  authorizationRequired,

  /// A concurrent policy change invalidated this operation.
  configurationChanged,

  /// The supplied password failed the format requirements.
  weakPassword,

  /// Authentication was denied or the password did not match.
  denied,

  /// A native prompt was cancelled.
  cancelled,

  /// Native credentials are not available.
  unavailable,

  /// A bounded retry delay is in force.
  rateLimited,
}

/// Contains no passwords, verifiers, keys, input values or platform messages.
final class LockException implements Exception {
  /// Creates a sanitized lock failure.
  const LockException(this.code);

  /// Reason for the failure.
  final LockFailure code;
  @override
  String toString() => 'LockException(${code.name})';
}

/// Public policy view, excluding its stored password verifier and retry data.
final class LockPolicy {
  /// Unconfigured preview policy. Production data requires enabled=true.
  const LockPolicy.disabled()
    : enabled = false,
      password = false,
      device = false;

  /// Describes configured authentication alternatives.
  const LockPolicy.enabled({required this.password, required this.device})
    : enabled = true;

  /// Whether app launch must authenticate.
  final bool enabled;

  /// An app password was configured.
  final bool password;

  /// OS biometric/device-credential authentication is allowed.
  final bool device;
  @override
  String toString() => 'LockPolicy(enabled: $enabled)';
}

/// One-use, short-lived proof bound to a particular service and policy revision.
abstract interface class LockAuthorization {}

final class _LockAuthorization implements LockAuthorization {
  _LockAuthorization._(
    this._owner,
    this._revision,
    this._issuedAt,
    this._device,
  );
  final Object _owner;
  final String _revision;
  final DateTime _issuedAt;
  final bool _device;
  bool _used = false;
  @override
  String toString() => 'LockAuthorization(redacted)';
}

/// Credential persistence/verification boundary for the lock state machine.
abstract interface class LockCredentials {
  /// Reads current policy; storage/configuration failures must block access.
  Future<LockPolicy> load();

  /// Queries real native enrollment and credential availability.
  Future<DeviceAuthCapabilities> capabilities();

  /// Authenticates the current app password with durable retry throttling.
  Future<LockAuthorization> authorizePassword(String password);

  /// Authenticates native credentials; enrollment is explicit for a new policy.
  Future<LockAuthorization> authorizeDevice({bool enrolling = false});

  /// Revalidates and consumes a one-use proof against the current policy.
  Future<LockPolicy> validate(LockAuthorization authorization);

  /// Sets an initial password; an enabled policy also requires fresh authorization.
  Future<LockPolicy> setPassword(
    String password, {
    bool allowDevice = false,
    LockAuthorization? authorization,
  });

  /// Enables OS-only lock after actual device authentication.
  Future<LockPolicy> enableDevice(LockAuthorization authorization);

  /// Disables protection only after fresh authentication; never deletes keys/cache.
  Future<LockPolicy> disable(LockAuthorization authorization);

  /// Cancels native authentication.
  Future<void> cancel();
}

/// OS-only policy/verifier storage with standard PBKDF2-HMAC-SHA256.
final class SecureLockCredentials implements LockCredentials {
  /// All calls belong to the root isolate, using one account's OS service.
  SecureLockCredentials(this._store, this._auth, {DateTime Function()? now})
    : _now = now ?? _utcNow;
  final KeyStore _store;
  final DeviceAuthenticator _auth;
  final DateTime Function() _now;
  static DateTime _utcNow() => DateTime.now().toUtc();

  /// Scoped OS slot; exposed only for explicit test cleanup/recovery tooling.
  static const policySlot = 'lm.lock.policy.v1';

  /// Sticky enrollment marker; missing policy after enrollment fails closed.
  static const markerSlot = 'lm.lock.enrolled.v1';

  /// Fixed work factor; persisted alternatives cannot reduce this setting.
  static const iterations = 600000;
  static Future<void> _tail = Future.value();

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    final previous = _tail;
    final completed = Completer<void>();
    _tail = completed.future;
    await previous;
    try {
      return await _store.withExclusiveAccess(action);
    } on LockException {
      rethrow;
    } catch (_) {
      throw const LockException(LockFailure.storageUnavailable);
    } finally {
      completed.complete();
    }
  }

  Future<_LockRecord> _read() async {
    final encoded = await _store.read(policySlot);
    final marker = await _store.read(markerSlot);
    if (marker != null && marker != '1') {
      throw const LockException(LockFailure.corruptConfiguration);
    }
    if (encoded == null) {
      if (marker != null) {
        throw const LockException(LockFailure.corruptConfiguration);
      }
      return _LockRecord.initial();
    }
    try {
      return _LockRecord.parse(encoded);
    } catch (_) {
      throw const LockException(LockFailure.corruptConfiguration);
    }
  }

  Future<void> _write(_LockRecord record) async {
    final encoded = record.encode();
    await _store.write(policySlot, encoded);
    if (await _store.read(policySlot) != encoded) {
      throw const LockException(LockFailure.storageUnavailable);
    }
    // Write credentials first: a crash before this marker still leaves a valid
    // enabled policy, never a marker-only unrecoverable enrollment.
    await _store.write(markerSlot, '1');
    if (await _store.read(markerSlot) != '1') {
      throw const LockException(LockFailure.storageUnavailable);
    }
  }

  @override
  Future<LockPolicy> load() => _exclusive(() async => (await _read()).policy);
  @override
  Future<DeviceAuthCapabilities> capabilities() => _auth.capabilities();

  @override
  Future<LockAuthorization> authorizePassword(String password) => _exclusive(
    () async {
      var record = await _read();
      if (!record.policy.password) {
        throw const LockException(LockFailure.authorizationRequired);
      }
      final now = _now();
      if (record.blockedUntil > now.millisecondsSinceEpoch) {
        throw const LockException(LockFailure.rateLimited);
      }
      // Reserve the attempt durably before KDF work, including process crashes.
      record = record.withAttempt(now);
      await _write(record);
      final salt = base64Url.decode(record.salt!);
      final expected = base64Url.decode(record.verifier!);
      List<int>? actual;
      try {
        actual = await _passwordHash(password, salt);
        if (!constantTimeBytesEquality.equals(expected, actual)) {
          throw const LockException(LockFailure.denied);
        }
        await _write(record.clearAttempts());
        return _LockAuthorization._(this, record.revision, _now(), false);
      } finally {
        salt.fillRange(0, salt.length, 0);
        expected.fillRange(0, expected.length, 0);
        actual?.fillRange(0, actual.length, 0);
      }
    },
  );

  @override
  Future<LockAuthorization> authorizeDevice({bool enrolling = false}) async {
    final before = await _exclusive(_read);
    if (!enrolling && (!before.policy.enabled || !before.policy.device)) {
      throw const LockException(LockFailure.unavailable);
    }
    if (!(await _auth.capabilities()).deviceCredential) {
      throw const LockException(LockFailure.unavailable);
    }
    final outcome = await _auth.authenticate();
    if (outcome != DeviceAuthOutcome.success) {
      throw LockException(switch (outcome) {
        DeviceAuthOutcome.cancelled => LockFailure.cancelled,
        DeviceAuthOutcome.unavailable => LockFailure.unavailable,
        DeviceAuthOutcome.lockedOut => LockFailure.rateLimited,
        _ => LockFailure.denied,
      });
    }
    return _exclusive(() async {
      final current = await _read();
      if (current.revision != before.revision) {
        throw const LockException(LockFailure.configurationChanged);
      }
      return _LockAuthorization._(this, current.revision, _now(), true);
    });
  }

  @override
  Future<LockPolicy> validate(LockAuthorization authorization) =>
      _exclusive(() async {
        final current = await _read();
        _require(current, authorization);
        return current.policy;
      });

  void _require(_LockRecord record, LockAuthorization? grant) {
    if (grant is! _LockAuthorization ||
        !identical(grant._owner, this) ||
        grant._used ||
        grant._revision != record.revision ||
        _now().isBefore(grant._issuedAt) ||
        _now().difference(grant._issuedAt) > const Duration(minutes: 2)) {
      throw const LockException(LockFailure.authorizationRequired);
    }
    grant._used = true;
  }

  @override
  Future<LockPolicy> setPassword(
    String password, {
    bool allowDevice = false,
    LockAuthorization? authorization,
  }) async {
    _validatePassword(password);
    if (allowDevice && !(await _auth.capabilities()).deviceCredential) {
      throw const LockException(LockFailure.unavailable);
    }
    return _exclusive(() async {
      final old = await _read();
      if (old.policy.enabled) _require(old, authorization);
      final random = SecretKeyData.random(length: 16);
      final salt = List<int>.of(random.bytes);
      random.destroy();
      List<int>? verifier;
      try {
        verifier = await _passwordHash(password, salt);
        final record = _LockRecord(
          revision: _revision(),
          device: allowDevice,
          salt: base64Url.encode(salt),
          verifier: base64Url.encode(verifier),
        );
        await _write(record);
        return record.policy;
      } finally {
        salt.fillRange(0, salt.length, 0);
        verifier?.fillRange(0, verifier.length, 0);
      }
    });
  }

  @override
  Future<LockPolicy> enableDevice(LockAuthorization authorization) =>
      _exclusive(() async {
        final old = await _read();
        _require(old, authorization);
        if (authorization is! _LockAuthorization || !authorization._device) {
          throw const LockException(LockFailure.authorizationRequired);
        }
        final record = _LockRecord(revision: _revision(), device: true);
        await _write(record);
        return record.policy;
      });
  @override
  Future<LockPolicy> disable(LockAuthorization authorization) =>
      _exclusive(() async {
        final old = await _read();
        _require(old, authorization);
        final record = _LockRecord(revision: _revision(), disabled: true);
        await _write(record);
        return record.policy;
      });
  @override
  Future<void> cancel() => _auth.cancel();

  static String _revision() {
    final random = SecretKeyData.random(length: 16);
    try {
      return base64Url.encode(random.bytes);
    } finally {
      random.destroy();
    }
  }

  static void _validatePassword(String password) {
    if (password.runes.length < 12 ||
        password.runes.length > 128 ||
        utf8.encode(password).length > 512 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(password) ||
        password.runes.any((r) => r >= 0xd800 && r <= 0xdfff) ||
        password.trim().isEmpty) {
      throw const LockException(LockFailure.weakPassword);
    }
  }

  static Future<List<int>> _passwordHash(
    String password,
    List<int> salt,
  ) async {
    if (utf8.encode(password).length > 512) {
      throw const LockException(LockFailure.denied);
    }
    final bytes = utf8.encode(password);
    final copy = List<int>.of(salt);
    try {
      return await Isolate.run(() => _derive((bytes, copy)));
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      copy.fillRange(0, copy.length, 0);
    }
  }

  @override
  String toString() => 'SecureLockCredentials(redacted)';
}

Future<List<int>> _derive((List<int>, List<int>) input) async {
  final (password, salt) = input;
  final secret = SecretKeyData(password, overwriteWhenDestroyed: true);
  try {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: SecureLockCredentials.iterations,
      bits: 256,
    ).deriveKey(secretKey: secret, nonce: salt);
    try {
      return List<int>.of(await key.extractBytes());
    } finally {
      if (key is SecretKeyData) key.destroy();
    }
  } finally {
    secret.destroy();
    password.fillRange(0, password.length, 0);
    salt.fillRange(0, salt.length, 0);
  }
}

final class _LockRecord {
  _LockRecord({
    required this.revision,
    this.device = false,
    this.salt,
    this.verifier,
    this.attempts = 0,
    this.blockedUntil = 0,
    this.disabled = false,
  });
  factory _LockRecord.initial() =>
      _LockRecord(revision: 'initial', disabled: true);
  final String revision;
  final bool device;
  final String? salt;
  final String? verifier;
  final int attempts;
  final int blockedUntil;
  final bool disabled;
  LockPolicy get policy => disabled
      ? const LockPolicy.disabled()
      : LockPolicy.enabled(password: verifier != null, device: device);
  _LockRecord withAttempt(DateTime now) {
    final count = attempts < 1000 ? attempts + 1 : 1000;
    final delay = count < 5 ? 0 : 30 * (1 << (count - 5 > 4 ? 4 : count - 5));
    return _LockRecord(
      revision: revision,
      device: device,
      salt: salt,
      verifier: verifier,
      attempts: count,
      blockedUntil: delay == 0
          ? 0
          : now.add(Duration(seconds: delay)).millisecondsSinceEpoch,
    );
  }

  _LockRecord clearAttempts() => _LockRecord(
    revision: revision,
    device: device,
    salt: salt,
    verifier: verifier,
  );
  String encode() => jsonEncode({
    'v': 1,
    'rev': revision,
    'device': device,
    'disabled': disabled,
    'salt': salt,
    'hash': verifier,
    'iterations': SecureLockCredentials.iterations,
    'attempts': attempts,
    'until': blockedUntil,
  });
  factory _LockRecord.parse(String encoded) {
    if (encoded.length > 2048) throw const FormatException();
    final map = jsonDecode(encoded) as Map;
    if (map.length != 9 ||
        map.keys.any(
          (key) => !const {
            'v',
            'rev',
            'device',
            'disabled',
            'salt',
            'hash',
            'iterations',
            'attempts',
            'until',
          }.contains(key),
        ) ||
        map['v'] != 1 ||
        map['iterations'] != SecureLockCredentials.iterations ||
        map['rev'] is! String ||
        (map['rev'] as String).length != 24 ||
        map['device'] is! bool ||
        map['disabled'] is! bool ||
        map['attempts'] is! int ||
        (map['attempts'] as int) < 0 ||
        (map['attempts'] as int) > 1000 ||
        map['until'] is! int ||
        (map['until'] as int) < 0 ||
        (map['until'] as int) > 8640000000000000) {
      throw const FormatException();
    }
    final salt = map['salt'] as String?;
    final hash = map['hash'] as String?;
    if ((salt == null) != (hash == null) ||
        (salt != null &&
            (base64Url.decode(salt).length != 16 ||
                base64Url.encode(base64Url.decode(salt)) != salt)) ||
        (hash != null &&
            (base64Url.decode(hash).length != 32 ||
                base64Url.encode(base64Url.decode(hash)) != hash)) ||
        (map['disabled'] == false && hash == null && map['device'] == false) ||
        (map['disabled'] == true && (hash != null || map['device'] == true))) {
      throw const FormatException();
    }
    return _LockRecord(
      revision: map['rev'] as String,
      device: map['device'] as bool,
      disabled: map['disabled'] as bool,
      salt: salt,
      verifier: hash,
      attempts: map['attempts'] as int,
      blockedUntil: map['until'] as int,
    );
  }
}
