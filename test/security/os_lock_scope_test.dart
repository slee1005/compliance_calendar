import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:license_manager/core/crypto/os_key_store.dart';
import 'package:license_manager/core/security/lock_credentials.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

final class _Paths extends PathProviderPlatform {
  _Paths(this.directory);
  final String directory;
  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'OS lock preserves credential-domain denial and releases its file handle',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'compliance-lock-scope-',
      );
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(directory.path);
      try {
        final store = OsKeyStore(service: 'com.smallbizcompliance.test.scope');
        await expectLater(
          store.withExclusiveAccess<void>(() async {
            throw const LockException(LockFailure.denied);
          }),
          throwsA(
            isA<LockException>().having(
              (e) => e.code,
              'code',
              LockFailure.denied,
            ),
          ),
        );
        expect(await store.withExclusiveAccess(() async => true), isTrue);
        final files = await directory
            .list(recursive: true)
            .where((f) => f is File)
            .cast<File>()
            .toList();
        expect(files.length, 1);
        expect(await files.single.length(), 0);
      } finally {
        PathProviderPlatform.instance = previous;
        await directory.delete(recursive: true);
      }
    },
  );
}
