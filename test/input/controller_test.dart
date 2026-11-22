import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:license_manager/core/ocr/document_input.dart';
import 'package:license_manager/core/ocr/input_controller.dart';

class _Access implements InputAccess {
  bool allowed = true;
  int generation = 0;
  @override
  int acquire() {
    check(generation);
    return generation;
  }

  @override
  void check(int value) {
    if (!allowed || value != generation) {
      throw const InputException(InputFailure.locked);
    }
  }
}

class _File implements DocumentFile {
  bool failRelease = false;
  Completer<EphemeralDocument>? pending;
  final bytes = Uint8List.fromList([37, 80, 68, 70, 45, 1, 2, 3]);
  int reads = 0, releases = 0;
  @override
  Future<EphemeralDocument> read() async {
    reads++;
    return pending?.future ?? EphemeralDocument.encoded(bytes);
  }

  @override
  Future<void> release() async {
    releases++;
    if (failRelease) {
      throw StateError('PRIVATE-RELEASE-DETAIL');
    }
  }
}

class _Camera implements CameraInput {
  int starts = 0, stops = 0;
  Completer<void>? initialization;
  bool failStop = false;
  final buffers = <Uint8List>[];
  @override
  Future<void> start() async {
    starts++;
    await initialization?.future;
  }

  @override
  Future<EphemeralDocument> nextFrame() async {
    final bytes = Uint8List.fromList(List.generate(16, (i) => i + 1));
    buffers.add(bytes);
    return EphemeralDocument.raw(
      format: DocumentFormat.bgra8888,
      width: 2,
      height: 2,
      rotation: 0,
      ownedPlanes: [InputPlane(bytes, rowStride: 8, pixelStride: 4)],
    );
  }

  @override
  Future<void> stop() async {
    stops++;
    if (failStop) throw StateError('PRIVATE-NATIVE-DETAIL');
  }
}

void main() {
  test(
    'source release failure retains no receipt or live document bytes',
    () async {
      final file = _File()..failRelease = true;
      final input = InputController(access: _Access());
      addTearDown(input.dispose);
      await input.readFile(file);
      expect(file.bytes.every((b) => b == 0), isTrue);
      expect(input.failure, InputFailure.io);
      expect(input.receipt, isNull);
    },
  );
  test(
    'no authorization means no file read or camera initialization',
    () async {
      final access = _Access()..allowed = false;
      final camera = _Camera();
      final file = _File();
      final input = InputController(access: access, camera: camera);
      addTearDown(input.dispose);
      await input.startCamera();
      await input.readFile(file);
      expect(camera.starts, 0);
      expect(file.reads, 0);
      expect(file.releases, 1);
      expect(input.failure, InputFailure.locked);
      expect(input.receipt, isNull);
    },
  );
  test(
    '100 synthetic captures wipe every buffer and do not queue images',
    () async {
      final camera = _Camera();
      final input = InputController(access: _Access(), camera: camera);
      addTearDown(input.dispose);
      await input.startCamera();
      for (var i = 0; i < 100; i++) {
        await input.capture();
        expect(input.failure, isNull);
        expect(input.receipt, isNotNull);
        expect(camera.buffers.last.every((b) => b == 0), isTrue);
      }
      expect(camera.buffers.length, 100);
      await input.suspend();
      expect(camera.stops, 1);
      expect(input.receipt, isNull);
    },
  );
  test('consumer exceptions wipe input and release the original without leaking details', () async {
    final file = _File();
    final input = InputController(
      access: _Access(),
      consume: (_) async => throw StateError('PRIVATE-PATH'),
    );
    addTearDown(input.dispose);
    await input.readFile(file);
    expect(file.bytes.every((b) => b == 0), isTrue);
    expect(file.releases, 1);
    expect(input.failure, InputFailure.io);
    expect(input.receipt, isNull);
  });
  test(
    'cancel while reading wipes a late buffer and never creates a receipt',
    () async {
      final file = _File()..pending = Completer<EphemeralDocument>();
      final input = InputController(access: _Access());
      addTearDown(input.dispose);
      final reading = input.readFile(file);
      await Future<void>.delayed(Duration.zero);
      await input.suspend();
      file.pending!.complete(EphemeralDocument.encoded(file.bytes));
      await reading;
      expect(file.bytes.every((b) => b == 0), isTrue);
      expect(file.releases, 1);
      expect(input.receipt, isNull);
    },
  );
  test(
    'authorization change while consuming rejects results and wipes bytes',
    () async {
      final access = _Access();
      final pending = Completer<void>();
      final file = _File();
      final input = InputController(
        access: access,
        consume: (_) => pending.future,
      );
      addTearDown(input.dispose);
      final reading = input.readFile(file);
      await Future<void>.delayed(Duration.zero);
      access.generation++;
      pending.complete();
      await reading;
      expect(file.bytes.every((b) => b == 0), isTrue);
      expect(input.failure, InputFailure.locked);
    },
  );
  test('suspend wipes immediately while consumer remains pending', () async {
    final pending = Completer<void>();
    final file = _File();
    final input = InputController(
      access: _Access(),
      consume: (_) => pending.future,
    );
    addTearDown(input.dispose);
    final reading = input.readFile(file);
    await Future<void>.delayed(Duration.zero);
    await input.suspend();
    expect(file.bytes.every((b) => b == 0), isTrue);
    pending.complete();
    await reading;
    expect(input.receipt, isNull);
  });
  test('second file is rejected and released without reading during active processing', () async {
    final pending = Completer<void>();
    final first = _File(), second = _File();
    final input = InputController(
      access: _Access(),
      consume: (_) => pending.future,
    );
    addTearDown(input.dispose);
    final reading = input.readFile(first);
    await Future<void>.delayed(Duration.zero);
    await expectLater(input.readFile(second), throwsA(isA<InputException>()));
    expect(second.reads, 0);
    expect(second.releases, 1);
    pending.complete();
    await reading;
  });
  test('initialization completing after suspend closes camera instead of starting a session', () async {
    final camera = _Camera()..initialization = Completer<void>();
    final input = InputController(access: _Access(), camera: camera);
    addTearDown(input.dispose);
    final starting = input.startCamera();
    await Future<void>.delayed(Duration.zero);
    await input.suspend();
    camera.initialization!.complete();
    await starting;
    expect(input.live, isFalse);
    expect(camera.stops, greaterThanOrEqualTo(1));
  });
  test(
    'camera shutdown errors remain visibly unavailable, never successful',
    () async {
      final camera = _Camera()..failStop = true;
      final input = InputController(access: _Access(), camera: camera);
      addTearDown(input.dispose);
      await input.startCamera();
      await input.suspend();
      expect(input.phase, InputPhase.failed);
      expect(input.failure, InputFailure.unavailable);
    },
  );
  test('timed-out consumers cannot keep owned bytes beyond ten seconds', () {
    fakeAsync((time) {
      final file = _File();
      final input = InputController(
        access: _Access(),
        consume: (_) => Completer<void>().future,
      );
      unawaited(input.readFile(file));
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 10));
      time.flushMicrotasks();
      expect(file.bytes.every((b) => b == 0), isTrue);
      expect(file.releases, 1);
      expect(input.failure, InputFailure.expired);
      input.dispose();
      time.flushMicrotasks();
    });
  });
}
