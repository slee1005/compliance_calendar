import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:integration_test/integration_test_driver.dart';

/// Saves only screenshots returned by a passing native app test.
Future<void> main() async {
  await integrationDriver(
    timeout: const Duration(minutes: 5),
    responseDataCallback: (data) async {
      if (data?['preview'] is! Map<String, dynamic>) {
        throw StateError('Native preview evidence was not returned.');
      }
      final preview = data!['preview'] as Map<String, dynamic>;
      const platforms = {
        'android': 'android',
        'iOS': 'ios',
        'macOS': 'macos',
        'windows': 'windows',
      };
      final platform = platforms[preview['targetPlatform']];
      if (preview['schema'] != 1 ||
          preview['isWeb'] != false ||
          platform == null) {
        throw StateError('Expected a supported native runner.');
      }
      final screens = preview['screens'];
      if (screens is! List || screens.length != 3) {
        throw StateError('Expected three application screenshots.');
      }
      final output = Directory('artifacts/t1/$platform');
      await output.create(recursive: true);
      final entries = <Map<String, Object>>[];
      final names = <String>{};
      for (final screen in screens.cast<Map<String, dynamic>>()) {
        final name = screen['name'] as String;
        if (!const {'onboarding', 'dashboard', 'licenses'}.contains(name) ||
            !names.add(name)) {
          throw StateError('Unexpected or duplicate screenshot name.');
        }
        final bytes = base64Decode(screen['png'] as String);
        final header = ByteData.sublistView(bytes);
        const pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
        if (bytes.length < 24 ||
            !List.generate(
              8,
              (i) => bytes[i] == pngSignature[i],
            ).every((v) => v)) {
          throw StateError('Screenshot is not PNG data.');
        }
        final width = header.getUint32(16);
        final height = header.getUint32(20);
        if (width != screen['width'] ||
            height != screen['height'] ||
            width < 300 ||
            height < 300) {
          throw StateError(
            'Screenshot dimensions do not match the native view.',
          );
        }
        final fileName = '$name.png';
        await File('${output.path}/$fileName').writeAsBytes(bytes, flush: true);
        entries.add({
          'file': fileName,
          'width': width,
          'height': height,
          'bytes': bytes.length,
        });
      }
      final manifest = {
        'schema': 1,
        'platform': platform,
        'deviceId':
            Platform.environment['COMPLIANCE_DEVICE_ID'] ?? 'unspecified',
        'hostPlatform': Platform.operatingSystem,
        'flutterVersion': (await File(
          '.flutter-version',
        ).readAsString()).trim(),
        'capturedAtUtc': preview['capturedAtUtc'],
        'nativeTestPassed': true,
        'captureMethod': preview['captureMethod'],
        'capturePixelRatio': preview['capturePixelRatio'],
        'devicePixelRatio': preview['devicePixelRatio'],
        'screens': entries,
      };
      await File('${output.path}/manifest.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
        flush: true,
      );
      stdout.writeln('Native preview evidence saved: ${output.path}');
    },
  );
}
