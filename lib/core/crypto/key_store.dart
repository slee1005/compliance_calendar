/// Value-free key management errors suitable for UI handling.
enum KeyErrorCode {
  /// No key exists; initialization or recovery is required.
  missingKey,

  /// Persisted key material is malformed and must never be replaced silently.
  corruptKey,

  /// The active key pointer or requested version is invalid.
  invalidVersion,

  /// Secure storage or its synchronization lock could not be used.
  storageUnavailable,

  /// A write could not be verified by reading it back.
  storageConflict,

  /// No further key version can be allocated.
  versionLimit,
}

/// A sanitized failure with no storage values, platform messages, or key bytes.
final class KeyManagementException implements Exception {
  /// Creates a failure containing only its non-sensitive reason.
  const KeyManagementException(this.code);

  /// The reason callers can translate into recovery guidance.
  final KeyErrorCode code;

  @override
  String toString() => 'KeyManagementException(${code.name})';
}

/// Secure persistence and cross-process synchronization for organization keys.
///
/// Implementations must not use plaintext persistence or destructive error
/// recovery. Read/write operations are called inside withExclusiveAccess.
abstract interface class KeyStore {
  /// Reads an app-owned value from OS secure storage.
  Future<String?> read(String key);

  /// Writes an app-owned value to OS secure storage.
  Future<void> write(String key, String value);

  /// Removes only the named app-owned value, for explicit lifecycle cleanup.
  Future<void> delete(String key);

  /// Serializes key mutations across processes using the same app namespace.
  /// Native lock I/O errors are sanitized; callback domain errors are preserved.
  Future<T> withExclusiveAccess<T>(Future<T> Function() action);
}
