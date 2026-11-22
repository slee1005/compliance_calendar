import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:license_manager/core/ocr/document_input.dart';

void main() {
  test('encoded signatures are identified without decoding or persisting the document', () {
    final samples = <DocumentFormat, List<int>>{
      DocumentFormat.png: [137, 80, 78, 71, 13, 10, 26, 10],
      DocumentFormat.jpeg: [255, 216, 255],
      DocumentFormat.pdf: [37, 80, 68, 70, 45],
      DocumentFormat.heic: [0, 0, 0, 16, 102, 116, 121, 112, 104, 101, 105, 99],
    };
    for (final sample in samples.entries) {
      final bytes = Uint8List.fromList(sample.value);
      final document = EphemeralDocument.encoded(bytes);
      expect(document.format, sample.key);
      expect(document.toString(), 'EphemeralDocument(redacted)');
      document.dispose();
      document.dispose();
      expect(bytes.every((b) => b == 0), isTrue);
      expect(() => document.planes, throwsA(isA<InputException>()));
    }
  });
  test('rejected encoded inputs are wiped, including oversize buffers', () {
    for (final bytes in [
      Uint8List(0),
      Uint8List.fromList([1, 2, 3]),
      Uint8List(EphemeralDocument.maxBytes + 1)..[0] = 137,
    ]) {
      expect(
        () => EphemeralDocument.encoded(bytes),
        throwsA(isA<InputException>()),
      );
      expect(bytes.every((b) => b == 0), isTrue);
    }
  });
  test('raw planes accept padded strides and reject last-pixel truncation', () {
    final planes = [
      InputPlane(
        Uint8List(20)..fillRange(0, 20, 1),
        rowStride: 8,
        pixelStride: 1,
      ),
      InputPlane(
        Uint8List(3)..fillRange(0, 3, 2),
        rowStride: 4,
        pixelStride: 2,
      ),
      InputPlane(
        Uint8List(3)..fillRange(0, 3, 3),
        rowStride: 4,
        pixelStride: 2,
      ),
    ];
    final frame = EphemeralDocument.raw(
      format: DocumentFormat.yuv420,
      width: 4,
      height: 3,
      rotation: 90,
      ownedPlanes: [
        planes[0],
        InputPlane(
          Uint8List(7)..fillRange(0, 7, 2),
          rowStride: 4,
          pixelStride: 2,
        ),
        InputPlane(
          Uint8List(7)..fillRange(0, 7, 3),
          rowStride: 4,
          pixelStride: 2,
        ),
      ],
    );
    expect(frame.width, 4);
    expect(frame.rotation, 90);
    frame.dispose();
    expect(planes[0].bytes.every((b) => b == 0), isTrue);
    expect(
      () => EphemeralDocument.raw(
        format: DocumentFormat.yuv420,
        width: 4,
        height: 3,
        rotation: 90,
        ownedPlanes: planes,
      ),
      throwsA(isA<InputException>()),
    );
    expect(planes.every((p) => p.bytes.every((b) => b == 0)), isTrue);
  });
  test(
    'invalid dimensions, plane counts and rotations always wipe ownership',
    () {
      for (final value in [0, 4097]) {
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        expect(
          () => EphemeralDocument.raw(
            format: DocumentFormat.bgra8888,
            width: value,
            height: 1,
            rotation: 0,
            ownedPlanes: [InputPlane(bytes, rowStride: 4, pixelStride: 4)],
          ),
          throwsA(isA<InputException>()),
        );
        expect(bytes.every((b) => b == 0), isTrue);
      }
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      expect(
        () => EphemeralDocument.raw(
          format: DocumentFormat.bgra8888,
          width: 1,
          height: 1,
          rotation: 45,
          ownedPlanes: [InputPlane(bytes, rowStride: 4, pixelStride: 4)],
        ),
        throwsA(isA<InputException>()),
      );
      expect(bytes.every((b) => b == 0), isTrue);
    },
  );
  test(
    'absolute ten-second lease wipes even a consumer that never returns',
    () {
      fakeAsync((time) {
        final bytes = Uint8List.fromList([37, 80, 68, 70, 45]);
        final frame = EphemeralDocument.encoded(bytes);
        time.elapse(const Duration(seconds: 9));
        expect(frame.isDisposed, isFalse);
        time.elapse(const Duration(seconds: 1));
        expect(frame.isDisposed, isTrue);
        expect(bytes.every((b) => b == 0), isTrue);
      });
    },
  );
}
