import 'dart:convert';
import 'dart:io';

import 'package:cypher/app/vault_bootstrap.dart';
import 'package:cypher/core/otp/hotp.dart';
import 'package:cypher/core/otp/otp_parameters.dart';
import 'package:cypher/core/otp/otp_secret.dart';
import 'package:cypher/core/otp/otp_types.dart';
import 'package:cypher/core/security/key_wrapper.dart';
import 'package:cypher/core/security/platform/flutter_secret_store.dart';
import 'package:cypher/data/account_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Exercises the real Keystore/Keychain adapter and file system on a device.
/// Uses its own key name and directory so it never touches a real vault.
///
/// Run: `flutter test integration_test -d <device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const directoryName = 'vault_integration_test';
  const keyName = 'cypher.vault.dek.integration-test';

  Future<void> cleanUp() async {
    await StoredKeyWrapper(
      const FlutterSecretStore(),
      storageKey: keyName,
    ).deleteKey();
    final support = await getApplicationSupportDirectory();
    final dir = Directory(
      '${support.path}${Platform.pathSeparator}$directoryName',
    );
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  setUp(cleanUp);
  tearDown(cleanUp);

  Future<AccountRepository> open() =>
      openAccountRepository(directoryName: directoryName, keyName: keyName);

  testWidgets('accounts persist through the real Keystore and file system', (
    tester,
  ) async {
    final secret = OtpSecret(utf8.encode('12345678901234567890'));

    final first = await open();
    expect(await first.unlock(), isA<VaultUnlocked>());
    final added = await first.add(
      OtpParameters(type: OtpType.hotp, secret: secret, accountName: 'device'),
    );
    expect(await first.incrementCounter(added.id), 1);
    first.lock();
    await first.dispose();

    // A brand-new repository reads the key back from the Keystore and
    // decrypts the file written above.
    final second = await open();
    expect(await second.unlock(), isA<VaultUnlocked>());
    final stored = second.accounts.single;
    expect(stored.accountName, 'device');
    expect(stored.counter, 1);
    expect(Hotp.generate(stored.secret, counter: stored.counter), '287082');

    // The file on disk is ciphertext, not JSON.
    final support = await getApplicationSupportDirectory();
    final raw = await File(
      '${support.path}${Platform.pathSeparator}$directoryName'
      '${Platform.pathSeparator}vault.bin',
    ).readAsBytes();
    expect(ascii.decode(raw.sublist(0, 4)), 'CYVT');
    expect(utf8.decode(raw, allowMalformed: true), isNot(contains('device')));
    await second.dispose();
  });

  testWidgets('a vault whose key was deleted is reported, not overwritten', (
    tester,
  ) async {
    final repo = await open();
    await repo.unlock();
    await repo.add(
      OtpParameters(
        type: OtpType.totp,
        secret: OtpSecret(utf8.encode('12345678901234567890')),
      ),
    );
    await repo.dispose();
    await StoredKeyWrapper(
      const FlutterSecretStore(),
      storageKey: keyName,
    ).deleteKey();

    final reopened = await open();
    final state = await reopened.unlock();
    expect(state, isA<VaultUnreadable>());
    expect((state as VaultUnreadable).reason, VaultUnreadableReason.keyMissing);
    await reopened.dispose();
  });
}
