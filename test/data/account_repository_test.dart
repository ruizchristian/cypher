import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cypher/core/otp/hotp.dart';
import 'package:cypher/core/otp/otp_parameters.dart';
import 'package:cypher/core/otp/otp_secret.dart';
import 'package:cypher/core/otp/otp_types.dart';
import 'package:cypher/core/security/key_wrapper.dart';
import 'package:cypher/core/security/vault_cipher.dart';
import 'package:cypher/data/account_repository.dart';
import 'package:cypher/data/vault_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/in_memory_secret_store.dart';
import '../fakes/in_memory_vault_file_store.dart';

final _secret = OtpSecret(utf8.encode('12345678901234567890'));

OtpParameters _totp(String name) => OtpParameters(
  type: OtpType.totp,
  secret: _secret,
  issuer: 'Example',
  accountName: name,
);

OtpParameters _hotp(String name) =>
    OtpParameters(type: OtpType.hotp, secret: _secret, accountName: name);

void main() {
  late InMemorySecretStore secrets;
  late InMemoryVaultFileStore files;

  AccountRepository newRepository() => AccountRepository(
    keys: StoredKeyWrapper(secrets),
    files: files,
    now: () => DateTime.utc(2026, 11, 7, 12),
  );

  setUp(() {
    secrets = InMemorySecretStore();
    files = InMemoryVaultFileStore();
  });

  group('first run and unlock', () {
    test('creates a key and an empty encrypted vault', () async {
      final repo = newRepository();
      final state = await repo.unlock();

      expect(state, isA<VaultUnlocked>());
      expect(repo.accounts, isEmpty);
      expect(secrets.values, hasLength(1));
      final key = await StoredKeyWrapper(secrets).readKey();
      expect(
        VaultCodec.decode(await VaultCipher.decrypt(files.data!, key!)),
        isEmpty,
      );
    });

    test('accounts survive lock/unlock and a fresh repository', () async {
      final repo = newRepository();
      await repo.unlock();
      await repo.add(_totp('alice'));
      repo.lock();
      expect(repo.state, isA<VaultLocked>());
      expect(() => repo.accounts, throwsStateError);

      await repo.unlock();
      expect(repo.accounts.single.accountName, 'alice');

      final fresh = newRepository();
      await fresh.unlock();
      expect(fresh.accounts.single.accountName, 'alice');
    });

    test('a stale key with no vault (iOS reinstall) starts fresh', () async {
      await StoredKeyWrapper(secrets).storeKey(VaultCipher.newKey());
      final stale = secrets.values.values.single;

      final repo = newRepository();
      expect(await repo.unlock(), isA<VaultUnlocked>());
      expect(repo.accounts, isEmpty);
      expect(secrets.values.values.single, isNot(stale));
      expect(files.data, isNotNull);
    });

    test('unlock is idempotent', () async {
      final repo = newRepository();
      await repo.unlock();
      await repo.add(_totp('a'));
      final writes = files.writeCount;
      await repo.unlock();
      expect(files.writeCount, writes);
      expect(repo.accounts, hasLength(1));
    });
  });

  group('unreadable vault', () {
    Future<void> seedVault() async {
      final repo = newRepository();
      await repo.unlock();
      await repo.add(_totp('precious'));
      await repo.dispose();
    }

    test('a missing key never overwrites the vault', () async {
      await seedVault();
      final before = List.of(files.data!);
      secrets.values.clear();

      final repo = newRepository();
      final state = await repo.unlock();
      expect(state, isA<VaultUnreadable>());
      expect(
        (state as VaultUnreadable).reason,
        VaultUnreadableReason.keyMissing,
      );
      expect(files.data, before);
      expect(secrets.values, isEmpty);
    });

    test('the wrong key reports decryptFailed', () async {
      await seedVault();
      await StoredKeyWrapper(secrets).storeKey(VaultCipher.newKey());
      final state = await newRepository().unlock();
      expect(
        (state as VaultUnreadable).reason,
        VaultUnreadableReason.decryptFailed,
      );
    });

    test('a tampered file reports decryptFailed', () async {
      await seedVault();
      files.data![30] ^= 0xff;
      final state = await newRepository().unlock();
      expect(
        (state as VaultUnreadable).reason,
        VaultUnreadableReason.decryptFailed,
      );
    });

    test(
      'valid encryption around invalid content reports corruptContent',
      () async {
        await seedVault();
        final key = await StoredKeyWrapper(secrets).readKey();
        files.data = await VaultCipher.encrypt(
          utf8.encode('{"schema":9}'),
          key!,
        );
        final state = await newRepository().unlock();
        expect(
          (state as VaultUnreadable).reason,
          VaultUnreadableReason.corruptContent,
        );
      },
    );

    test('mutations are refused while unreadable', () async {
      await seedVault();
      secrets.values.clear();
      final repo = newRepository();
      await repo.unlock();
      expect(() => repo.add(_totp('x')), throwsStateError);
    });

    test('reset keeps the old file and starts an empty vault', () async {
      await seedVault();
      final before = List.of(files.data!);
      secrets.values.clear();

      final repo = newRepository();
      await repo.unlock();
      final movedTo = await repo.resetUnreadableVault();

      expect(movedTo, isNotEmpty);
      expect(files.quarantined.single, before);
      expect(repo.state, isA<VaultUnlocked>());
      expect(repo.accounts, isEmpty);
    });

    test('reset is refused unless the vault is unreadable', () async {
      final repo = newRepository();
      await repo.unlock();
      expect(repo.resetUnreadableVault, throwsStateError);
    });
  });

  group('mutations', () {
    late AccountRepository repo;

    setUp(() async {
      repo = newRepository();
      await repo.unlock();
    });

    Future<List<String>> persistedNames() async {
      final fresh = newRepository();
      await fresh.unlock();
      return [for (final a in fresh.accounts) a.accountName];
    }

    test('add assigns an id and creation time and persists', () async {
      final account = await repo.add(_totp('alice'));
      expect(account.id, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(account.createdAt, DateTime.utc(2026, 11, 7, 12));
      expect(await persistedNames(), ['alice']);
    });

    test('rename changes only the names', () async {
      final a = await repo.add(_totp('alice'));
      final renamed = await repo.rename(
        a.id,
        issuer: 'Work',
        accountName: 'al',
      );
      expect((renamed.issuer, renamed.accountName), ('Work', 'al'));
      expect(renamed.secret, a.secret);
      expect(await persistedNames(), ['al']);
    });

    test('delete removes and persists', () async {
      final a = await repo.add(_totp('a'));
      await repo.add(_totp('b'));
      await repo.delete(a.id);
      expect(await persistedNames(), ['b']);
    });

    test('reorder moves an account and persists', () async {
      for (final n in ['a', 'b', 'c']) {
        await repo.add(_totp(n));
      }
      await repo.reorder(0, 2);
      expect(await persistedNames(), ['b', 'c', 'a']);
      await repo.reorder(2, 0);
      expect(await persistedNames(), ['a', 'b', 'c']);
      expect(() => repo.reorder(0, 3), throwsRangeError);
    });

    test('unknown ids are rejected', () {
      expect(() => repo.delete('nope'), throwsStateError);
      expect(() => repo.rename('nope', issuer: 'x'), throwsStateError);
    });

    test('incrementCounter persists before returning', () async {
      final h = await repo.add(_hotp('h'));
      final next = await repo.incrementCounter(h.id);
      expect(next, 1);

      final fresh = newRepository();
      await fresh.unlock();
      expect(fresh.accounts.single.counter, 1);
      expect(
        Hotp.generate(fresh.accounts.single.secret, counter: next),
        '287082', // RFC 4226 counter 1
      );
    });

    test('incrementCounter rejects TOTP accounts', () async {
      final t = await repo.add(_totp('t'));
      expect(() => repo.incrementCounter(t.id), throwsStateError);
    });

    test('a failed write leaves memory unchanged', () async {
      await repo.add(_totp('kept'));
      files.failNextWrite = const FileSystemException('disk full');
      await expectLater(
        repo.add(_totp('lost')),
        throwsA(isA<FileSystemException>()),
      );
      expect(repo.accounts.map((a) => a.accountName), ['kept']);
      expect(await persistedNames(), ['kept']);
    });

    test('concurrent mutations are applied one at a time', () async {
      await Future.wait([for (var i = 0; i < 10; i++) repo.add(_totp('n$i'))]);
      expect(repo.accounts, hasLength(10));
      expect(await persistedNames(), hasLength(10));
    });

    test('emits state changes', () async {
      final seen = <VaultState>[];
      final sub = repo.states.listen(seen.add);
      await repo.add(_totp('a'));
      repo.lock();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen.map((s) => s.runtimeType), [VaultUnlocked, VaultLocked]);
    });
  });

  group('locking during in-flight work', () {
    test('a write in flight still uses the real key after lock', () async {
      final repo = newRepository();
      await repo.unlock();
      files.writeGate = Completer<void>();
      final pending = repo.add(_totp('mid-lock'));
      await Future<void>.delayed(Duration.zero);
      repo.lock();
      files.writeGate!.complete();
      await pending;

      expect(repo.state, isA<VaultLocked>());
      final fresh = newRepository();
      await fresh.unlock();
      expect(fresh.accounts.single.accountName, 'mid-lock');
    });

    test('an unlock in flight does not unlock after lock()', () async {
      final seed = newRepository();
      await seed.unlock();
      await seed.add(_totp('a'));

      final repo = newRepository();
      final pending = repo.unlock();
      repo.lock();
      await pending;
      expect(repo.state, isA<VaultLocked>());
      expect(() => repo.accounts, throwsStateError);
    });

    test(
      'an unreadable unlock in flight does not publish after lock()',
      () async {
        final seed = newRepository();
        await seed.unlock();
        await seed.add(_totp('a'));
        secrets.values.clear(); // key gone -> would be keyMissing

        final repo = newRepository();
        final seen = <VaultState>[];
        final sub = repo.states.listen(seen.add);
        final pending = repo.unlock();
        repo.lock();
        await pending;
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(repo.state, isA<VaultLocked>());
        expect(seen, isEmpty);
      },
    );
  });

  group('key hygiene', () {
    test('a stale key is wiped when no vault exists', () async {
      await StoredKeyWrapper(secrets).storeKey(VaultCipher.newKey());
      final keys = _RecordingKeyWrapper(StoredKeyWrapper(secrets));
      final repo = AccountRepository(keys: keys, files: files);

      await repo.unlock();

      expect(keys.read.single, everyElement(0));
    });

    test('a new key is wiped when the first vault write fails', () async {
      final keys = _RecordingKeyWrapper(StoredKeyWrapper(secrets));
      final repo = AccountRepository(keys: keys, files: files);
      files.failNextWrite = const FileSystemException('disk full');

      await expectLater(repo.unlock(), throwsA(isA<FileSystemException>()));

      expect(keys.stored.single, everyElement(0));
      expect(repo.state, isA<VaultLocked>());
    });
  });
}

/// Records the key buffers it hands out and receives, so tests can check
/// that the repository zeroes them.
final class _RecordingKeyWrapper implements KeyWrapper {
  _RecordingKeyWrapper(this._inner);

  final KeyWrapper _inner;
  final List<Uint8List> read = [];
  final List<Uint8List> stored = [];

  @override
  Future<Uint8List?> readKey() async {
    final key = await _inner.readKey();
    if (key != null) read.add(key);
    return key;
  }

  @override
  Future<void> storeKey(Uint8List key) {
    stored.add(key);
    return _inner.storeKey(key);
  }

  @override
  Future<void> deleteKey() => _inner.deleteKey();
}
