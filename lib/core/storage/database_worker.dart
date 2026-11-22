part of 'db.dart';

void _databaseWorker((SendPort, String, String, bool) input) {
  final (reply, path, hex, create) = input;
  Database? database;
  try {
    // READWRITE without CREATE is essential when a key binding/file is missing.
    database = sqlite3.open(
      path,
      mode: create ? OpenMode.readWriteCreate : OpenMode.readWrite,
    );
    database.execute('PRAGMA cipher_log_level = NONE');
    final versionRows = database.select('PRAGMA cipher_version');
    if (versionRows.isEmpty ||
        !(versionRows.first.values.first as String).startsWith('4.')) {
      throw const StorageException(StorageErrorCode.encryptionUnavailable);
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hex)) {
      throw const StorageException(StorageErrorCode.invalidRequest);
    }
    // PRAGMA values cannot be bound. This value is fixed-length derived hex.
    database.execute('PRAGMA key = "x\'$hex\'"');
    database.select('SELECT count(*) FROM sqlite_master');
    // SQLCipher returns these PRAGMA scalars as TEXT on its native builds.
    if (_scalar(database, 'PRAGMA cipher_status')?.toString() != '1' ||
        _scalar(database, 'PRAGMA cipher_plaintext_header_size')?.toString() !=
            '0' ||
        _scalar(database, 'PRAGMA cipher_use_hmac')?.toString() != '1') {
      throw const StorageException(StorageErrorCode.encryptionUnavailable);
    }
    database.execute('PRAGMA cipher_memory_security = ON');
    database.execute('PRAGMA temp_store = MEMORY');
    database.execute('PRAGMA foreign_keys = ON');
    database.execute('PRAGMA secure_delete = ON');
    database.execute('PRAGMA busy_timeout = 5000');
    if (_scalar(database, 'PRAGMA temp_store') != 2) {
      throw const StorageException(StorageErrorCode.encryptionUnavailable);
    }
    _initializeSchema(database);
    if (_scalar(database, 'PRAGMA journal_mode = WAL') != 'wal') {
      throw const StorageException(StorageErrorCode.operationFailed);
    }
    database.execute('PRAGMA synchronous = FULL');
    final engine = _CacheEngine(database);
    engine.integrity();
    final commands = ReceivePort();
    reply.send({
      'id': 0,
      'port': commands.sendPort,
      'version': versionRows.first.values.first,
    });
    commands.listen((Object? message) {
      if (message is! Map) return;
      try {
        final operation = message['operation'] as String;
        final result = engine.run(
          operation,
          (message['args'] as Map).cast<String, Object?>(),
        );
        reply.send({'id': message['id'], 'value': result});
        if (operation == 'close') commands.close();
      } catch (error) {
        reply.send({
          'id': message['id'],
          'error': error is StorageException
              ? error.code.name
              : StorageErrorCode.operationFailed.name,
        });
      }
    });
  } catch (error) {
    try {
      database?.close();
    } catch (_) {
      /* Preserve the original safe error. */
    }
    reply.send({
      'id': 0,
      'error': error is StorageException
          ? error.code.name
          : StorageErrorCode.cannotOpen.name,
    });
  }
}

Object? _scalar(Database db, String sql) {
  final rows = db.select(sql);
  return rows.isEmpty ? null : rows.first.values.first;
}

const _applicationId = 0x434d4752;
void _initializeSchema(Database db) {
  db.execute('BEGIN IMMEDIATE');
  try {
    final version = db.userVersion;
    final app = _scalar(db, 'PRAGMA application_id');
    if (version == 0 &&
        app == 0 &&
        _scalar(db, 'SELECT count(*) FROM sqlite_master') == 0) {
      db.execute(_schema);
      db.execute('PRAGMA application_id = $_applicationId');
      db.userVersion = 1;
    } else if (version != 1 || app != _applicationId) {
      throw const StorageException(StorageErrorCode.unsupportedSchema);
    }
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

const _schema = '''
CREATE TABLE license_cache (
 id TEXT PRIMARY KEY NOT NULL,
 payload TEXT NOT NULL,
 category TEXT NOT NULL,
 license_type TEXT NOT NULL,
 holder_type TEXT NOT NULL CHECK(holder_type IN ('staff','business')),
 holder_name TEXT NOT NULL,
 issuer TEXT NOT NULL,
 expiration_date TEXT NOT NULL,
 revision INTEGER NOT NULL CHECK(revision > 0),
 updated_at INTEGER NOT NULL,
 deleted_at INTEGER
) STRICT;
CREATE INDEX idx_license_status_expiry ON license_cache(deleted_at, expiration_date, id);
CREATE INDEX idx_license_category_expiry ON license_cache(deleted_at, category, expiration_date, id);
CREATE INDEX idx_license_type_expiry ON license_cache(deleted_at, license_type, expiration_date, id);
CREATE TABLE change_queue (
 sequence INTEGER PRIMARY KEY AUTOINCREMENT,
 license_id TEXT NOT NULL UNIQUE REFERENCES license_cache(id),
 revision INTEGER NOT NULL CHECK(revision > 0),
 operation TEXT NOT NULL CHECK(operation IN ('upsert','delete')),
 payload TEXT,
 attempts INTEGER NOT NULL DEFAULT 0 CHECK(attempts >= 0),
 next_attempt_at INTEGER NOT NULL DEFAULT 0,
 last_error TEXT CHECK(last_error IN ('offline','unauthorized','rateLimited','conflict','unavailable')),
 CHECK((operation='upsert' AND payload IS NOT NULL) OR (operation='delete' AND payload IS NULL))
) STRICT;
CREATE INDEX idx_queue_due ON change_queue(next_attempt_at, sequence);
CREATE TABLE calendar_event_map (
 license_id TEXT PRIMARY KEY NOT NULL REFERENCES license_cache(id),
 master_event_id TEXT NOT NULL,
 preparation_event_id TEXT,
 etag TEXT
) STRICT;
CREATE TABLE calendar_ref (
 singleton INTEGER PRIMARY KEY CHECK(singleton=1),
 calendar_id TEXT NOT NULL, account_email TEXT NOT NULL,
 sync_cursor TEXT, last_synced_at INTEGER
) STRICT;
CREATE TABLE app_settings (
 singleton INTEGER PRIMARY KEY CHECK(singleton=1),
 display_name TEXT NOT NULL, mask_names INTEGER NOT NULL CHECK(mask_names IN (0,1)),
 quiet_start INTEGER NOT NULL CHECK(quiet_start BETWEEN 0 AND 23),
 quiet_end INTEGER NOT NULL CHECK(quiet_end BETWEEN 0 AND 23), reminder_days TEXT NOT NULL
) STRICT;
CREATE TABLE audit_local (
 sequence INTEGER PRIMARY KEY AUTOINCREMENT,
 occurred_at INTEGER NOT NULL,
 action TEXT NOT NULL CHECK(action IN ('upsert','softDelete')),
 license_id TEXT NOT NULL,
 previous_hash TEXT
) STRICT;
CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit_local BEGIN SELECT RAISE(ABORT, 'immutable audit'); END;
CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit_local BEGIN SELECT RAISE(ABORT, 'immutable audit'); END;
''';

final class _CacheEngine {
  _CacheEngine(this.db) {
    _lookup = db.prepare(
      'SELECT payload, revision, deleted_at FROM license_cache WHERE id=?',
      persistent: true,
    );
    _write = db.prepare(
      '''INSERT INTO license_cache
      (id,payload,category,license_type,holder_type,holder_name,issuer,expiration_date,revision,updated_at)
      VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
      payload=excluded.payload,category=excluded.category,license_type=excluded.license_type,
      holder_type=excluded.holder_type,holder_name=excluded.holder_name,issuer=excluded.issuer,
      expiration_date=excluded.expiration_date,revision=excluded.revision,updated_at=excluded.updated_at''',
      persistent: true,
    );
    _enqueue = db.prepare(
      '''
    INSERT INTO change_queue(license_id,revision,operation,payload) VALUES(?,?,?,?)
    ON CONFLICT(license_id) DO UPDATE SET revision=excluded.revision,operation=excluded.operation,
    payload=excluded.payload,attempts=0,next_attempt_at=0,last_error=NULL''',
      persistent: true,
    );
    _append = db.prepare(
      'INSERT INTO audit_local(occurred_at,action,license_id,previous_hash) VALUES(?,?,?,?)',
      persistent: true,
    );
  }
  late final PreparedStatement _lookup;
  late final PreparedStatement _write;
  late final PreparedStatement _enqueue;
  late final PreparedStatement _append;
  final Database db;

  Object? run(String operation, Map<String, Object?> args) =>
      switch (operation) {
        'upsert' => transaction(
          () =>
              upsert(_inputPayload(args['payload']), args['expected'] as int?),
        ),
        'batch' => batch(args['payloads'] as List),
        'find' => find(_id(args['id']), args['deleted'] == true),
        'list' => rows(_query(args)),
        'explain' =>
          db
              .select('EXPLAIN QUERY PLAN ${_query(args).$1}', _query(args).$2)
              .map((r) => r['detail'] as String)
              .toList(),
        'delete' => transaction(
          () => softDelete(_id(args['id']), args['expected'] as int?),
        ),
        'pending' => pending(args),
        'ack' => acknowledge(args),
        'defer' => defer(args),
        'map' => saveMap(args),
        'getMap' => first(
          'SELECT * FROM calendar_event_map WHERE license_id=?',
          [_id(args['id'])],
        ),
        'ref' => transaction(() => saveRef(args)),
        'getRef' => first('SELECT * FROM calendar_ref WHERE singleton=1'),
        'settings' => saveSettings(args),
        'getSettings' => first('SELECT * FROM app_settings WHERE singleton=1'),
        'audit' => audit(args),
        'integrity' => integrity(),
        'checkpoint' => checkpoint(),
        'close' => close(),
        _ => throw const StorageException(StorageErrorCode.invalidRequest),
      };

  T transaction<T>(T Function() action) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final value = action();
      db.execute('COMMIT');
      return value;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Map<String, Object?>? first(String sql, [List<Object?> args = const []]) {
    final result = db.select(sql, args);
    return result.isEmpty ? null : Map<String, Object?>.from(result.first);
  }

  List<Map<String, Object?>> rows((String, List<Object?>) query) => [
    for (final row in db.select(query.$1, query.$2))
      Map<String, Object?>.from(row),
  ];

  Map<String, Object?>? find(String id, bool deleted) => first(
    'SELECT * FROM license_cache WHERE id=? ${deleted ? '' : 'AND deleted_at IS NULL'}',
    [id],
  );

  Map<String, Object?> upsert(LicensePayload payload, int? expected) {
    final wire = payload.toMap();
    _writePayload(wire, expected);
    return find(wire['lm_id']!, true)!;
  }

  void _writePayload(Map<String, String> wire, int? expected) {
    final id = wire['lm_id']!;
    final found = _lookup.select([id]);
    final previous = found.isEmpty ? null : found.first;
    _revision(expected, previous?['revision'] as int? ?? 0);
    if (previous?['deleted_at'] != null) {
      throw const StorageException(StorageErrorCode.revisionConflict);
    }
    final revision = (previous?['revision'] as int? ?? 0) + 1;
    final encoded = jsonEncode(wire);
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    _write.execute([
      id,
      encoded,
      wire['lm_cat'],
      wire['lm_type'],
      wire['lm_htype'],
      wire['lm_holder'],
      wire['lm_issuer'],
      wire['lm_exp'],
      revision,
      now,
    ]);
    queue(id, revision, 'upsert', encoded);
    appendAudit(id, now, 'upsert', previous?['payload'] as String?);
  }

  Object? batch(List input) {
    if (input.length > 1000) {
      throw const StorageException(StorageErrorCode.invalidRequest);
    }
    final wires = input.map((value) => _inputPayload(value).toMap()).toList();
    if (wires.map((wire) => wire['lm_id']).toSet().length != wires.length) {
      throw const StorageException(StorageErrorCode.invalidRequest);
    }
    transaction(() {
      for (final wire in wires) {
        _writePayload(wire, null);
      }
    });
    return null;
  }

  bool softDelete(String id, int? expected) {
    final previous = find(id, true);
    _revision(expected, previous?['revision'] as int? ?? 0);
    if (previous == null || previous['deleted_at'] != null) return false;
    final revision = (previous['revision'] as int) + 1;
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    db.execute(
      'UPDATE license_cache SET deleted_at=?,updated_at=?,revision=? WHERE id=?',
      [now, now, revision, id],
    );
    queue(id, revision, 'delete', null);
    appendAudit(id, now, 'softDelete', previous['payload'] as String);
    return true;
  }

  void queue(String id, int revision, String operation, String? encoded) =>
      _enqueue.execute([id, revision, operation, encoded]);

  void appendAudit(String id, int now, String action, String? previous) =>
      _append.execute([
        now,
        action,
        id,
        previous == null
            ? null
            : sha256.convert(utf8.encode(previous)).toString(),
      ]);

  List<Map<String, Object?>> pending(Map<String, Object?> args) {
    _limit(args['limit']);
    return rows((
      'SELECT * FROM change_queue WHERE next_attempt_at<=? ORDER BY sequence LIMIT ?',
      [args['now'], args['limit']],
    ));
  }

  bool acknowledge(Map<String, Object?> args) {
    _positiveRevision(args['revision']);
    db.execute('DELETE FROM change_queue WHERE license_id=? AND revision=?', [
      _id(args['id']),
      args['revision'],
    ]);
    return db.updatedRows == 1;
  }

  bool defer(Map<String, Object?> args) => transaction(() {
    final id = _id(args['id']);
    _positiveRevision(args['revision']);
    final reason = args['reason'] as String;
    if (!ChangeFailure.values.any((r) => r.name == reason)) {
      throw const StorageException(StorageErrorCode.invalidRequest);
    }
    final row = first(
      'SELECT attempts FROM change_queue WHERE license_id=? AND revision=?',
      [id, args['revision']],
    );
    if (row == null) return false;
    final attempts = row['attempts'] as int;
    final seconds = 30 * (1 << (attempts > 10 ? 10 : attempts));
    db.execute(
      'UPDATE change_queue SET attempts=attempts+1,next_attempt_at=?,last_error=? WHERE license_id=? AND revision=?',
      [
        (args['now'] as int) + seconds * Duration.microsecondsPerSecond,
        reason,
        id,
        args['revision'],
      ],
    );
    return true;
  });
  Object? saveMap(Map<String, Object?> args) {
    final id = _id(args['id']);
    _text(args['master'], 1024);
    _text(args['preparation'], 1024, optional: true);
    _text(args['etag'], 1024, optional: true);
    if (find(id, true) == null) {
      throw const StorageException(StorageErrorCode.invalidRequest);
    }
    db.execute(
      '''INSERT INTO calendar_event_map(license_id,master_event_id,preparation_event_id,etag) VALUES(?,?,?,?)
      ON CONFLICT(license_id) DO UPDATE SET master_event_id=excluded.master_event_id,
      preparation_event_id=excluded.preparation_event_id,etag=excluded.etag''',
      [id, args['master'], args['preparation'], args['etag']],
    );
    return null;
  }

  Object? saveRef(Map<String, Object?> args) {
    _text(args['calendar'], 1024);
    _text(args['email'], 320);
    _text(args['cursor'], 8192, optional: true);
    final existing = first('SELECT * FROM calendar_ref WHERE singleton=1');
    if (existing != null &&
        (existing['calendar_id'] != args['calendar'] ||
            existing['account_email'] != args['email'])) {
      throw const StorageException(StorageErrorCode.revisionConflict);
    }
    db.execute(
      '''INSERT INTO calendar_ref(singleton,calendar_id,account_email,sync_cursor,last_synced_at) VALUES(1,?,?,?,?)
      ON CONFLICT(singleton) DO UPDATE SET calendar_id=excluded.calendar_id,account_email=excluded.account_email,
      sync_cursor=excluded.sync_cursor,last_synced_at=excluded.last_synced_at''',
      [args['calendar'], args['email'], args['cursor'], args['synced']],
    );
    return null;
  }

  Object? saveSettings(Map<String, Object?> args) {
    _text(args['name'], 60, empty: true);
    final start = args['start'] as int;
    final end = args['end'] as int;
    final days = (args['days'] as List).cast<int>();
    if (start < 0 ||
        start > 23 ||
        end < 0 ||
        end > 23 ||
        days.isEmpty ||
        days.length > 5 ||
        days.toSet().length != days.length ||
        days.any((d) => d < 1 || d > 365)) {
      throw const StorageException(StorageErrorCode.invalidRequest);
    }
    db.execute(
      '''INSERT INTO app_settings(singleton,display_name,mask_names,quiet_start,quiet_end,reminder_days) VALUES(1,?,?,?,?,?)
      ON CONFLICT(singleton) DO UPDATE SET display_name=excluded.display_name,mask_names=excluded.mask_names,
      quiet_start=excluded.quiet_start,quiet_end=excluded.quiet_end,reminder_days=excluded.reminder_days''',
      [
        args['name'],
        args['mask'] == true ? 1 : 0,
        start,
        end,
        jsonEncode(days),
      ],
    );
    return null;
  }

  List<Map<String, Object?>> audit(Map<String, Object?> args) {
    _limit(args['limit']);
    if ((args['after'] as int) < 0) {
      throw const StorageException(StorageErrorCode.invalidRequest);
    }
    return rows((
      'SELECT * FROM audit_local WHERE sequence>? ORDER BY sequence LIMIT ?',
      [args['after'], args['limit']],
    ));
  }

  Object? integrity() {
    if (db.select('PRAGMA cipher_integrity_check').isNotEmpty ||
        _scalar(db, 'PRAGMA integrity_check') != 'ok') {
      throw const StorageException(StorageErrorCode.corruptData);
    }
    return null;
  }

  Object? checkpoint() {
    final result = db.select('PRAGMA wal_checkpoint(TRUNCATE)');
    if (result.first.values.first != 0) {
      throw const StorageException(StorageErrorCode.operationFailed);
    }
    return null;
  }

  Object? close() {
    _lookup.close();
    _write.close();
    _enqueue.close();
    _append.close();
    db.close();
    return null;
  }
}

LicensePayload _inputPayload(Object? raw) {
  try {
    return LicensePayload.fromMap((raw as Map).cast<String, Object?>());
  } catch (_) {
    throw const StorageException(StorageErrorCode.invalidRequest);
  }
}

void _revision(int? expected, int actual) {
  if (expected != null && (expected < 0 || expected != actual)) {
    throw const StorageException(StorageErrorCode.revisionConflict);
  }
}

void _positiveRevision(Object? value) {
  if (value is! int || value < 1) {
    throw const StorageException(StorageErrorCode.invalidRequest);
  }
}

String _id(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      ).hasMatch(value) ||
      value.length != 36) {
    throw const StorageException(StorageErrorCode.invalidRequest);
  }
  return value;
}

void _text(
  Object? value,
  int max, {
  bool optional = false,
  bool empty = false,
}) {
  if (optional && value == null) return;
  if (value is! String ||
      value.runes.length > max ||
      (!empty && value.trim().isEmpty) ||
      RegExp(r'[\x00-\x1f\x7f\u0085\u2028\u2029]').hasMatch(value) ||
      value.runes.any((rune) => rune >= 0xd800 && rune <= 0xdfff)) {
    throw const StorageException(StorageErrorCode.invalidRequest);
  }
}

void _limit(Object? value) {
  if (value is! int || value < 1 || value > 1000) {
    throw const StorageException(StorageErrorCode.invalidRequest);
  }
}

(String, List<Object?>) _query(Map<String, Object?> args) {
  _limit(args['limit']);
  if ((args['offset'] as int) < 0) {
    throw const StorageException(StorageErrorCode.invalidRequest);
  }
  final terms = <String>[];
  final values = <Object?>[];
  if (args['deleted'] != true) terms.add('deleted_at IS NULL');
  void add(String condition, Object? value) {
    terms.add(condition);
    values.add(value);
  }

  for (final (key, column) in [
    ('category', 'category'),
    ('type', 'license_type'),
    ('holder', 'holder_type'),
  ]) {
    if (args[key] != null) {
      _text(args[key], key == 'type' ? 60 : 40);
      if (key == 'holder' && args[key] != 'staff' && args[key] != 'business') {
        throw const StorageException(StorageErrorCode.invalidRequest);
      }
      add('$column=?', args[key]);
    }
  }
  if (args['search'] != null) {
    _text(args['search'], 120, empty: true);
    terms.add(
      '(instr(lower(holder_name),lower(?))>0 OR instr(lower(license_type),lower(?))>0 OR instr(lower(issuer),lower(?))>0)',
    );
    values.addAll(List.filled(3, args['search']));
  }
  for (final (key, op) in [('from', '>='), ('through', '<=')]) {
    if (args[key] != null) {
      LicenseDate.parse(
        args[key] as String,
        field: LicenseField.expirationDate,
      );
      add('expiration_date$op?', args[key]);
    }
  }
  if (args['from'] != null &&
      args['through'] != null &&
      (args['from'] as String).compareTo(args['through'] as String) > 0) {
    throw const StorageException(StorageErrorCode.invalidRequest);
  }
  if (args['status'] != null) {
    if (args['today'] == null) {
      throw const StorageException(StorageErrorCode.invalidRequest);
    }
    final today = LicenseDate.parse(
      args['today'] as String,
      field: LicenseField.expirationDate,
    );
    final status = LicenseStatus.values.byName(args['status'] as String);
    final (int?, int?) bounds = switch (status) {
      LicenseStatus.expired => (null, -1),
      LicenseStatus.critical => (0, 7),
      LicenseStatus.urgent => (8, 30),
      LicenseStatus.upcoming => (31, 90),
      LicenseStatus.normal => (91, null),
    };
    void bound(int days, {required bool lower}) {
      final date = today.add(Duration(days: days));
      if (date.year < 1 || date.year > 9999) {
        if ((lower && date.year > 9999) || (!lower && date.year < 1)) {
          terms.add('1=0');
        }
        return;
      }
      add(
        'expiration_date${lower ? '>=' : '<='}?',
        LicenseDate.format(date, field: LicenseField.expirationDate),
      );
    }

    if (bounds.$1 != null) {
      bound(bounds.$1!, lower: true);
    }
    if (bounds.$2 != null) {
      bound(bounds.$2!, lower: false);
    }
  }
  return (
    'SELECT * FROM license_cache ${terms.isEmpty ? '' : 'WHERE ${terms.join(' AND ')}'} ORDER BY expiration_date,id LIMIT ? OFFSET ?',
    [...values, args['limit'], args['offset']],
  );
}
