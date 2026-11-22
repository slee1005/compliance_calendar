// This regression intentionally inspects the vendored backend test surface.
// ignore_for_file: implementation_imports

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage_windows/src/flutter_secure_storage_windows_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

final class _TemporaryPaths extends PathProviderPlatform {
  _TemporaryPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform previous;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'compliance-store-policy-',
    );
    previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(directory.path);
    file = File.fromUri(directory.uri.resolve(encryptedJsonFileName));
  });
  tearDown(() async {
    PathProviderPlatform.instance = previous;
    await directory.delete(recursive: true);
  });

  test(
    'only a genuinely absent Windows store is treated as a new store',
    () async {
      expect(await DpapiJsonFileMapStorage().load({}), isEmpty);
      expect(await file.exists(), isFalse);
    },
  );

  test('a read failure is not converted to an empty Windows key map', () async {
    final obstructing = Directory(file.path);
    await obstructing.create();
    await expectLater(
      DpapiJsonFileMapStorage().load({}),
      throwsA(isA<FileSystemException>()),
    );
    expect(await obstructing.exists(), isTrue);
  });

  test('corrupt DPAPI storage is preserved and emits no backend diagnostics', () async {
    // Deliberately invalid non-secret data in an isolated temporary directory.
    const invalid = [0, 1, 2, 3, 4];
    await file.writeAsBytes(invalid, flush: true);
    final messages = <String?>[];
    final previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message);
    try {
      await expectLater(DpapiJsonFileMapStorage().load({}), throwsA(anything));
      expect(await file.exists(), isTrue);
      expect((await file.readAsBytes()).join(',') == invalid.join(','), isTrue);
      expect(messages.isEmpty, isTrue);
    } finally {
      debugPrint = previousPrint;
    }
  }, skip: !Platform.isWindows);
}
