import 'dart:async';
import 'dart:typed_data';

import '../core/otp/otp_parameters.dart';
import '../core/otp/otp_types.dart';
import '../core/security/key_wrapper.dart';
import '../core/security/vault_cipher.dart';
import 'account.dart';
import 'vault_codec.dart';
import 'vault_file_store.dart';

enum VaultUnreadableReason {
  /// A vault file exists but its key is gone (Keystore reset, restore onto a
  /// new device).
  keyMissing,

  /// The key does not open the file, or the file was altered.
  decryptFailed,

  /// The file decrypted but its content is not a valid vault.
  corruptContent,
}

sealed class VaultState {
  const VaultState();
}

final class VaultLocked extends VaultState {
  const VaultLocked();
}

final class VaultUnlocked extends VaultState {
  const VaultUnlocked(this.accounts);

  /// Display order. Unmodifiable.
  final List<Account> accounts;
}

final class VaultUnreadable extends VaultState {
  const VaultUnreadable(this.reason);

  final VaultUnreadableReason reason;
}

/// The single owner of stored accounts.
///
/// While unlocked, accounts and the vault key live in memory; [lock] drops
/// both. Every mutation is encrypted and written before the in-memory state
/// changes, so memory is never ahead of disk. Mutations run one at a time.
final class AccountRepository {
  AccountRepository({
    required this._keys,
    required this._files,
    this._now = DateTime.now,
  });

  final KeyWrapper _keys;
  final VaultFileStore _files;
  final DateTime Function() _now;

  final StreamController<VaultState> _states =
      StreamController<VaultState>.broadcast();
  VaultState _state = const VaultLocked();
  Uint8List? _key;

  // Bumped by lock(), so an unlock that was in flight when the app locked
  // cannot publish an unlocked state afterwards.
  int _lockGeneration = 0;
  Future<void> _pending = Future<void>.value();

  VaultState get state => _state;

  /// Emits every state change after the current one.
  Stream<VaultState> get states => _states.stream;

  /// The unlocked accounts. Throws [StateError] unless unlocked.
  List<Account> get accounts => _requireUnlocked().accounts;

  /// Opens the vault, creating it on first run.
  ///
  /// Never overwrites a vault it cannot read: that case yields
  /// [VaultUnreadable], and only [resetUnreadableVault] starts over.
  Future<VaultState> unlock() {
    // Captured now, not inside the queued action: a lock() issued while this
    // call waits in the queue must still cancel it.
    final generation = _lockGeneration;
    return _serialized(() => _unlock(generation));
  }

  Future<VaultState> _unlock(int generation) async {
    if (_state is VaultUnlocked) return _state;

    final key = await _keys.readKey();
    // The key is wiped on every exit, including I/O errors, except the one
    // path that adopts it as _key.
    var adopted = false;
    try {
      final data = await _files.read();

      if (data == null) {
        // First run, or a key left behind by an iOS reinstall or an
        // interrupted first run. Either way there is nothing to lose.
        await _createEmptyVault(generation);
        return _state;
      }
      if (key == null) {
        return _publishUnlessLocked(
          generation,
          const VaultUnreadable(VaultUnreadableReason.keyMissing),
        );
      }

      final Uint8List clear;
      try {
        clear = await VaultCipher.decrypt(data, key);
      } on VaultDecryptException {
        return _publishUnlessLocked(
          generation,
          const VaultUnreadable(VaultUnreadableReason.decryptFailed),
        );
      }
      try {
        final accounts = VaultCodec.decode(clear);
        if (generation != _lockGeneration) return _state;
        _key = key;
        adopted = true;
        return _publish(VaultUnlocked(List.unmodifiable(accounts)));
      } on VaultFormatException {
        return _publishUnlessLocked(
          generation,
          const VaultUnreadable(VaultUnreadableReason.corruptContent),
        );
      } finally {
        _wipe(clear);
      }
    } finally {
      if (key != null && !adopted) _wipe(key);
    }
  }

  /// Drops the accounts and the key from memory immediately.
  void lock() {
    final key = _key;
    if (key != null) _wipe(key);
    _key = null;
    _lockGeneration++;
    if (_state is VaultUnlocked) _publish(const VaultLocked());
  }

  /// Moves an unreadable vault aside (it is kept, not deleted, so it can be
  /// recovered later) and starts a fresh, empty vault. Returns the name the
  /// old file was moved to.
  Future<String> resetUnreadableVault() {
    final generation = _lockGeneration;
    return _serialized(() async {
      if (_state is! VaultUnreadable) {
        throw StateError('Only an unreadable vault can be reset');
      }
      final movedTo = await _files.quarantine();
      await _createEmptyVault(generation);
      return movedTo;
    });
  }

  Future<Account> add(OtpParameters parameters) => _serialized(() async {
    final account = Account.fromParameters(
      parameters,
      id: Account.newId(),
      createdAt: _now().toUtc(),
    );
    await _save([..._requireUnlocked().accounts, account]);
    return account;
  });

  Future<Account> rename(String id, {String? issuer, String? accountName}) =>
      _serialized(() async {
        final current = _requireUnlocked().accounts;
        final index = _indexOf(current, id);
        final updated = current[index].copyWith(
          issuer: issuer,
          accountName: accountName,
        );
        await _save([...current]..[index] = updated);
        return updated;
      });

  Future<void> delete(String id) => _serialized(() async {
    final current = _requireUnlocked().accounts;
    final index = _indexOf(current, id);
    await _save([...current]..removeAt(index));
  });

  /// Moves the account at [from] so it ends up at index [to] in the result.
  Future<void> reorder(int from, int to) => _serialized(() async {
    final reordered = [..._requireUnlocked().accounts];
    RangeError.checkValidIndex(from, reordered, 'from');
    RangeError.checkValidIndex(to, reordered, 'to');
    reordered.insert(to, reordered.removeAt(from));
    await _save(reordered);
  });

  /// Advances an HOTP counter and returns the new value. The new counter is
  /// on disk before this completes, so a shown code is never reissued.
  Future<int> incrementCounter(String id) => _serialized(() async {
    final current = _requireUnlocked().accounts;
    final index = _indexOf(current, id);
    final account = current[index];
    if (account.type != OtpType.hotp) {
      throw StateError('Only HOTP accounts have a counter');
    }
    final updated = account.copyWith(counter: account.counter + 1);
    await _save([...current]..[index] = updated);
    return updated.counter;
  });

  Future<void> dispose() async {
    lock();
    await _states.close();
  }

  Future<void> _createEmptyVault(int generation) async {
    // The key is stored before the vault is written: a crash in between
    // leaves a stray key (recovered on next unlock), never a vault whose key
    // was lost.
    final key = VaultCipher.newKey();
    var adopted = false;
    try {
      await _keys.storeKey(key);
      final clear = VaultCodec.encode(const []);
      await _files.write(await VaultCipher.encrypt(clear, key));
      if (generation != _lockGeneration) {
        _publish(const VaultLocked());
        return;
      }
      _key = key;
      adopted = true;
      _publish(const VaultUnlocked([]));
    } finally {
      if (!adopted) _wipe(key);
    }
  }

  Future<void> _save(List<Account> accounts) async {
    // Work on a copy of the key: lock() may zero _key while this write is
    // in flight, and the file must still be encrypted with the real key.
    final key = Uint8List.fromList(_requireKey());
    final clear = VaultCodec.encode(accounts);
    try {
      await _files.write(await VaultCipher.encrypt(clear, key));
    } finally {
      _wipe(clear);
      _wipe(key);
    }
    if (_state is VaultUnlocked) {
      _publish(VaultUnlocked(List.unmodifiable(accounts)));
    }
  }

  VaultUnlocked _requireUnlocked() {
    final state = _state;
    if (state is! VaultUnlocked) throw StateError('Vault is not unlocked');
    return state;
  }

  Uint8List _requireKey() {
    final key = _key;
    if (key == null) throw StateError('Vault is not unlocked');
    return key;
  }

  static int _indexOf(List<Account> accounts, String id) {
    final index = accounts.indexWhere((a) => a.id == id);
    if (index < 0) throw StateError('No account with that id');
    return index;
  }

  static void _wipe(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

  /// Publishes [state] only if no lock() happened since [generation] was
  /// captured; otherwise the app stays locked and the result is dropped.
  VaultState _publishUnlessLocked(int generation, VaultState state) =>
      generation == _lockGeneration ? _publish(state) : _state;

  VaultState _publish(VaultState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
    return state;
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}
