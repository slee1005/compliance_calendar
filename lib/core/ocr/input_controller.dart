import 'dart:async';

import 'package:flutter/foundation.dart';

import 'document_input.dart';

/// T6 validates input and disposes it. It never pretends that OCR succeeded.
enum InputPhase {
  /// No camera or document is active.
  idle,

  /// Camera initialization is awaiting the OS.
  starting,

  /// Camera stream is live, without recording a file.
  live,

  /// One bounded input is being processed.
  reading,

  /// File processing completed and its bytes were wiped.
  disposed,

  /// Input failed without exposing the original error.
  failed,
}

/// Receives input only for the duration of this future; T7 supplies on-device OCR.
typedef DocumentConsumer = Future<void> Function(EphemeralDocument document);

/// Owns a single input, with cancellation and authorization fences around awaits.
final class InputController extends ChangeNotifier {
  /// Creates the single-input owner with explicit authorization.
  InputController({
    required this.access,
    this.camera,
    this.desktop,
    DocumentConsumer? consume,
  }) : _consume = consume ?? _inspect;

  /// Foreground authorization supplied by app composition.
  final InputAccess access;

  /// Mobile stream adapter; null means unavailable.
  final CameraInput? camera;

  /// Desktop read-only selection adapter; null means unavailable.
  final DesktopInput? desktop;
  final DocumentConsumer _consume;
  static Future<void> _inspect(EphemeralDocument document) async {
    document.planes;
  }

  InputPhase _phase = InputPhase.idle;
  InputFailure? _failure;
  InputReceipt? _receipt;

  /// Current input state; only this owner may change it.
  InputPhase get phase => _phase;

  /// Latest sanitized failure, without source identifiers.
  InputFailure? get failure => _failure;

  /// Metadata after the owned document has been wiped.
  InputReceipt? get receipt => _receipt;
  bool _closed = false;
  int _generation = 0;
  EphemeralDocument? _active;
  Future<void> _stopping = Future.value();

  /// Whether initialization or input processing owns the slot.
  bool get busy =>
      _phase == InputPhase.starting || _phase == InputPhase.reading;

  /// Whether the mobile camera is streaming.
  bool get live => _phase == InputPhase.live;

  void _check(int operation, int authorization) {
    if (_closed || operation != _generation) {
      throw const InputException(InputFailure.cancelled);
    }
    access.check(authorization);
  }

  /// Starts only after a foreground authorization check.
  Future<void> startCamera() async {
    if (_closed || busy || live) return;
    final source = camera;
    if (source == null) {
      _fail(InputFailure.unavailable);
      return;
    }
    final operation = ++_generation;
    try {
      final authorization = access.acquire();
      _phase = InputPhase.starting;
      _failure = null;
      _receipt = null;
      _notify();
      await _stopping;
      _check(operation, authorization);
      await source.start();
      _check(operation, authorization);
      _phase = InputPhase.live;
      _notify();
    } catch (error) {
      // Close even a camera whose async initialization finished after cancellation.
      try {
        await source.stop();
      } catch (_) {
        if (!_closed) _fail(InputFailure.unavailable);
        return;
      }
      if (!_closed && operation == _generation) _fail(_safe(error));
    }
  }

  /// Processes and wipes one frame from the running stream.
  Future<void> capture() async {
    if (_closed || !live) return;
    await _run(() => camera!.nextFrame());
  }

  /// Consumes a capability once and releases it on every exit.
  Future<void> readFile(DocumentFile file) async {
    var submitted = false;
    try {
      if (_closed || busy) throw const InputException(InputFailure.busy);
      submitted = true;
      await _run(file.read);
    } finally {
      try {
        await file.release();
      } catch (_) {
        if (submitted && !_closed) {
          _receipt = null;
          _fail(InputFailure.io);
        }
      }
    }
  }

  Future<void> _run(Future<EphemeralDocument> Function() acquire) async {
    final operation = ++_generation;
    final wasLive = live;
    EphemeralDocument? document;
    try {
      final authorization = access.acquire();
      _phase = InputPhase.reading;
      _failure = null;
      _receipt = null;
      _notify();
      document = await acquire();
      _check(operation, authorization);
      _active = document;
      final result = InputReceipt(document.format, document.byteLength);
      await _consume(document).timeout(EphemeralDocument.maxLifetime);
      _check(operation, authorization);
      if (document.isDisposed) throw const InputException(InputFailure.expired);
      document.dispose();
      _receipt = result;
      _phase = wasLive ? InputPhase.live : InputPhase.disposed;
    } catch (error) {
      if (!_closed && operation == _generation) {
        _failure = error is TimeoutException
            ? InputFailure.expired
            : _safe(error);
        _phase = wasLive ? InputPhase.live : InputPhase.failed;
      }
    } finally {
      document?.dispose();
      if (identical(_active, document)) _active = null;
      _notify();
    }
  }

  /// Immediate RAM disposal; camera closure is serialized and awaitable.
  Future<void> suspend() {
    _generation++;
    _active?.dispose();
    _active = null;
    _receipt = null;
    _failure = null;
    _phase = InputPhase.idle;
    _notify();
    _stopping = _stopping.then((_) => camera?.stop()).catchError((Object _) {
      if (!_closed) _fail(InputFailure.unavailable);
    });
    return _stopping;
  }

  void _fail(InputFailure reason) {
    _failure = reason;
    _phase = InputPhase.failed;
    _notify();
  }

  static InputFailure _safe(Object error) =>
      error is InputException ? error.code : InputFailure.io;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    if (_closed) return;
    unawaited(suspend());
    _closed = true;
    super.dispose();
  }
}
