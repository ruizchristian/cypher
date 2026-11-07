import 'dart:convert';

import 'package:cypher/core/otp/otp_parameters.dart';
import 'package:cypher/core/otp/otp_secret.dart';
import 'package:cypher/core/otp/otp_types.dart';
import 'package:cypher/core/security/backup_cipher.dart';
import 'package:cypher/core/security/key_wrapper.dart';
import 'package:cypher/data/account_repository.dart';
import 'package:cypher/data/backup_service.dart';
import 'package:cypher/data/vault_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_clock.dart';
import '../fakes/in_memory_secret_store.dart';
import '../fakes/in_memory_vault_file_store.dart';

const _cheap = BackupKdfParams.pbkdf2(iterations: 1);
const _password = 'correct horse battery staple';

void main() {
  late InMemorySecretStore store;
  late AccountRepository repo;
  late FakeClock clock;

  BackupService service() => BackupService(
    repository: repo,
    store: store,
    now: clock.now,
    params: _cheap,
    inIsolate: false,
  );

  setUp(() async {
    store = InMemorySecretStore();
    clock = FakeClock.atUnixSeconds(1_700_000_000);
    repo = AccountRepository(
      keys: StoredKeyWrapper(store),
      files: InMemoryVaultFileStore(),
    );
    await repo.unlock();
    await repo.addAll([
      OtpParameters(
        type: OtpType.totp,
        secret: OtpSecret(utf8.encode('12345678901234567890')),
        issuer: 'GitHub',
        accountName: 'octocat',
        algorithm: HashAlgorithm.sha256,
        digits: 8,
        period: 60,
      ),
      OtpParameters(
        type: OtpType.hotp,
        secret: OtpSecret([1, 2, 3, 4, 5]),
        issuer: 'Bank',
        counter: 42,
      ),
    ]);
  });

  test('export then read returns every account and setting', () async {
    final backup = service();
    final file = await backup.export(_password);
    final read = await backup.readBackup(file, _password);

    expect(read, hasLength(2));
    final (a, b) = (read[0], read[1]);
    expect(
      (a.issuer, a.accountName, a.type, a.algorithm, a.digits, a.period),
      ('GitHub', 'octocat', OtpType.totp, HashAlgorithm.sha256, 8, 60),
    );
    expect(a.secret, repo.accounts[0].secret);
    expect((b.issuer, b.type, b.counter), ('Bank', OtpType.hotp, 42));
  });

  test('refuses a password that is too short', () {
    expect(() => service().export('short'), throwsArgumentError);
  });

  test('export needs the vault unlocked', () async {
    repo.lock();
    expect(() => service().export(_password), throwsStateError);
  });

  test('read failures map to user-facing problems', () async {
    final backup = service();
    final file = await backup.export(_password);
    Future<BackupProblem> problem(Future<void> f) async {
      try {
        await f;
      } on BackupReadException catch (e) {
        return e.problem;
      }
      fail('expected failure');
    }

    expect(
      await problem(backup.readBackup(file, 'wrong password')),
      BackupProblem.wrongPasswordOrDamaged,
    );
    expect(
      await problem(backup.readBackup(utf8.encode('hello world, not it'), 'x')),
      BackupProblem.notABackup,
    );
  });

  test('a valid file with too many accounts is refused', () async {
    final many = [
      for (var i = 0; i <= BackupService.maxImportAccounts; i++)
        ...repo.accounts.take(1),
    ];
    // Unique ids are required by the codec; reuse via a fresh encode.
    final json = jsonDecode(utf8.decode(VaultCodec.encode(many))) as Map;
    final list = json['accounts'] as List;
    for (var i = 0; i < list.length; i++) {
      (list[i] as Map)['id'] = 'id$i';
    }
    final file = await BackupCipher.encrypt(
      utf8.encode(jsonEncode(json)),
      _password,
      params: _cheap,
      inIsolate: false,
    );
    expect(
      () => service().readBackup(file, _password),
      throwsA(
        isA<BackupReadException>().having(
          (e) => e.problem,
          'problem',
          BackupProblem.tooManyAccounts,
        ),
      ),
    );
  });

  test('records the last backup and survives a restart', () async {
    final backup = service();
    await backup.initialize();
    expect(backup.lastBackupAt, isNull);
    final changes = <DateTime?>[];
    final sub = backup.lastBackupChanges.listen(changes.add);
    await backup.recordBackupSaved();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(changes, [clock.now().toUtc()]);

    final again = service();
    await again.initialize();
    expect(again.lastBackupAt, clock.now().toUtc());
  });

  test('the exported file never contains the secret in the clear', () async {
    final file = await service().export(_password);
    final text = latin1.decode(file);
    expect(text, isNot(contains('GEZDGNBV'))); // Base32 of the secret
    expect(text, isNot(contains('GitHub')));
  });
}
