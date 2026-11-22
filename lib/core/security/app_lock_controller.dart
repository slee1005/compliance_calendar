import 'dart:async';

import 'package:flutter/foundation.dart';

import 'device_authenticator.dart';
import 'lock_credentials.dart';
import 'privacy_guard.dart';

/// Authorization states; only preview/unlocked may display application content.
enum LockPhase {
  /// Reading OS policy; protected content is never shown yet.
  loading,

  /// No lock configured, suitable only for the opt-in fictional preview.
  preview,

  /// Authentication is required.
  locked,

  /// A native/KDF authentication attempt is running.
  authenticating,

  /// The current foreground session is authenticated.
  unlocked,

  /// A policy/storage/native failure blocked access.
  blocked,
}

/// Wall time and monotonic time are both checked to fail closed on clock rollback.
abstract interface class LockClock {
  /// UTC wall clock, never persisted as an unlocked-session flag.
  DateTime get now;

  /// Monotonic process duration.
  Duration get elapsed;
}

/// Real process clock; sessions are never restored after process restart.
final class SystemLockClock implements LockClock {
  /// Starts a monotonic stopwatch for this process owner.
  SystemLockClock() {
    _watch.start();
  }
  final Stopwatch _watch = Stopwatch();
  @override
  DateTime get now => DateTime.now().toUtc();
  @override
  Duration get elapsed => _watch.elapsed;
}

/// Root-isolate session authority, independent of all platform APIs and UI.
final class AppLockController extends ChangeNotifier {
  /// onLock must close registered protected DB handles/clear decrypted UI state.
  /// Current preview has no production data handles; future composition supplies it.
  AppLockController({
    required this.credentials,
    required this.privacy,
    LockClock? clock,
    this.onLock,
  }) : _clock = clock ?? SystemLockClock() {
    _nativeSubscription = privacy.signals.listen(_nativeVisibility);
  }

  /// Secure credential service.
  final LockCredentials credentials;

  /// Native cover service, never selected by feature widgets.
  final PrivacyGuard privacy;
  final LockClock _clock;

  /// Closes protected data handles and clears decrypted application state.
  final Future<void> Function()? onLock;
  late final StreamSubscription<PrivacySignal> _nativeSubscription;
  LockPolicy _policy = const LockPolicy.disabled();
  LockPhase _phase = LockPhase.loading;
  DeviceAuthCapabilities _capabilities = const DeviceAuthCapabilities(
    deviceCredential: false,
    biometrics: false,
  );
  PrivacyCapabilities? _protection;
  LockFailure? _failure;
  bool _visible = true;
  bool _nativeVisible = true;
  bool _lifecycleVisible = true;
  bool _busy = false;
  bool _disposed = false;
  bool _pendingUnlock = false;
  int _generation = 0;
  DateTime? _awayWall;
  Duration? _awayTick;
  Timer? _timer;
  Future<void>? _initializing;
  Future<void>? _securing;

  /// Fixed planner timeout; not relaxed by feature code.
  static const backgroundTimeout = Duration(minutes: 5);

  /// Current policy, without secrets.
  LockPolicy get policy => _policy;

  /// Current authorization state.
  LockPhase get phase => _phase;

  /// OS support/enrollment, never inferred from a mock success.
  DeviceAuthCapabilities get capabilities => _capabilities;

  /// Native protection settings that actually succeeded.
  PrivacyCapabilities? get protection => _protection;

  /// Value-free latest failure.
  LockFailure? get failure => _failure;

  /// Whether an async authentication/configuration operation is running.
  bool get busy => _busy;

  /// Whether the app is foregrounded and not covered by OS capture/lock signals.
  bool get visible => _visible;

  /// Only these states may mount the protected application tree.
  bool get canShowContent =>
      _visible && (_phase == LockPhase.preview || _phase == LockPhase.unlocked);

  /// Only enabled/authenticated sessions may access future production data.
  bool get authorized =>
      _visible && _policy.enabled && _phase == LockPhase.unlocked;

  /// Reads policy before showing content. A missing bridge never means unlocked.
  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      _protection = await privacy.configure(lockEnabled: true);
      _policy = await credentials.load();
      _capabilities = await credentials.capabilities();
      _protection = await privacy.configure(lockEnabled: _policy.enabled);
      if (_disposed) return;
      _phase = _policy.enabled ? LockPhase.locked : LockPhase.preview;
      _failure = null;
    } catch (error) {
      if (_disposed) return;
      _phase = LockPhase.blocked;
      _failure = _safeFailure(error);
    }
    _notify();
  }

  /// Rechecks policy after a storage failure; never deletes/reset credentials.
  Future<void> retry() async {
    if (_busy) return;
    _phase = LockPhase.loading;
    _notify();
    _initializing = null;
    await initialize();
  }

  /// Immediately hides on focus loss and checks the exact five-minute boundary.
  void visibility(PrivacySignal signal) {
    _lifecycleVisible = signal == PrivacySignal.foreground;
    _applyVisibility(signal);
  }

  void _nativeVisibility(PrivacySignal signal) {
    _nativeVisible = signal == PrivacySignal.foreground;
    _applyVisibility(signal);
  }

  void _applyVisibility(PrivacySignal signal) {
    if (_disposed) return;
    if (signal == PrivacySignal.locked) {
      _visible = false;
      _beginAbsence();
      lock();
      return;
    }
    if (!_nativeVisible || !_lifecycleVisible) {
      _visible = false;
      _beginAbsence();
      _notify();
      return;
    }
    final expired = _expired();
    _visible = true;
    _timer?.cancel();
    _timer = null;
    _awayWall = null;
    _awayTick = null;
    if (expired && (_policy.enabled || _busy)) {
      lock();
    } else if (_pendingUnlock &&
        _policy.enabled &&
        _phase != LockPhase.blocked) {
      _pendingUnlock = false;
      _phase = LockPhase.unlocked;
    }
    _notify();
  }

  void _beginAbsence() {
    _awayWall ??= _clock.now;
    _awayTick ??= _clock.elapsed;
    _timer ??= Timer(backgroundTimeout, () {
      _timer = null;
      if (!_visible && (_policy.enabled || _busy)) lock();
    });
  }

  bool _expired() {
    if (_awayWall == null || _awayTick == null) return false;
    return _clock.now.isBefore(_awayWall!) ||
        _clock.now.difference(_awayWall!) >= backgroundTimeout ||
        _clock.elapsed - _awayTick! >= backgroundTimeout;
  }

  /// Locks immediately and invalidates any delayed authentication result.
  void lock() {
    if (_disposed) return;
    _generation++;
    _pendingUnlock = false;
    if (_policy.enabled) _phase = LockPhase.locked;
    _notify();
    unawaited(credentials.cancel());
    _securing = (_securing ?? Future<void>.value()).then((_) async {
      try {
        await privacy.cover();
        await onLock?.call();
      } catch (_) {
        if (!_disposed) {
          _phase = LockPhase.blocked;
          _failure = LockFailure.storageUnavailable;
          _notify();
        }
      }
    });
  }

  /// Rejects protected access outside the current authenticated generation.
  /// After async work, callers must call this again before using its result.
  int requireAuthorization({int? generation}) {
    if (!authorized || (generation != null && generation != _generation)) {
      throw const LockException(LockFailure.authorizationRequired);
    }
    return _generation;
  }

  /// Native authentication includes device PIN/passcode fallback.
  Future<bool> unlockDevice() =>
      _authenticate(() => credentials.authorizeDevice());

  /// Uses the actual stored verifier; no device authentication is simulated.
  Future<bool> unlockPassword(String password) =>
      _authenticate(() => credentials.authorizePassword(password));
  Future<bool> _authenticate(
    Future<LockAuthorization> Function() authenticate,
  ) async {
    if (_busy || !_visible || !_policy.enabled || _phase == LockPhase.blocked) {
      return false;
    }
    final generation = _generation;
    _busy = true;
    _phase = LockPhase.authenticating;
    _failure = null;
    _notify();
    try {
      final grant = await authenticate();
      await _securing;
      if (_disposed ||
          generation != _generation ||
          _expired() ||
          _phase == LockPhase.blocked) {
        return false;
      }
      final current = await credentials.validate(grant);
      if (_disposed ||
          generation != _generation ||
          _expired() ||
          _phase == LockPhase.blocked) {
        return false;
      }
      if (!current.enabled) {
        throw const LockException(LockFailure.configurationChanged);
      }
      _policy = current;
      if (_visible) {
        _phase = LockPhase.unlocked;
      } else {
        _pendingUnlock = true;
        _phase = LockPhase.locked;
      }
      return true;
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _failure = _safeFailure(error);
        _phase = LockPhase.locked;
      }
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        if (_phase == LockPhase.authenticating) _phase = LockPhase.locked;
        _notify();
      }
    }
  }

  /// Initial password enrollment. Existing protection must be disabled with reauth first.
  Future<bool> enablePassword(String password, {bool allowDevice = false}) =>
      _configure(
        () => credentials.setPassword(password, allowDevice: allowDevice),
      );

  /// OS-only enrollment is committed only after actual native authentication.
  Future<bool> enableDevice() => _configure(() async {
    final grant = await credentials.authorizeDevice(enrolling: true);
    return credentials.enableDevice(grant);
  });
  Future<bool> _configure(Future<LockPolicy> Function() configure) async {
    if (_busy || !_visible || _policy.enabled || _phase != LockPhase.preview) {
      return false;
    }
    final generation = _generation;
    _busy = true;
    _failure = null;
    _notify();
    try {
      _policy = await configure();
      _protection = await privacy.configure(lockEnabled: _policy.enabled);
      if (_disposed) return false;
      final stale =
          generation != _generation ||
          _expired() ||
          _phase == LockPhase.blocked;
      _generation++;
      _pendingUnlock = false;
      if (stale) {
        _phase = LockPhase.locked;
      } else if (_visible) {
        _phase = LockPhase.unlocked;
      } else {
        _phase = LockPhase.locked;
        _pendingUnlock = true;
      }
      return true;
    } catch (error) {
      if (!_disposed) {
        _failure = _safeFailure(error);
        // An interrupted credential write may have committed. Never restore
        // preview based on an uncertain outcome; reload from a blocked gate.
        if (_failure == LockFailure.weakPassword ||
            _failure == LockFailure.cancelled ||
            _failure == LockFailure.unavailable ||
            _failure == LockFailure.denied) {
          _phase = _policy.enabled ? LockPhase.locked : LockPhase.preview;
        } else {
          _phase = LockPhase.blocked;
        }
      }
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  /// Requires a fresh device-owner check even for an already-unlocked session.
  Future<bool> disableDevice() => _disable(() => credentials.authorizeDevice());

  /// Requires the current password again before disabling protection.
  Future<bool> disablePassword(String password) =>
      _disable(() => credentials.authorizePassword(password));
  Future<bool> _disable(Future<LockAuthorization> Function() authorize) async {
    if (_busy || !authorized) return false;
    final generation = _generation;
    _busy = true;
    _failure = null;
    _notify();
    var changing = false;
    try {
      final grant = await authorize();
      if (_disposed ||
          generation != _generation ||
          _expired() ||
          _phase == LockPhase.blocked) {
        return false;
      }
      changing = true;
      _policy = await credentials.disable(grant);
      _generation++;
      _pendingUnlock = false;
      await privacy.cover();
      await _securing;
      await onLock?.call();
      if (_disposed) return false;
      if (_generation != generation + 1 ||
          _expired() ||
          _phase == LockPhase.blocked) {
        throw const LockException(LockFailure.configurationChanged);
      }
      _protection = await privacy.configure(lockEnabled: false);
      if (_disposed) return false;
      if (_generation != generation + 1 || _phase == LockPhase.blocked) {
        throw const LockException(LockFailure.configurationChanged);
      }
      _phase = LockPhase.preview;
      return true;
    } catch (error) {
      if (!_disposed) {
        _failure = _safeFailure(error);
        if (changing) _phase = LockPhase.blocked;
      }
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  /// Called only after the lock/loading/content frame has been painted safely.
  Future<void> revealFrame() async {
    if (_disposed || !_visible) return;
    try {
      await _securing;
      if (_visible && !_disposed) await privacy.reveal();
    } catch (_) {
      if (!_disposed) {
        final changed =
            _phase != LockPhase.blocked ||
            _failure != LockFailure.storageUnavailable;
        _phase = LockPhase.blocked;
        _failure = LockFailure.storageUnavailable;
        if (changed) _notify();
      }
    }
  }

  static LockFailure _safeFailure(Object error) =>
      error is LockException ? error.code : LockFailure.storageUnavailable;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    unawaited(_nativeSubscription.cancel());
    unawaited(credentials.cancel());
    privacy.dispose();
    super.dispose();
  }
}
