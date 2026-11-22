import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Stores only verified booleans and native capability status, never credentials.
Future<void> main() async {
  await integrationDriver(
    timeout: const Duration(minutes: 13),
    responseDataCallback: (data) async {
      final result = data?['lock'];
      if (result is! Map ||
          !const [
            'macOS',
            'iOS',
            'android',
            'windows',
          ].contains(result['platform'])) {
        throw StateError('Native lock evidence missing.');
      }
      final directory = Directory(
        'artifacts/t5/${(result['platform'] as String).toLowerCase()}',
      );
      await directory.create(recursive: true);
      await File('${directory.path}/lock.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
        flush: true,
      );
      final variant = result['realFiveMinuteBackgroundVerified'] == true
          ? 'background'
          : result['nativeBiometricsVerified'] == true
          ? 'biometric'
          : result['nativeDeviceCredentialVerified'] == true
          ? 'device'
          : 'password';
      await File('${directory.path}/lock-$variant.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
        flush: true,
      );
      stdout.writeln('Native lock verification passed: ${result['platform']}');
    },
  );
}
