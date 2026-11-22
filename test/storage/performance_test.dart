import 'package:flutter_test/flutter_test.dart';

import '../support/cache_benchmark.dart';
import '../support/storage_support.dart';

void main() {
  test('500 cache+queue+audit inserts and indexed filter retain all expected records', () async {
    final harness = StorageHarness();
    await harness.initialize();
    try {
      final result = await benchmarkCache(harness.db);
      // Timing contains no record values, SQL, paths or keys.
      // ignore: avoid_print
      print(
        'T4 SQLCipher insert500=${result.insertMs.toStringAsFixed(2)}ms filter=${result.filterMs.toStringAsFixed(2)}ms',
      );
      expect(result.matches, 92);
      expect(
        (await harness.db.licenses.pendingChanges(limit: 1000)).length,
        500,
      );
      expect((await harness.db.licenses.auditEntries()).length, 500);
      // Enforce wall time on the native AOT runner. JIT compilation and parallel
      // unit-test contention are not representative application benchmarks.
      if (const bool.fromEnvironment('ENFORCE_STORAGE_PERFORMANCE')) {
        expect(result.insertMs, lessThan(50));
        expect(result.filterMs, lessThan(50));
        expect(result.insertMs + result.filterMs, lessThan(50));
      }
    } finally {
      await harness.dispose();
    }
  });
}
