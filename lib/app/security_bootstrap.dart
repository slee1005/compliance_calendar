import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/crypto/os_key_store.dart';
import '../core/security/app_lock_controller.dart';
import '../core/security/lock_credentials.dart';
import '../core/security/os_device_authenticator.dart';
import '../core/security/privacy_guard.dart';
import '../core/ocr/input_controller.dart';
import '../core/ocr/document_input.dart';
import 'document_inputs.dart';

import 'package:flutter/foundation.dart';

import 'app.dart';

/// Production composition always installs the real lock gate before any UI.
final class SecurityBootstrap extends StatefulWidget {
  /// No test credentials or success simulation are accepted by this entry point.
  const SecurityBootstrap({super.key});
  @override
  State<SecurityBootstrap> createState() => _SecurityBootstrapState();
}

class _SecurityBootstrapState extends State<SecurityBootstrap> {
  late final AppLockController _lock = AppLockController(
    credentials: SecureLockCredentials(OsKeyStore(), OsDeviceAuthenticator()),
    privacy: NativePrivacyGuard(),
    onLock: () async {
      final stopped = _input.suspend();
      await _desktop?.setEnabled(false);
      await stopped;
      if (_input.failure == InputFailure.unavailable) {
        throw const InputException(InputFailure.unavailable);
      }
    },
  );
  late final StreamCameraInput? _camera =
      const {
        TargetPlatform.android,
        TargetPlatform.iOS,
      }.contains(defaultTargetPlatform)
      ? StreamCameraInput()
      : null;
  late final NativeDesktopInput? _desktop =
      const {
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }.contains(defaultTargetPlatform)
      ? NativeDesktopInput()
      : null;
  late final InputController _input = InputController(
    access: LockInputAccess(_lock),
    camera: _camera,
    desktop: _desktop,
  );
  @override
  void dispose() {
    _input.dispose();
    final desktop = _desktop;
    if (desktop != null) {
      unawaited(
        desktop.dispose().catchError((Object _) {
          /* app is closing; no source details */
        }),
      );
    }
    _lock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ComplianceApp(
    lockController: _lock,
    inputController: _input,
    cameraPreview: _camera?.preview,
  );
}
