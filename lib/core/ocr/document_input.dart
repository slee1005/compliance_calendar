import 'dart:async';
import 'dart:typed_data';

/// Value-free input errors; never attach a filename, path, bytes or OS message.
enum InputFailure {
  /// The device or input adapter cannot provide this source.
  unavailable,

  /// Camera access was denied or restricted by the OS.
  permissionDenied,

  /// The operation was cancelled or superseded.
  cancelled,

  /// The foreground authenticated session is missing or stale.
  locked,

  /// Another input already owns the processing slot.
  busy,

  /// The source exceeds the bounded memory size.
  tooLarge,

  /// The source kind or local file policy is unsupported.
  unsupported,

  /// The buffer or plane metadata is invalid.
  invalidData,

  /// The source or its memory lease expired.
  expired,

  /// A value-free native I/O failure.
  io,
}

/// Sanitized failure crossing the input boundary.
final class InputException implements Exception {
  /// Creates an error containing only its public reason.
  const InputException(this.code);

  /// Safe reason suitable for UI mapping.
  final InputFailure code;
  @override
  String toString() => 'InputException(${code.name})';
}

/// Encoded files or raw camera planes; no document is serialized for storage.
enum DocumentFormat {
  /// PNG signature; decoding belongs to T7.
  png,

  /// JPEG signature; decoding belongs to T7.
  jpeg,

  /// HEIF/HEIC container signature; decoding belongs to T7.
  heic,

  /// PDF header; page rendering belongs to T7.
  pdf,

  /// Three stride-aware YUV 4:2:0 planes.
  yuv420,

  /// One blue/green/red/alpha plane.
  bgra8888,
}

/// Stride information required by the next on-device OCR milestone.
final class InputPlane {
  /// Adopts a mutable plane; the document owner must wipe it.
  InputPlane(this.bytes, {required this.rowStride, required this.pixelStride});

  /// Owned bytes; aliases must not outlive the processing callback.
  final Uint8List bytes;

  /// Bytes between consecutive rows.
  final int rowStride;

  /// Bytes between consecutive pixel starts.
  final int pixelStride;
  @override
  String toString() => 'InputPlane(redacted)';
}

/// One owned, bounded, short-lived input. Adoption transfers buffer ownership.
/// Consumers must not retain copies. All owned bytes are zeroed on every exit.
final class EphemeralDocument {
  EphemeralDocument._(
    this.format,
    List<InputPlane> planes,
    this.width,
    this.height,
    this.rotation,
  ) : _planes = List.unmodifiable(planes) {
    _expiry = Timer(maxLifetime, dispose);
  }

  /// Maximum encoded file or total raw-plane size in memory.
  static const maxBytes = 20 * 1024 * 1024;

  /// Largest accepted raw camera dimension.
  static const maxDimension = 4096;

  /// Absolute maximum lifetime of adopted bytes.
  static const maxLifetime = Duration(seconds: 10);

  /// Signature/raw format only, not proof of successful decoding.
  final DocumentFormat format;

  /// Raw width; encoded dimensions are intentionally not decoded in T6.
  final int? width;

  /// Raw height; encoded dimensions are intentionally not decoded in T6.
  final int? height;

  /// Clockwise input rotation in degrees for the on-device consumer.
  final int rotation;
  final List<InputPlane> _planes;
  Timer? _expiry;
  bool _disposed = false;

  /// Whether this owner has zeroed its bytes.
  bool get isDisposed => _disposed;

  /// Borrowed planes; throws after cancellation/disposal/expiry.
  List<InputPlane> get planes {
    if (_disposed) throw const InputException(InputFailure.expired);
    return _planes;
  }

  /// Total owned byte count while the lease is live.
  int get byteLength =>
      planes.fold(0, (sum, plane) => sum + plane.bytes.length);

  /// Performs bounded signature identification, not an image/PDF decode or OCR.
  static EphemeralDocument encoded(Uint8List ownedBytes) {
    try {
      if (ownedBytes.isEmpty) {
        throw const InputException(InputFailure.invalidData);
      }
      if (ownedBytes.length > maxBytes) {
        throw const InputException(InputFailure.tooLarge);
      }
      bool starts(List<int> prefix, [int offset = 0]) =>
          ownedBytes.length >= offset + prefix.length &&
          List.generate(
            prefix.length,
            (i) => ownedBytes[offset + i] == prefix[i],
          ).every((v) => v);
      final format = starts([137, 80, 78, 71, 13, 10, 26, 10])
          ? DocumentFormat.png
          : starts([255, 216, 255])
          ? DocumentFormat.jpeg
          : starts([37, 80, 68, 70, 45])
          ? DocumentFormat.pdf
          : starts([102, 116, 121, 112], 4) &&
                [
                  'heic',
                  'heix',
                  'hevc',
                  'hevx',
                  'mif1',
                ].any((brand) => starts(brand.codeUnits, 8))
          ? DocumentFormat.heic
          : null;
      if (format == null) throw const InputException(InputFailure.unsupported);
      return EphemeralDocument._(
        format,
        [InputPlane(ownedBytes, rowStride: 0, pixelStride: 0)],
        null,
        null,
        0,
      );
    } catch (_) {
      ownedBytes.fillRange(0, ownedBytes.length, 0);
      rethrow;
    }
  }

  /// Validates actual last-pixel bounds, including padded camera row strides.
  static EphemeralDocument raw({
    required DocumentFormat format,
    required int width,
    required int height,
    required int rotation,
    required List<InputPlane> ownedPlanes,
  }) {
    try {
      if (width < 1 ||
          height < 1 ||
          width > maxDimension ||
          height > maxDimension ||
          ![0, 90, 180, 270].contains(rotation) ||
          (format != DocumentFormat.yuv420 &&
              format != DocumentFormat.bgra8888) ||
          ownedPlanes.length != (format == DocumentFormat.yuv420 ? 3 : 1)) {
        throw const InputException(InputFailure.invalidData);
      }
      if (ownedPlanes.fold<int>(0, (n, p) => n + p.bytes.length) > maxBytes) {
        throw const InputException(InputFailure.tooLarge);
      }
      for (var i = 0; i < ownedPlanes.length; i++) {
        final p = ownedPlanes[i];
        final w = i == 0 ? width : (width + 1) ~/ 2;
        final h = i == 0 ? height : (height + 1) ~/ 2;
        final pixelBytes = format == DocumentFormat.bgra8888 ? 4 : 1;
        if (p.pixelStride < pixelBytes ||
            p.pixelStride > 4 ||
            p.rowStride < (w - 1) * p.pixelStride + pixelBytes ||
            p.bytes.length <
                (h - 1) * p.rowStride + (w - 1) * p.pixelStride + pixelBytes) {
          throw const InputException(InputFailure.invalidData);
        }
      }
      return EphemeralDocument._(format, ownedPlanes, width, height, rotation);
    } catch (_) {
      for (final p in ownedPlanes) {
        p.bytes.fillRange(0, p.bytes.length, 0);
      }
      rethrow;
    }
  }

  /// Cancels the lease and synchronously wipes every owned plane.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _expiry?.cancel();
    for (final p in _planes) {
      p.bytes.fillRange(0, p.bytes.length, 0);
    }
  }

  @override
  String toString() => 'EphemeralDocument(redacted)';
}

/// An OS-selected read-only file capability, never a persisted source path.
abstract interface class DocumentFile {
  /// Reads once into bounded memory; no new document file may be written.
  Future<EphemeralDocument> read();

  /// Releases an OS source capability; never deletes the user original.
  Future<void> release();
}

/// Mobile camera boundary. No takePicture, video or gallery API is exposed.
abstract interface class CameraInput {
  /// Starts a live camera stream without recording audio or files.
  Future<void> start();

  /// Returns the next owned frame; implementations must not queue images.
  Future<EphemeralDocument> nextFrame();

  /// Cancels pending frames and closes the live camera.
  Future<void> stop();
}

/// Desktop OS selection/drop boundary. Sources expire and are explicitly released.
abstract interface class DesktopInput {
  /// Unread, short-lived capabilities from explicit local OS drops.
  Stream<DocumentFile> get drops;

  /// Enables selection/drop only while the input route has consent.
  Future<void> setEnabled(bool enabled);

  /// Shows a native read-only selector; null means cancellation.
  Future<DocumentFile?> pick();

  /// Disables input and releases native listeners/capabilities.
  Future<void> dispose();
}

/// Implemented by composition using the T5 session authority.
abstract interface class InputAccess {
  /// Obtains the current foreground authorization generation.
  int acquire();

  /// Rejects results after authorization or generation changes.
  void check(int generation);
}

/// Receipt contains only format and byte count after disposal, never OCR output.
final class InputReceipt {
  /// Creates value-free metadata after successful disposal.
  const InputReceipt(this.format, this.byteCount);

  /// Signature/raw format only, not proof of successful decoding.
  final DocumentFormat format;

  /// Byte count of the disposed input, without document content.
  final int byteCount;
}
