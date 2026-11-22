import 'package:license_manager/core/storage/cache_models.dart';
import 'package:license_manager/core/storage/db.dart';

import 'storage_support.dart';

/// Measures the public API including payload validation, isolate messages, SQL,
/// transactional queue/audit writes, and result decoding. Fixture preparation,
/// organization initialization, and DB open/integrity checks are outside timing.
Future<({double insertMs, double filterMs, int matches})> benchmarkCache(
  ComplianceDatabase db,
) async {
  final payloads = List.generate(
    500,
    (i) => storagePayload(1000 + i, days: i % 150 - 10),
  );
  final watch = Stopwatch()..start();
  await db.licenses.upsertAll(payloads);
  watch.stop();
  final insertMs = watch.elapsedMicroseconds / 1000;
  watch.reset();
  watch.start();
  final rows = await db.licenses.list(
    filter: LicenseFilter(
      status: LicenseStatus.urgent,
      today: DateTime.utc(2026, 11, 21),
    ),
  );
  watch.stop();
  return (
    insertMs: insertMs,
    filterMs: watch.elapsedMicroseconds / 1000,
    matches: rows.length,
  );
}
