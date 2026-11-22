import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Writes counts and booleans only; no input bytes, source paths or credentials.
Future<void> main() async {
  await integrationDriver(
    timeout: const Duration(minutes: 16),
    responseDataCallback: (data) async {
      final result = data?['input'];
      if (result is! Map ||
          !const [
            'macOS',
            'iOS',
            'android',
            'windows',
          ].contains(result['platform'])) {
        throw StateError('Native input evidence missing.');
      }
      final directory = Directory(
        'artifacts/t6/${(result['platform'] as String).toLowerCase()}',
      );
      await directory.create(recursive: true);
      await File('${directory.path}/input.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
        flush: true,
      );
      final variant = result['nativeMouseDropVerified'] == true
          ? 'mouse-drop'
          : result['nativeFilePickerVerified'] == true
          ? 'selection'
          : 'stream';
      await File('${directory.path}/input-$variant.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
        flush: true,
      );
      stdout.writeln('Native input verification passed: ${result['platform']}');
    },
  );
}
