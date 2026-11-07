import 'dart:async';
import 'dart:typed_data';

import '../core/otp/otp_parameters.dart';
import '../core/security/backup_cipher.dart';
import '../core/security/secret_store.dart';
import 'account_repository.dart';
import 'vault_codec.dart';

/// Why a backup file could not be read. User-facing, so it carries no data.
enum BackupProblem {
  /// Not a CypherAuth backup (or its header is implausible).
  notABackup,

  /// Made by a newer version of CypherAuth.
  newerVersion,

  /// Larger than any real backup.
  tooLarge,

  /// Wrong password, or the file was damaged or altered.
  wrongPasswordOrDamaged,

  /// More accounts than one import may add.
  tooManyAccounts,
}

final class BackupReadException implements Exception {
  const BackupReadException(this.problem);

  final BackupProblem problem;

  @override
  String toString() => 'BackupReadException(${problem.name})';
}

/// Encrypted backup export and import (docs/system-plan.md §7).
///
/// The payload is the vault's own versioned JSON ([VaultCodec]), so backups
/// stay readable by later versions. Imports return parameters for the
/// add-account confirmation step, which skips duplicates and saves them all
/// in one write.
final class BackupService {
  BackupService({
    required this._repository,
    required this._store,
    this._now = DateTime.now,
    this._params = BackupCipher.defaultParams,
    this._inIsolate = true,
  });

  static const String lastBackupKey = 'cypher.backup.last.v1';
  static const int maxImportAccounts = 1000;

  final AccountRepository _repository;
  final SecretStore _store;
  final DateTime Function() _now;
  final BackupKdfParams _params;
  final bool _inIsolate;

  final StreamController<DateTime?> _lastBackupChanges =
      StreamController<DateTime?>.broadcast();
  DateTime? _lastBackupAt;

  /// When the last export was saved, or `null` if never.
  DateTime? get lastBackupAt => _lastBackupAt;
  Stream<DateTime?> get lastBackupChanges => _lastBackupChanges.stream;

  Future<void> initialize() async {
    final raw = await _store.read(lastBackupKey);
    _lastBackupAt = raw == null ? null : DateTime.tryParse(raw);
  }

  /// Encrypts every account with [password]. The vault must be unlocked.
  /// Nothing is recorded until [recordBackupSaved] confirms the file exists.
  Future<Uint8List> export(String password) async {
    if (!BackupPassword.isAcceptable(password)) {
      throw ArgumentError('Backup password is too short');
    }
    final clear = VaultCodec.encode(_repository.accounts);
    try {
      return await BackupCipher.encrypt(
        clear,
        password,
        params: _params,
        inIsolate: _inIsolate,
      );
    } finally {
      clear.fillRange(0, clear.length, 0);
    }
  }

  Future<void> recordBackupSaved() async {
    final at = _now().toUtc();
    await _store.write(lastBackupKey, at.toIso8601String());
    _lastBackupAt = at;
    if (!_lastBackupChanges.isClosed) _lastBackupChanges.add(at);
  }

  /// Decrypts a backup file and returns its accounts as parameters.
  /// Throws [BackupReadException].
  Future<List<OtpParameters>> readBackup(
    Uint8List file,
    String password,
  ) async {
    final Uint8List clear;
    try {
      clear = await BackupCipher.decrypt(file, password, inIsolate: _inIsolate);
    } on BackupDecryptException catch (e) {
      throw BackupReadException(switch (e.reason) {
        BackupFailure.notABackup ||
        BackupFailure.unsafeParameters => BackupProblem.notABackup,
        BackupFailure.unsupportedVersion => BackupProblem.newerVersion,
        BackupFailure.tooLarge => BackupProblem.tooLarge,
        BackupFailure.wrongPasswordOrDamaged =>
          BackupProblem.wrongPasswordOrDamaged,
      });
    }
    try {
      final accounts = VaultCodec.decode(clear);
      if (accounts.length > maxImportAccounts) {
        throw const BackupReadException(BackupProblem.tooManyAccounts);
      }
      return [
        for (final a in accounts)
          OtpParameters(
            type: a.type,
            secret: a.secret,
            issuer: a.issuer,
            accountName: a.accountName,
            algorithm: a.algorithm,
            digits: a.digits,
            period: a.period,
            counter: a.counter,
          ),
      ];
    } on VaultFormatException {
      // The content was authenticated, so this is a newer schema, not damage.
      throw const BackupReadException(BackupProblem.newerVersion);
    } finally {
      clear.fillRange(0, clear.length, 0);
    }
  }

  Future<void> dispose() => _lastBackupChanges.close();
}
