import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../shared/models/license_validation.dart';
import '../../shared/models/payload.dart';
import '../crypto/key_derivation.dart';
import 'cache_models.dart';
import 'license_repository.dart';

export 'license_repository.dart';

part 'database_worker.dart';
part 'sqlcipher_repository.dart';

/// SQLCipher cache with a single worker isolate owning its native connection.
///
/// Opening never initializes organization keys, migrates plaintext databases,
/// removes corrupt files, or changes the caller's secure key-version binding.
final class ComplianceDatabase {
  ComplianceDatabase._();
  final ReceivePort _inbox = ReceivePort();
  final Completer<void> _ready = Completer<void>();
  final Map<int, Completer<Object?>> _pending = {};
  SendPort? _commands;
  Isolate? _worker;
  int _next = 0;
  bool _closed = false;
  Future<void>? _closing;
  late String _cipherVersion;

  /// Opens only with the explicitly selected derived key. Creation is opt-in.
  ///
  /// The caller retains key ownership and must destroy it after this completes.
  /// A missing file with createIfMissing=false fails without creating a file.
  static Future<ComplianceDatabase> open({
    required String path,
    required DatabaseKey key,
    bool createIfMissing = false,
  }) async {
    if (path.isEmpty ||
        path == ':memory:' ||
        path.contains('\x00') ||
        !File(path).isAbsolute) {
      throw const StorageException(StorageErrorCode.invalidRequest);
    }
    final result = ComplianceDatabase._();
    result._inbox.listen(result._receive);
    try {
      result._worker = await Isolate.spawn(
        _databaseWorker,
        (result._inbox.sendPort, path, key.hex, createIfMissing),
        onExit: result._inbox.sendPort,
        onError: result._inbox.sendPort,
        errorsAreFatal: true,
      );
      await result._ready.future;
      return result;
    } catch (error) {
      result._worker?.kill(priority: Isolate.immediate);
      result._inbox.close();
      if (error is StorageException) rethrow;
      throw const StorageException(StorageErrorCode.cannotOpen);
    }
  }

  /// Runtime SQLCipher version, returned only after encryption checks succeed.
  String get cipherVersion => _cipherVersion;

  /// Repository sharing this worker. It accepts encrypted payloads only.
  LicenseRepository get licenses => _SqlCipherLicenseRepository(this);

  void _receive(Object? message) {
    if (message is! Map) {
      _fail(const StorageException(StorageErrorCode.closed));
      return;
    }
    if (message['id'] == 0) {
      if (message['error'] != null) {
        _ready.completeError(_decodeError(message['error']));
      } else {
        _commands = message['port'] as SendPort;
        _cipherVersion = message['version'] as String;
        _ready.complete();
      }
      return;
    }
    final pending = _pending.remove(message['id']);
    if (pending == null) return;
    if (message['error'] != null) {
      pending.completeError(_decodeError(message['error']));
    } else {
      pending.complete(message['value']);
    }
  }

  static StorageException _decodeError(Object? code) => StorageException(
    StorageErrorCode.values.firstWhere(
      (v) => v.name == code,
      orElse: () => StorageErrorCode.operationFailed,
    ),
  );

  void _fail(StorageException error) {
    _closed = true;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
    _inbox.close();
  }

  Future<Object?> _request(
    String operation, [
    Map<String, Object?> args = const {},
  ]) {
    if (_closed || _commands == null) {
      return Future.error(const StorageException(StorageErrorCode.closed));
    }
    final id = ++_next;
    final response = Completer<Object?>();
    _pending[id] = response;
    _commands!.send({'id': id, 'operation': operation, 'args': args});
    return response.future;
  }

  /// Confirms encrypted page integrity and SQLite structural integrity.
  Future<void> checkIntegrity() async => await _request('integrity');

  /// Flushes the encrypted WAL into the database; does not export plaintext.
  Future<void> checkpoint() async => await _request('checkpoint');

  /// Closes the worker, freeing the connection and key material it owns.
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    if (_closed) return;
    final response = _request('close');
    _closed = true;
    try {
      await response;
    } finally {
      _worker?.kill();
      _inbox.close();
    }
  }

  @override
  String toString() => 'ComplianceDatabase(redacted)';
}
