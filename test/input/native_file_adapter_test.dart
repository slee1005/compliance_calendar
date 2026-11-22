import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:license_manager/app/document_inputs.dart';
import 'package:license_manager/core/ocr/document_input.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.smallbizcompliance/input');
  test(
    'immutable engine replies become writable owned buffers before disposal',
    () async {
      const codec = StandardMethodCodec();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler(channel.name, (message) async {
        final call = codec.decodeMethodCall(message!);
        final Object? result = switch (call.method) {
          'pick' => 'TEST-READONLY-CAPABILITY',
          'read' => Uint8List.fromList([37, 80, 68, 70, 45, 1, 2, 3]),
          _ => null,
        };
        return codec.encodeSuccessEnvelope(result).asUnmodifiableView();
      });
      addTearDown(() => messenger.setMockMessageHandler(channel.name, null));
      final input = NativeDesktopInput();
      final file = (await input.pick())!;
      final document = await file.read();
      final bytes = document.planes.single.bytes;
      bytes[0] = bytes[0];
      document.dispose();
      expect(bytes.every((value) => value == 0), isTrue);
      await file.release();
      await input.dispose();
    },
  );
  test(
    'native selection uses an opaque capability and zeroes the received buffer',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'pick' => 'TEST-OPAQUE-CAPABILITY',
              'read' => Uint8List.fromList([37, 80, 68, 70, 45, 1, 2, 3]),
              _ => null,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final input = NativeDesktopInput();
      await input.setEnabled(true);
      final file = (await input.pick())!;
      final document = await file.read();
      final bytes = document.planes.single.bytes;
      expect(document.format, DocumentFormat.pdf);
      document.dispose();
      expect(bytes.every((b) => b == 0), isTrue);
      await file.release();
      await file.release();
      expect(calls.where((c) => c.method == 'release').length, 1);
      expect(
        calls.where((c) => c.method == 'read').single.arguments,
        'TEST-OPAQUE-CAPABILITY',
      );
      await expectLater(file.read(), throwsA(isA<InputException>()));
      await input.dispose();
      expect(calls.last.method, 'enable');
      expect(calls.last.arguments, isFalse);
    },
  );
  test('native file failures hide filenames and OS details', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'pick') return 'TEST-CAPABILITY';
          if (call.method == 'read') {
            throw PlatformException(
              code: 'too_large',
              message: 'PRIVATE-SOURCE-NAME',
              details: 'PRIVATE-PATH',
            );
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final input = NativeDesktopInput();
    final file = (await input.pick())!;
    try {
      await file.read();
      fail('Expected bounded failure');
    } on InputException catch (error) {
      expect(error.code, InputFailure.tooLarge);
      expect(error.toString().contains('PRIVATE'), isFalse);
    }
    await file.release();
    await input.dispose();
  });
  test('OS picker cancellation returns no source', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final input = NativeDesktopInput();
    expect(await input.pick(), isNull);
    await input.dispose();
  });
}
