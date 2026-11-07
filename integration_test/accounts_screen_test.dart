import 'dart:convert';
import 'dart:io';

import 'package:cypher/app/app.dart';
import 'package:cypher/app/system_clock.dart';
import 'package:cypher/app/vault_bootstrap.dart';
import 'package:cypher/core/otp/otp_parameters.dart';
import 'package:cypher/core/otp/otp_secret.dart';
import 'package:cypher/core/otp/otp_types.dart';
import 'package:cypher/core/security/key_wrapper.dart';
import 'package:cypher/core/security/platform/flutter_secret_store.dart';
import 'package:cypher/core/security/platform/flutter_secure_clipboard.dart';
import 'package:cypher/core/security/platform/local_auth_biometrics.dart';
import 'package:cypher/data/account_repository.dart';
import 'package:cypher/data/lock_service.dart';
import 'package:cypher/features/accounts/accounts_strings.dart';
import 'package:cypher/features/shared/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// The accounts screen on a real device: real Keystore, file system, clock
/// and the native clipboard channel. Uses its own vault and key name.
///
/// Screenshots are written to the app's files directory under `screenshots/`
/// (pull with `adb exec-out run-as com.ruizchristian.cypherauth cat files/screenshots/…`).
/// The countdown rings animate continuously while codes are visible, so the
/// screen never "settles"; wait a fixed time instead of pumpAndSettle.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const directoryName = 'vault_accounts_ui_test';
  const keyName = 'cypher.vault.dek.accounts-ui-test';
  const lockNamespace = 'cypher.lock.accounts-ui-test';

  Future<void> cleanUp() async {
    for (final key in ['pin', 'settings', 'throttle']) {
      await const FlutterSecretStore().delete('$lockNamespace.$key.v1');
    }
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

  OtpParameters account(
    OtpType type,
    String issuer,
    String name, {
    int digits = 6,
    HashAlgorithm algorithm = HashAlgorithm.sha1,
    String seed = '12345678901234567890',
  }) => OtpParameters(
    type: type,
    secret: OtpSecret(utf8.encode(seed)),
    issuer: issuer,
    accountName: name,
    digits: digits,
    algorithm: algorithm,
  );

  Future<AccountRepository> seededRepository() async {
    final repo = await openAccountRepository(
      directoryName: directoryName,
      keyName: keyName,
    );
    await repo.unlock();
    await repo.add(account(OtpType.totp, 'GitHub', 'octocat'));
    await repo.add(
      account(
        OtpType.totp,
        'Google',
        'alice@example.com',
        algorithm: HashAlgorithm.sha256,
        seed: '12345678901234567890123456789012',
      ),
    );
    await repo.add(account(OtpType.totp, 'AWS', 'root', digits: 8));
    await repo.add(account(OtpType.hotp, 'Bank', 'card holder'));
    repo.lock();
    return repo;
  }

  Future<void> pumpApp(
    WidgetTester tester,
    AccountRepository repo,
    FlutterSecureClipboard clipboard,
  ) async {
    // The app now sits behind the lock: set a PIN (which opens the vault)
    // before showing the accounts screen.
    final lock = LockService(
      store: const FlutterSecretStore(),
      repository: repo,
      biometrics: LocalAuthBiometrics(),
      keyNamespace: lockNamespace,
    );
    await lock.initialize();
    await lock.createPin('482913');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(const SystemClock()),
          accountRepositoryProvider.overrideWithValue(repo),
          lockServiceProvider.overrideWithValue(lock),
          secureClipboardProvider.overrideWithValue(clipboard),
        ],
        child: const CypherApp(),
      ),
    );
    await settle(tester);
  }

  Future<void> screenshot(String name) async {
    final bytes = await binding.takeScreenshot(name);
    final support = await getApplicationSupportDirectory();
    final file = File(
      '${support.path}${Platform.pathSeparator}screenshots'
      '${Platform.pathSeparator}$name.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  testWidgets('shows live codes, copies through the native channel, and '
      'clears the clipboard', (tester) async {
    final repo = await seededRepository();
    final clipboard = FlutterSecureClipboard(
      clearAfter: const Duration(seconds: 2),
    );
    await pumpApp(tester, repo, clipboard);

    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('AWS'), findsOneWidget);
    expect(find.text(AccountsStrings.hotpHidden), findsOneWidget);
    final sixDigit = find.textContaining(RegExp(r'^\d{3} \d{3}$'));
    final eightDigit = find.textContaining(RegExp(r'^\d{4} \d{4}$'));
    expect(sixDigit, findsNWidgets(2));
    expect(eightDigit, findsOneWidget);

    // Copy the GitHub code via the Kotlin channel and read it back.
    final shown = tester.widget<Text>(sixDigit.first).data!;
    await tester.tap(sixDigit.first);
    await settle(tester);
    final copied = await Clipboard.getData(Clipboard.kTextPlain);
    // The code may have rolled over between reading and tapping; either way
    // the clipboard holds 6 digits and never a secret.
    expect(copied?.text, matches(RegExp(r'^\d{6}$')));
    expect(
      copied!.text == shown.replaceAll(' ', '') ||
          tester.widget<Text>(sixDigit.first).data!.replaceAll(' ', '') ==
              copied.text,
      isTrue,
    );

    await binding.convertFlutterSurfaceToImage();
    await settle(tester);
    await screenshot('accounts_copied');

    // After clearAfter the code is gone from the clipboard.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    final afterClear = await Clipboard.getData(Clipboard.kTextPlain);
    expect(afterClear?.text ?? '', isEmpty);

    // HOTP: reveal the next code.
    await tester.tap(find.byTooltip(AccountsStrings.nextCode));
    await settle(tester);
    expect(find.text('287 082'), findsOneWidget); // RFC 4226, counter 1
    await screenshot('accounts_hotp');

    clipboard.dispose();
    await repo.dispose();
  });

  testWidgets('does not clear something the user copied afterwards', (
    tester,
  ) async {
    final repo = await seededRepository();
    final clipboard = FlutterSecureClipboard(
      clearAfter: const Duration(seconds: 2),
    );
    await pumpApp(tester, repo, clipboard);

    await tester.tap(find.textContaining(RegExp(r'^\d{3} \d{3}$')).first);
    await settle(tester);
    await Clipboard.setData(const ClipboardData(text: 'my own note'));

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    final after = await Clipboard.getData(Clipboard.kTextPlain);
    expect(after?.text, 'my own note');

    await Clipboard.setData(const ClipboardData(text: ''));
    clipboard.dispose();
    await repo.dispose();
  });
}
