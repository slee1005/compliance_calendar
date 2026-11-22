import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:license_manager/app/document_inputs.dart';
import 'package:license_manager/core/ocr/document_input.dart';
import 'package:license_manager/core/ocr/input_controller.dart';
import 'package:license_manager/core/security/app_lock_controller.dart';
import 'package:license_manager/core/security/privacy_guard.dart';
import 'package:license_manager/features/scan/scan_screen.dart';

import '../support/lock_support.dart';

class _Camera implements CameraInput {
  int starts = 0, stops = 0;
  Uint8List? bytes;
  @override
  Future<void> start() async {
    starts++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<EphemeralDocument> nextFrame() async {
    final b = Uint8List.fromList(List.generate(16, (i) => i + 1));
    bytes = b;
    return EphemeralDocument.raw(
      format: DocumentFormat.bgra8888,
      width: 2,
      height: 2,
      rotation: 0,
      ownedPlanes: [InputPlane(b, rowStride: 8, pixelStride: 4)],
    );
  }
}

class _Desktop implements DesktopInput {
  final events = StreamController<DocumentFile>.broadcast();
  bool enabled = false;
  @override
  Stream<DocumentFile> get drops => events.stream;
  @override
  Future<void> setEnabled(bool value) async {
    enabled = value;
  }

  @override
  Future<DocumentFile?> pick() async => null;
  @override
  Future<void> dispose() async {
    await events.close();
  }
}

void main() {
  Future<(AppLockController, InputController, _Camera, _Desktop)> mount(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    double scale = 1,
    DocumentConsumer? consume,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final lock = AppLockController(
      credentials: TestLockCredentials(),
      privacy: TestPrivacyGuard(),
    );
    await lock.initialize();
    await lock.unlockDevice();
    final camera = _Camera(), desktop = _Desktop();
    final input = InputController(
      access: LockInputAccess(lock),
      camera: camera,
      desktop: desktop,
      consume: consume,
    );
    addTearDown(input.dispose);
    addTearDown(lock.dispose);
    addTearDown(desktop.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ScanScreen(input: input, lock: lock),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (lock, input, camera, desktop);
  }

  testWidgets(
    'camera and drops stay off until explicit consent in an unlocked session',
    (tester) async {
      final (lock, _, camera, desktop) = await mount(tester);
      expect(camera.starts, 0);
      expect(desktop.enabled, isFalse);
      expect(find.byKey(const Key('input-camera-start')), findsNothing);
      await tester.tap(find.byKey(const Key('input-test-consent')));
      await tester.pumpAndSettle();
      expect(desktop.enabled, isTrue);
      await tester.ensureVisible(find.byKey(const Key('input-camera-start')));
      await tester.tap(find.byKey(const Key('input-camera-start')));
      await tester.pumpAndSettle();
      expect(camera.starts, 1);
      lock.lock();
      await tester.pumpAndSettle();
      expect(desktop.enabled, isFalse);
      expect(camera.stops, greaterThan(0));
      expect(find.byKey(const Key('input-capture')), findsNothing);
    },
  );
  testWidgets('backgrounding immediately wipes an in-flight camera input', (
    tester,
  ) async {
    final pending = Completer<void>();
    final (lock, input, camera, _) = await mount(
      tester,
      consume: (_) => pending.future,
    );
    await tester.tap(find.byKey(const Key('input-test-consent')));
    await tester.pumpAndSettle();
    await input.startCamera();
    final capturing = input.capture();
    await tester.pump();
    expect(camera.bytes!.any((b) => b != 0), isTrue);
    lock.visibility(PrivacySignal.inactive);
    await tester.pump();
    expect(camera.bytes!.every((b) => b == 0), isTrue);
    pending.complete();
    await capturing;
    await tester.pumpAndSettle();
    expect(input.receipt, isNull);
  });
  for (final size in const [Size(375, 667), Size(1440, 900)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('input trial fits $size at $scale text', (tester) async {
        final (_, input, _, _) = await mount(tester, size: size, scale: scale);
        await tester.ensureVisible(find.byKey(const Key('input-test-consent')));
        await tester.tap(find.byKey(const Key('input-test-consent')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await input.startCamera();
        await input.capture();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('input-receipt')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
