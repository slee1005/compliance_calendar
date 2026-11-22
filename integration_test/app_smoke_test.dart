import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:license_manager/app/app.dart';
import 'package:license_manager/core/crypto/os_key_store.dart';
import 'package:license_manager/core/security/app_lock_controller.dart';
import 'package:license_manager/core/security/lock_credentials.dart';
import 'package:license_manager/core/security/os_device_authenticator.dart';
import 'package:license_manager/core/security/privacy_guard.dart';
import 'package:license_manager/app/app_controller.dart';
import 'package:license_manager/app/router.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const capturePreview = bool.fromEnvironment('CAPTURE_PREVIEW');
  final mobileCapture = const {
    TargetPlatform.android,
    TargetPlatform.iOS,
  }.contains(defaultTargetPlatform);

  testWidgets('native runner starts and reaches every top-level preview', (
    tester,
  ) async {
    final security = AppLockController(
      credentials: SecureLockCredentials(
        OsKeyStore(
          service:
              'com.smallbizcompliance.preview.${DateTime.now().microsecondsSinceEpoch}',
        ),
        OsDeviceAuthenticator(),
      ),
      privacy: NativePrivacyGuard(),
    );
    addTearDown(security.dispose);
    final controller = AppController();
    addTearDown(controller.dispose);
    final captureKey = GlobalKey();
    final screenshots = <Map<String, Object>>[];
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: ComplianceApp(controller: controller, lockController: security),
      ),
    );
    await tester.pumpAndSettle();
    final nativeWatch = Stopwatch()..start();
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      await const MethodChannel('com.smallbizcompliance/privacy')
          .invokeMethod<Object?>('activateTestWindow');
    }
    while (!security.canShowContent) {
      if (nativeWatch.elapsed > const Duration(seconds: 60)) {
        fail('Native preview did not become visible');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    if (capturePreview && mobileCapture) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
    }
    Future<void> capture(String name) async {
      if (!capturePreview) return;
      await tester.pumpAndSettle();
      if (name != 'onboarding') {
        expect(find.text('자격·컴플라이언스').hitTestable(), findsOneWidget);
        expect(find.text('예시 모드 · 가상 자료입니다').hitTestable(), findsOneWidget);
      }
      if (mobileCapture) {
        final png = Uint8List.fromList(await binding.takeScreenshot(name));
        final header = ByteData.sublistView(png);
        screenshots.add({
          'name': name,
          'width': header.getUint32(16),
          'height': header.getUint32(20),
          'png': base64Encode(png),
        });
        return;
      }
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(png, isNotNull);
        screenshots.add({
          'name': name,
          'width': image.width,
          'height': image.height,
          'png': base64Encode(png!.buffer.asUint8List()),
        });
      } finally {
        image.dispose();
      }
    }

    await capture('onboarding');
    final start = find.byKey(const Key('start-example'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.text('예시 모드 · 가상 자료입니다'), findsOneWidget);
    await capture('dashboard');
    for (final destination in AppDestination.values) {
      controller.navigate(destination);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: destination.name);
      if (destination == AppDestination.licenses) await capture('licenses');
    }
    controller.showCredential(controller.records.first);
    await tester.pumpAndSettle();
    expect(find.text('목록으로'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'credential detail');
    controller.showStaff('A. Han');
    await tester.pumpAndSettle();
    expect(find.text('A. Han · 예시'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'staff detail');
    controller.restart();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('start-empty')), findsOneWidget);
    expect(controller.records, isEmpty);
    if (capturePreview) {
      binding.reportData = {
        'preview': {
          'schema': 1,
          'targetPlatform': defaultTargetPlatform.name,
          'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
          'devicePixelRatio': tester.view.devicePixelRatio,
          'capturePixelRatio': mobileCapture ? tester.view.devicePixelRatio : 1,
          'captureMethod': mobileCapture
              ? 'integration_test native screenshot'
              : 'native Flutter app RenderRepaintBoundary',
          'isWeb': kIsWeb,
          'screens': screenshots,
        },
      };
    }
  });
}
