import 'dart:convert';
import 'dart:io';

import 'package:cypher/app/vault_bootstrap.dart';
import 'package:cypher/core/otp/hotp.dart';
import 'package:cypher/core/otp/otp_parameters.dart';
import 'package:cypher/core/otp/otp_secret.dart';
import 'package:cypher/core/otp/otp_types.dart';
import 'package:cypher/core/security/key_wrapper.dart';
import 'package:cypher/core/security/platform/flutter_secret_store.dart';
import 'package:cypher/data/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Export and restore with the real Argon2id (64 MiB × 3) on a device, and
/// report how long each takes. Uses its own vaults.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const store = FlutterSecretStore();
  const dirs = ['vault_backup_src', 'vault_backup_dst'];
  const keys = ['cypher.vault.dek.backup-src', 'cypher.vault.dek.backup-dst'];

  Future<void> cleanUp() async {
    final support = await getApplicationSupportDirectory();
    for (var i = 0; i < 2; i++) {
      await StoredKeyWrapper(store, storageKey: keys[i]).deleteKey();
      final dir = Directory(
        '${support.path}${Platform.pathSeparator}${dirs[i]}',
      );
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    await store.delete('cypher.backup.last.v1.test');
  }

  setUp(cleanUp);
  tearDown(cleanUp);

  testWidgets('a backup made on one vault restores into another', (
    tester,
  ) async {
    final source = await openAccountRepository(
      directoryName: dirs[0],
      keyName: keys[0],
    );
    await source.unlock();
    await source.add(
      OtpParameters(
        type: OtpType.hotp,
        secret: OtpSecret(utf8.encode('12345678901234567890')),
        issuer: 'Example',
        accountName: 'alice',
        counter: 7,
      ),
    );

    final exporter = BackupService(repository: source, store: store);
    final sw = Stopwatch()..start();
    final file = await exporter.export('correct horse battery staple');
    final exportMs = sw.elapsedMilliseconds;
    expect(ascii.decode(file.sublist(0, 6)), 'CYPHER');

    sw.reset();
    final accounts = await exporter.readBackup(
      file,
      'correct horse battery staple',
    );
    final importMs = sw.elapsedMilliseconds;

    final target = await openAccountRepository(
      directoryName: dirs[1],
      keyName: keys[1],
    );
    await target.unlock();
    await target.addAll(accounts);
    final restored = target.accounts.single;
    expect((restored.issuer, restored.counter), ('Example', 7));
    expect(Hotp.generate(restored.secret, counter: 0), '755224');

    // ignore: avoid_print
    print('BACKUP_TIMING export=${exportMs}ms import=${importMs}ms');
    await source.dispose();
    await target.dispose();
  });
}
