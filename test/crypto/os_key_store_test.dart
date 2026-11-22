import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:license_manager/core/crypto/key_store.dart';
import 'package:license_manager/core/crypto/os_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'Android options prohibit destructive reset and isolate the namespace',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      Map<Object?, Object?>? options;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            options =
                (call.arguments as Map<Object?, Object?>)['options']
                    as Map<Object?, Object?>;
            return null;
          });
      await OsKeyStore(service: 'com.smallbizcompliance.test')
          .read('public-probe');
      expect(options?['resetOnError'], 'false');
      expect(options?['migrateOnAlgorithmChange'], 'false');
      expect(options?['storageNamespace'], 'com.smallbizcompliance.test');
    },
  );

  test(
    'Apple key stores are private, non-synchronizing, and device-bound on iOS',
    () async {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        debugDefaultTargetPlatformOverride = platform;
        Map<Object?, Object?>? options;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              options =
                  (call.arguments as Map<Object?, Object?>)['options']
                      as Map<Object?, Object?>;
              return null;
            });
        await OsKeyStore(service: 'com.smallbizcompliance.test')
            .read('public-probe');
        expect(options?['accountName'], 'com.smallbizcompliance.test');
        expect(options?['accessibility'], 'unlocked_this_device');
        expect(options?['synchronizable'], 'false');
        expect(options?['groupId'], isNull);
        if (platform == TargetPlatform.macOS) {
          expect(options?['usesDataProtectionKeychain'], 'false');
        }
      }
    },
  );

  test('native storage errors never expose backend messages', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(
            code: 'test',
            message: 'SIMULATED-PRIVATE-DETAIL',
          );
        });
    final store = OsKeyStore(service: 'com.smallbizcompliance.test');
    for (final action in [
      () => store.read('probe'),
      () => store.write('probe', 'not-a-key'),
      () => store.delete('probe'),
    ]) {
      try {
        await action();
        fail('Expected secure storage error');
      } on KeyManagementException catch (error) {
        expect(error.code, KeyErrorCode.storageUnavailable);
        expect(error.toString().contains('SIMULATED-PRIVATE-DETAIL'), isFalse);
      }
    }
  });

  test('Windows scopes every operation to its own namespace', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final names = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final arguments = call.arguments as Map<Object?, Object?>;
          names.add(arguments['key']! as String);
          final options = arguments['options']! as Map<Object?, Object?>;
          expect(options['useBackwardCompatibility'], 'false');
          return null;
        });
    final store = OsKeyStore(service: 'com.smallbizcompliance.test');
    await store.read('probe');
    await store.write('probe', 'not-a-key');
    await store.delete('probe');
    expect(names, List.filled(3, 'com.smallbizcompliance.test.probe'));
  });

  test('unsupported hosts and unsafe service paths fail closed', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(() => OsKeyStore(), throwsA(isA<KeyManagementException>()));
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    for (final service in [
      '',
      '../outside',
      'name\n',
      List.filled(101, 'a').join(),
    ]) {
      expect(
        () => OsKeyStore(service: service),
        throwsA(isA<KeyManagementException>()),
      );
    }
  });
}
