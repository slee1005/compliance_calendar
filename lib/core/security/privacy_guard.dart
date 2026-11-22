import 'dart:async';

import 'package:flutter/services.dart';

/// Native visibility signals supplement Flutter lifecycle notifications.
enum PrivacySignal {
  /// The native window is active and not being recorded.
  foreground,

  /// Native content is covered while focus is elsewhere.
  inactive,

  /// The app entered background.
  background,

  /// The OS session/device locked or protected data became unavailable.
  locked,
}

/// Actual protection configuration, with screenshot limitations kept explicit.
final class PrivacyCapabilities {
  /// Describes controls that the native runner actually enabled.
  const PrivacyCapabilities({
    required this.nativeCover,
    required this.captureProtection,
    required this.fileProtection,
  });

  /// Synchronous native cover is installed.
  final bool nativeCover;

  /// OS screenshot/capture exclusion was accepted (not a universal guarantee).
  final bool captureProtection;

  /// Native cache-directory file protection was applied.
  final bool fileProtection;
}

/// Native cover boundary. Features never call channels directly.
abstract interface class PrivacyGuard {
  /// Current native focus/device-lock changes.
  Stream<PrivacySignal> get signals;

  /// Configures native protection; throws on a missing/broken bridge.
  Future<PrivacyCapabilities> configure({required bool lockEnabled});

  /// Reveals only after a safe Flutter frame; stale epoch requests are rejected.
  Future<void> reveal();

  /// Immediately requests a cover, retaining it until a safe frame is presented.
  Future<void> cover();

  /// Releases Dart listeners without removing native protection.
  void dispose();
}

/// Runner-owned native cover with an epoch handshake preventing stale reveals.
final class NativePrivacyGuard implements PrivacyGuard {
  /// Each engine owns exactly one instance of this channel client.
  NativePrivacyGuard() {
    _channel.setMethodCallHandler(_receive);
  }
  static const _channel = MethodChannel('com.smallbizcompliance/privacy');
  final _signals = StreamController<PrivacySignal>.broadcast(sync: true);
  int _epoch = -1;
  bool _disposed = false;
  @override
  Stream<PrivacySignal> get signals => _signals.stream;
  Future<void> _receive(MethodCall call) async {
    if (_disposed || call.method != 'visibility' || call.arguments is! Map) {
      return;
    }
    final args = call.arguments as Map;
    final epoch = args['epoch'];
    final state = args['state'];
    if (epoch is! int || epoch < _epoch || state is! String) return;
    _epoch = epoch;
    final signal = switch (state) {
      'foreground' => PrivacySignal.foreground,
      'background' => PrivacySignal.background,
      'locked' => PrivacySignal.locked,
      _ => PrivacySignal.inactive,
    };
    _signals.add(signal);
  }

  @override
  Future<PrivacyCapabilities> configure({required bool lockEnabled}) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'configure',
      {'enabled': lockEnabled},
    );
    if (result == null || result['epoch'] is! int || result['cover'] != true) {
      throw StateError('Native privacy unavailable');
    }
    _epoch = result['epoch'] as int;
    _signals.add(
      result['active'] == true
          ? PrivacySignal.foreground
          : PrivacySignal.inactive,
    );
    return PrivacyCapabilities(
      nativeCover: true,
      captureProtection: result['capture'] == true,
      fileProtection: result['files'] == true,
    );
  }

  @override
  Future<void> reveal() async {
    if (_disposed || _epoch < 0) return;
    final result = await _channel.invokeMapMethod<String, Object?>('reveal', {
      'epoch': _epoch,
    });
    if (result?['epoch'] is int && (result!['epoch'] as int) > _epoch) {
      _epoch = result['epoch'] as int;
      // A focus change raced the rendered frame; await the next native signal.
      _signals.add(
        result['active'] == true
            ? PrivacySignal.foreground
            : PrivacySignal.inactive,
      );
    }
  }

  @override
  Future<void> cover() async {
    if (_disposed) return;
    final result = await _channel.invokeMapMethod<String, Object?>('cover');
    if (result?['epoch'] is int) _epoch = result!['epoch'] as int;
  }

  @override
  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    unawaited(_signals.close());
  }
}
