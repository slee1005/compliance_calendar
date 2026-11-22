/// Actual enrolled device authentication capabilities, independent of UI.
final class DeviceAuthCapabilities {
  /// Hardware alone does not imply that biometrics are enrolled.
  const DeviceAuthCapabilities({
    required this.deviceCredential,
    required this.biometrics,
  });

  /// The OS can authenticate the device owner, including its PIN/password.
  final bool deviceCredential;

  /// At least one biometric method is enrolled.
  final bool biometrics;
}

/// Sanitized outcomes, without platform exception messages or biometric data.
enum DeviceAuthOutcome {
  /// The OS authenticated the device owner.
  success,

  /// The prompt was dismissed.
  cancelled,

  /// Authentication was denied.
  denied,

  /// OS authentication is temporarily locked out.
  lockedOut,

  /// Authentication is not configured or supported.
  unavailable,

  /// The OS request failed safely.
  failed,
}

/// Native authentication boundary; feature code never selects an OS directly.
abstract interface class DeviceAuthenticator {
  /// Queries actual OS support and enrollment.
  Future<DeviceAuthCapabilities> capabilities();

  /// Uses native credentials as fallback unless biometricOnly is requested.
  Future<DeviceAuthOutcome> authenticate({bool biometricOnly = false});

  /// Cancels an outstanding prompt when the app really backgrounds or locks.
  Future<void> cancel();
}
