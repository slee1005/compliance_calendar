import 'dart:async' show Completer;
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:license_manager/app/app.dart';
import 'package:license_manager/app/app_controller.dart';
import 'package:license_manager/app/document_inputs.dart';
import 'package:license_manager/app/router.dart';
import 'package:license_manager/core/crypto/os_key_store.dart';
import 'package:license_manager/core/ocr/document_input.dart';
import 'package:license_manager/core/ocr/input_controller.dart';
import 'package:license_manager/core/security/app_lock_controller.dart';
import 'package:license_manager/core/security/lock_credentials.dart';
import 'package:license_manager/core/security/os_device_authenticator.dart';
import 'package:license_manager/core/security/privacy_guard.dart';

const _privacy = MethodChannel('com.smallbizcompliance/privacy');
const _files = MethodChannel('com.smallbizcompliance/input');
Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < const Duration(seconds: 60)) {
    var active = true;
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      final status = await _privacy.invokeMapMethod<String, Object?>(
        'activateTestWindow',
      );
      active = status?['active'] == true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await tester.pump();
    if (active && ready()) {
      await tester.pumpAndSettle();
      if (ready()) return;
    }
  }
  fail('Native input condition timed out.');
}

class _MemoryFile implements DocumentFile {
  // Format header and non-identifying synthetic bytes exist only in RAM.
  final bytes = Uint8List.fromList([
    37,
    80,
    68,
    70,
    45,
    ...List.generate(32, (i) => i + 1),
  ]);
  bool released = false;
  @override
  Future<EphemeralDocument> read() async => EphemeralDocument.encoded(bytes);
  @override
  Future<void> release() async {
    released = true;
  }
}

Future<int> _documentsOnDisk() async {
  final temporary = await getTemporaryDirectory();
  // Windows GetTempPath is shared with other applications. Do not inspect
  // unrelated user files; no T6 adapter creates files in this reserved subtree.
  final ownedTemporary = defaultTargetPlatform == TargetPlatform.windows
      ? Directory.fromUri(
          temporary.uri.resolve('com.smallbizcompliance.input/'),
        )
      : temporary;
  final directories = [
    ownedTemporary,
    await getApplicationCacheDirectory(),
    Directory.fromUri(
      (await getApplicationSupportDirectory()).uri.resolve('cache/'),
    ),
  ];
  final seen = <String>{};
  var count = 0;
  for (final directory in directories) {
    if (!await directory.exists()) continue;
    await for (final entry in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is! File || !seen.add(entry.path)) continue;
      final extension = entry.path.toLowerCase().split('.').last;
      var document = const {
        'png',
        'jpg',
        'jpeg',
        'heic',
        'heif',
        'pdf',
        'webp',
        'bmp',
        'tiff',
        'tif',
      }.contains(extension);
      final handle = await entry.open();
      try {
        final header = await handle.read(12);
        if (header.length >= 5) {
          document =
              document ||
              (header[0] == 137 &&
                  header[1] == 80 &&
                  header[2] == 78 &&
                  header[3] == 71) ||
              (header[0] == 255 && header[1] == 216 && header[2] == 255) ||
              (header[0] == 37 &&
                  header[1] == 80 &&
                  header[2] == 68 &&
                  header[3] == 70 &&
                  header[4] == 45) ||
              (header.length >= 12 &&
                  header[4] == 102 &&
                  header[5] == 116 &&
                  header[6] == 121 &&
                  header[7] == 112);
        }
      } finally {
        await handle.close();
      }
      if (document) count++;
    }
  }
  return count;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    '100 inputs leave zero document files and wipe owned bytes',
    (tester) async {
      addTearDown(tester.platformDispatcher.clearSemanticsEnabledTestValue);
      final store = OsKeyStore(
        service:
            'com.smallbizcompliance.t6.${DateTime.now().microsecondsSinceEpoch}',
      );
      final desktop =
          const {
            TargetPlatform.macOS,
            TargetPlatform.windows,
          }.contains(defaultTargetPlatform)
          ? NativeDesktopInput()
          : null;
      final camera = desktop == null ? StreamCameraInput() : null;
      late InputController input;
      final lock = AppLockController(
        credentials: SecureLockCredentials(store, OsDeviceAuthenticator()),
        privacy: NativePrivacyGuard(),
        onLock: () async {
          await desktop?.setEnabled(false);
          await input.suspend();
        },
      );
      var nativeFrames = 0;
      var lastOwned = <Uint8List>[];
      input = InputController(
        access: LockInputAccess(lock),
        camera: camera,
        desktop: desktop,
        consume: (document) async {
          final owned = document.planes.map((p) => p.bytes).toList();
          lastOwned = owned;
          expect(owned.any((bytes) => bytes.any((b) => b != 0)), isTrue);
        },
      );
      final app = AppController()
        ..start(example: true)
        ..navigate(AppDestination.scan);
      final random = SecretKeyData.random(length: 24);
      final password = base64Url.encode(random.bytes);
      random.destroy();
      var memoryCount = 0, dropCount = 0;
      var nativeMouseDropVerified = false;
      var nativeCameraAvailable = false;
      try {
        expect(
          await _documentsOnDisk(),
          0,
          reason: 'Document files already exist in app-owned temporary/cache directories.',
        );
        await tester.pumpWidget(
          ComplianceApp(
            controller: app,
            lockController: lock,
            inputController: input,
            cameraPreview: camera?.preview,
          ),
        );
        await _wait(tester, () => lock.canShowContent);
        expect(await lock.enablePassword(password), isTrue);
        await _wait(tester, () => lock.authorized);
        final consent = find.byKey(const Key('input-test-consent'));
        await tester.ensureVisible(consent);
        await tester.tap(consent);
        await tester.pumpAndSettle();
        for (var i = 0; i < 100; i++) {
          final file = _MemoryFile();
          await input.readFile(file);
          expect(file.released, isTrue);
          expect(file.bytes.every((b) => b == 0), isTrue);
          expect(input.failure, isNull);
          expect(lastOwned.every((b) => b.every((v) => v == 0)), isTrue);
          memoryCount++;
        }
        if (camera != null) {
          await _wait(tester, () => lock.authorized);
          await input.startCamera();
          nativeCameraAvailable = input.live;
          if (defaultTargetPlatform == TargetPlatform.android) {
            expect(
              input.live,
              isTrue,
              reason: 'Grant CAMERA only on the disposable emulator before this test.',
            );
          }
          if (input.live) {
            for (var i = 0; i < 100; i++) {
              await input.capture();
              expect(input.failure, isNull);
              expect(input.receipt, isNotNull);
              expect(lastOwned.every((b) => b.every((v) => v == 0)), isTrue);
              nativeFrames++;
              if (i % 10 == 0) await tester.pump();
            }
          } else {
            expect(input.failure, InputFailure.unavailable);
          }

          await input.suspend();
        }
        if (desktop != null &&
            const bool.fromEnvironment('VERIFY_DESKTOP_SELECTION')) {
          await desktop.setEnabled(true);
          debugPrint('T6_READY_FOR_OS_FILE_PICKER');
          final selected = await desktop.pick();
          expect(selected, isNotNull);
          await _wait(tester, () => lock.authorized);
          await input.readFile(selected!);
          if (input.failure != null) {
            final status = await _files.invokeMapMethod<String, Object?>(
              'status',
            );
            debugPrint('T6_NATIVE_READ_STAGE ${status?['readStage']}');
          }
          expect(input.failure, isNull);
          const source = String.fromEnvironment('DESKTOP_TEST_SOURCE');
          expect(source.isNotEmpty, isTrue);
          for (var i = 0; i < 100; i++) {
            await input.suspend();
            await _wait(tester, () => lock.authorized);
            await _files.invokeMethod<String>('stageTestDrop', source);
            await _wait(
              tester,
              () => input.receipt != null || input.failure != null,
            );
            expect(input.failure, isNull);
            expect(input.receipt!.format, DocumentFormat.pdf);
            expect(lastOwned.every((b) => b.every((v) => v == 0)), isTrue);
            dropCount++;
          }
          await desktop.setEnabled(false);
          final status = await _files.invokeMapMethod<String, Object?>(
            'status',
          );
          expect(status!['pending'], 0);
        }
        if (desktop != null &&
            const bool.fromEnvironment('VERIFY_NATIVE_MOUSE_DROP')) {
          await desktop.setEnabled(true);
          await input.suspend();
          final delivered = Completer<void>();
          void changed() {
            if (!delivered.isCompleted &&
                (input.receipt != null || input.failure != null)) {
              delivered.complete();
            }
          }

          input.addListener(changed);
          debugPrint('T6_READY_FOR_FINDER_MOUSE_DROP');
          try {
            await delivered.future.timeout(const Duration(minutes: 4));
            expect(input.failure, isNull);
            expect(input.receipt!.format, DocumentFormat.pdf);
            expect(lastOwned.every((b) => b.every((v) => v == 0)), isTrue);
            nativeMouseDropVerified = true;
          } finally {
            input.removeListener(changed);
          }
          await desktop.setEnabled(false);
        }
        await input.suspend();
        expect(
          await _documentsOnDisk(),
          0,
          reason: 'Input left document files in app-owned temporary/cache directories.',
        );
        binding.reportData = {
          'input': {
            'platform': defaultTargetPlatform.name,
            'memoryInputsDisposed': memoryCount,
            'nativeCameraAvailable': nativeCameraAvailable,
            'nativeCameraFrames': nativeFrames,
            'nativePasteboardDrops': dropCount,
            'nativeFilePickerVerified': dropCount > 0,
            'nativeMouseDropVerified': nativeMouseDropVerified,
            'documentFilesRemaining': 0,
            'verifiedAtUtc': DateTime.now().toUtc().toIso8601String(),
          },
        };
      } finally {
        // Native AX automation may activate platform semantics during the picker.
        // Release that platform handle before the harness checks test ownership.
        tester.platformDispatcher.semanticsEnabledTestValue = false;
        await tester.pumpWidget(const SizedBox.shrink());
        await input.suspend();
        input.dispose();
        await desktop?.dispose();
        lock.dispose();
        app.dispose();
        await store.withExclusiveAccess(() async {
          for (final slot in [
            SecureLockCredentials.policySlot,
            SecureLockCredentials.markerSlot,
          ]) {
            await store.delete(slot);
            expect(await store.read(slot) == null, isTrue);
          }
        });
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
    semanticsEnabled: false,
  );
}
