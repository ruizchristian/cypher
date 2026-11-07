import 'dart:io';

import 'package:cypher/app/app.dart';
import 'package:cypher/app/system_clock.dart';
import 'package:cypher/app/vault_bootstrap.dart';
import 'package:cypher/core/security/key_wrapper.dart';
import 'package:cypher/core/security/platform/flutter_secret_store.dart';
import 'package:cypher/core/security/platform/flutter_secure_clipboard.dart';
import 'package:cypher/core/security/platform/local_auth_biometrics.dart';
import 'package:cypher/data/lock_service.dart';
import 'package:cypher/features/accounts/accounts_screen.dart';
import 'package:cypher/features/accounts/accounts_strings.dart';
import 'package:cypher/features/lock/lock_strings.dart';
import 'package:cypher/features/shared/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// The real lock on a device: Keystore-backed storage, the real Argon2id cost
/// on a background isolate, and the real biometrics adapter. Uses its own
/// vault and key namespace.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const vaultDir = 'vault_lock_test';
  const vaultKey = 'cypher.vault.dek.lock-test';
  const namespace = 'cypher.lock.lock-test';
  const store = FlutterSecretStore();

  Future<void> cleanUp() async {
    for (final key in ['pin', 'settings', 'throttle']) {
      await store.delete('$namespace.$key.v1');
    }
    await StoredKeyWrapper(store, storageKey: vaultKey).deleteKey();
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}$vaultDir');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  setUp(cleanUp);
  tearDown(cleanUp);

  Future<void> enterPin(WidgetTester tester, String pin, String submit) async {
    for (final digit in pin.split('')) {
      final key = find.descendant(
        of: find.byType(TextButton),
        matching: find.text(digit),
      );
      await tester.ensureVisible(key);
      await tester.tap(key);
      await tester.pump();
    }
    // With a known PIN length the pad checks on the last digit (no button).
    final button = find.widgetWithText(FilledButton, submit);
    if (button.evaluate().isNotEmpty) {
      await tester.ensureVisible(button);
      await tester.tap(button);
    }
    // The real Argon2id check runs on another isolate; give it time.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'set a PIN, lock, reject a wrong PIN, unlock with the right one',
    (tester) async {
      final repo = await openAccountRepository(
        directoryName: vaultDir,
        keyName: vaultKey,
      );
      final lock = LockService(
        store: store,
        repository: repo,
        biometrics: LocalAuthBiometrics(),
        keyNamespace: namespace,
      );
      await lock.initialize();
      final clipboard = FlutterSecureClipboard();
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
      await tester.pumpAndSettle();

      // First run: create and confirm the PIN. The emulator has no enrolled
      // biometrics, so no biometric offer appears.
      expect(find.text(LockStrings.createTitle), findsOneWidget);
      await enterPin(tester, '482913', LockStrings.continueLabel);
      await enterPin(tester, '482913', LockStrings.continueLabel);
      expect(find.text(LockStrings.biometricOfferTitle), findsNothing);
      expect(find.byType(AccountsScreen), findsOneWidget);

      // The PIN rests only as an Argon2id hash in the Keystore-backed store.
      final stored = await store.read('$namespace.pin.v1');
      expect(stored, startsWith(r'v1$argon2id$'));
      expect(stored, isNot(contains('482913')));

      await tester.tap(find.byTooltip(AccountsStrings.lockNow));
      await tester.pumpAndSettle();
      expect(find.text(LockStrings.unlockTitle), findsOneWidget);
      // The length is known now, so there is no Unlock button to press.
      expect(
        find.widgetWithText(FilledButton, LockStrings.unlock),
        findsNothing,
      );

      await enterPin(tester, '000000', LockStrings.unlock);
      expect(find.text(LockStrings.wrongPin(3)), findsOneWidget);
      expect(
        await store.read('$namespace.throttle.v1'),
        contains('"failures":1'),
      );

      await enterPin(tester, '482913', LockStrings.unlock);
      expect(find.byType(AccountsScreen), findsOneWidget);

      clipboard.dispose();
      await lock.dispose();
      await repo.dispose();
    },
  );
}
