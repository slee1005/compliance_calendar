import 'package:license_manager/core/crypto/key_store.dart';
import 'package:license_manager/shared/models/license.dart';
import 'package:license_manager/shared/models/license_category.dart';

/// Test-only in-memory OS-store substitute; values are generated at runtime.
final class TestKeyStore implements KeyStore {
  /// Runtime-only values; tests must never print or snapshot their contents.
  final Map<String, String> values = {};

  /// Number of write attempts, without secret-value diagnostics.
  int writes = 0;

  /// Number of read attempts.
  int reads = 0;

  /// Simulates unavailable secure storage.
  bool failReads = false;

  /// Simulates a failed named write without changing that value.
  String? failWriteTo;

  /// Simulates an ambiguous committed write followed by a failed verification.
  String? failReadBackOf;
  String? _failedRead;

  /// Simulates a lost write for read-back verification.
  bool discardWrites = false;

  /// Simulates inability to acquire an OS lock.
  bool failLock = false;

  @override
  Future<String?> read(String key) async {
    reads++;
    if (key == _failedRead) {
      _failedRead = null;
      throw StateError('SIMULATED-PRIVATE-BACKEND-DETAIL');
    }
    if (failReads) throw StateError('SIMULATED-PRIVATE-BACKEND-DETAIL');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (key == failWriteTo) {
      throw StateError('SIMULATED-PRIVATE-BACKEND-DETAIL');
    }
    if (!discardWrites) values[key] = value;
    if (key == failReadBackOf) _failedRead = key;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<T> withExclusiveAccess<T>(Future<T> Function() action) async {
    if (failLock) throw StateError('SIMULATED-PRIVATE-BACKEND-DETAIL');
    return action();
  }
}

/// Fictional metadata only; secret organization keys are never fixture literals.
License cryptoLicense({
  String id = '96db7b78-58ba-465d-bd21-a5340b552c8a',
  DateTime? expiry,
  String? number = 'MEMORY-ONLY',
}) => License(
  id: id,
  category: LicenseCategory.professionalLicense,
  licenseType: 'Example permit',
  holderName: 'Example alias',
  holderType: 'staff',
  issueDate: DateTime.utc(2024),
  expirationDate: expiry ?? DateTime.utc(2028, 12, 31),
  issuer: 'Example issuer',
  licenseNumber: number,
);
