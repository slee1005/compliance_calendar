import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/ocr/document_input.dart';
import '../core/security/app_lock_controller.dart';

/// Composition adapter: authorization is always the actual T5 session.
final class LockInputAccess implements InputAccess {
  /// Binds input access to the real T5 session.
  LockInputAccess(this.lock);

  /// Session authority supplied by production composition.
  final AppLockController lock;
  @override
  int acquire() {
    try {
      return lock.requireAuthorization();
    } catch (_) {
      throw const InputException(InputFailure.locked);
    }
  }

  @override
  void check(int generation) {
    try {
      lock.requireAuthorization(generation: generation);
    } catch (_) {
      throw const InputException(InputFailure.locked);
    }
  }
}

/// Official camera stream only. Photo/video/audio/gallery methods are not used.
final class StreamCameraInput implements CameraInput {
  CameraController? _camera;
  Completer<EphemeralDocument>? _pending;
  int _generation = 0;

  /// Builds only the native in-memory camera preview surface.
  Widget preview(BuildContext context) {
    final c = _camera;
    return c != null && c.value.isInitialized
        ? ClipRect(child: CameraPreview(c))
        : const SizedBox.shrink();
  }

  @override
  Future<void> start() async {
    if (_camera != null) throw const InputException(InputFailure.busy);
    final generation = ++_generation;
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (generation != _generation) {
        throw const InputException(InputFailure.cancelled);
      }
      if (cameras.isEmpty) throw const InputException(InputFailure.unavailable);
      final description = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      _camera = controller;
      await controller.initialize();
      if (generation != _generation) {
        throw const InputException(InputFailure.cancelled);
      }
      if (!controller.supportsImageStreaming()) {
        throw const InputException(InputFailure.unavailable);
      }
      final streaming = controller;
      await controller.startImageStream((image) => _frame(image, streaming));
      if (generation != _generation) {
        throw const InputException(InputFailure.cancelled);
      }
    } catch (error) {
      if (identical(_camera, controller)) _camera = null;
      try {
        await controller?.dispose();
      } catch (_) {
        /* value-free failure below */
      }
      if (error is InputException) rethrow;
      throw InputException(
        error is CameraException &&
                const {
                  'CameraAccessDenied',
                  'CameraAccessDeniedWithoutPrompt',
                  'CameraAccessRestricted',
                }.contains(error.code)
            ? InputFailure.permissionDenied
            : InputFailure.unavailable,
      );
    }
  }

  void _frame(CameraImage image, CameraController source) {
    final pending = _pending;
    _pending = null;
    try {
      if (pending == null ||
          pending.isCompleted ||
          !identical(source, _camera)) {
        return;
      }
      final format = switch (image.format.group) {
        ImageFormatGroup.bgra8888 => DocumentFormat.bgra8888,
        ImageFormatGroup.yuv420 => DocumentFormat.yuv420,
        _ => throw const InputException(InputFailure.unsupported),
      };
      final planes = image.planes
          .map(
            (p) => InputPlane(
              Uint8List.fromList(p.bytes),
              rowStride: p.bytesPerRow,
              pixelStride:
                  p.bytesPerPixel ??
                  (format == DocumentFormat.bgra8888 ? 4 : 1),
            ),
          )
          .toList();
      final orientation = switch (source.value.deviceOrientation) {
        DeviceOrientation.portraitUp => 0,
        DeviceOrientation.landscapeLeft => 90,
        DeviceOrientation.portraitDown => 180,
        DeviceOrientation.landscapeRight => 270,
      };
      final rotation =
          (source.description.sensorOrientation +
              (source.description.lensDirection == CameraLensDirection.front
                  ? orientation
                  : -orientation) +
              360) %
          360;
      pending.complete(
        EphemeralDocument.raw(
          format: format,
          width: image.width,
          height: image.height,
          rotation: rotation,
          ownedPlanes: planes,
        ),
      );
    } catch (_) {
      if (pending != null && !pending.isCompleted) {
        pending.completeError(const InputException(InputFailure.invalidData));
      }
    } finally {
      // Includes unrequested frames: no image queue or Dart thumbnail cache.
      for (final p in image.planes) {
        try {
          p.bytes.fillRange(0, p.bytes.length, 0);
        } catch (_) {
          /* plugin-owned immutable buffer is released */
        }
      }
    }
  }

  @override
  Future<EphemeralDocument> nextFrame() async {
    if (_camera == null || !_camera!.value.isStreamingImages) {
      throw const InputException(InputFailure.unavailable);
    }
    if (_pending != null) throw const InputException(InputFailure.busy);
    final pending = Completer<EphemeralDocument>();
    _pending = pending;
    try {
      return await pending.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      throw const InputException(InputFailure.expired);
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const InputException(InputFailure.cancelled));
    }
    final c = _camera;
    _camera = null;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } finally {
      await c.dispose();
    }
  }
}

/// Local desktop files only. Native bridges do not materialize file promises,
/// download URLs, persist bookmarks, or pass filenames/paths to Dart.
final class NativeDesktopInput implements DesktopInput {
  /// Installs one engine-local native file-capability handler.
  NativeDesktopInput() {
    _channel.setMethodCallHandler(_receive);
  }
  static const _channel = MethodChannel('com.smallbizcompliance/input');
  final _drops = StreamController<DocumentFile>.broadcast(sync: true);
  bool _closed = false;
  @override
  Stream<DocumentFile> get drops => _drops.stream;
  Future<void> _receive(MethodCall call) async {
    final token = call.arguments;
    if (call.method != 'drop' || token is! String) return;
    final file = _NativeDocumentFile(token);
    if (_closed || !_drops.hasListener) {
      await file.release();
      return;
    }
    _drops.add(file);
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('enable', enabled);
    } catch (_) {
      throw const InputException(InputFailure.unavailable);
    }
  }

  @override
  Future<DocumentFile?> pick() async {
    try {
      final token = await _channel.invokeMethod<String>('pick');
      return token == null ? null : _NativeDocumentFile(token);
    } on PlatformException catch (_) {
      throw const InputException(InputFailure.io);
    } catch (_) {
      throw const InputException(InputFailure.unavailable);
    }
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    try {
      await setEnabled(false);
    } finally {
      _channel.setMethodCallHandler(null);
      await _drops.close();
    }
  }
}

final class _NativeDocumentFile implements DocumentFile {
  _NativeDocumentFile(this._token);
  final String _token;
  bool _released = false;
  bool _read = false;
  @override
  Future<EphemeralDocument> read() async {
    if (_released || _read) throw const InputException(InputFailure.expired);
    _read = true;
    Uint8List? bytes;
    Uint8List? wire;
    try {
      wire = await NativeDesktopInput._channel.invokeMethod<Uint8List>(
        'read',
        _token,
      );
      if (wire == null) throw const InputException(InputFailure.invalidData);
      if (_released) throw const InputException(InputFailure.cancelled);
      // Native codec views may be immutable. This owner always needs writable
      // bytes so disposal cannot silently leave its input in memory.
      bytes = Uint8List.fromList(wire);
      final document = EphemeralDocument.encoded(bytes);
      bytes = null;
      return document;
    } on PlatformException catch (error) {
      throw InputException(switch (error.code) {
        'too_large' => InputFailure.tooLarge,
        'unsupported' => InputFailure.unsupported,
        'expired' => InputFailure.expired,
        'inactive' => InputFailure.locked,
        _ => InputFailure.io,
      });
    } on InputException {
      rethrow;
    } catch (_) {
      throw const InputException(InputFailure.io);
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      if (wire != null) {
        try {
          wire.fillRange(0, wire.length, 0);
        } on UnsupportedError {
          /* engine-owned immutable view is released */
        }
      }
    }
  }

  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await NativeDesktopInput._channel.invokeMethod<void>('release', _token);
    } catch (_) {
      throw const InputException(InputFailure.io);
    }
  }

  @override
  String toString() => 'DocumentFile(redacted)';
}
