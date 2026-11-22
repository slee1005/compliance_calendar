import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Saves only non-sensitive native SQLCipher version and performance evidence.
Future<void> main() async {
  await integrationDriver(
    timeout: const Duration(minutes: 5),
    responseDataCallback: (data) async {
      final result = data?['storage'];
      if (result is! Map ||
          !const [
            'macOS',
            'iOS',
            'android',
            'windows',
          ].contains(result['platform'])) {
        throw StateError('Native storage evidence missing.');
      }
      final platform = result['platform'] as String;
      final mode = result['mode'] as String;
      if (!const ['debug', 'profile', 'release'].contains(mode)) {
        throw StateError('Invalid test mode.');
      }
      final directory = Directory('artifacts/t4/${platform.toLowerCase()}');
      await directory.create(recursive: true);
      await File('${directory.path}/$mode.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
        flush: true,
      );
      stdout.writeln(
        'SQLCipher $platform $mode: insert500=${(result['insert500Ms'] as num).toStringAsFixed(2)}ms, filter=${(result['filterMs'] as num).toStringAsFixed(2)}ms',
      );
    },
  );
}
