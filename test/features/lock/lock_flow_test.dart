import 'package:cypher/core/security/biometric_auth.dart';
import 'package:cypher/data/lock_service.dart';
import 'package:cypher/features/accounts/accounts_screen.dart';
import 'package:cypher/features/accounts/accounts_strings.dart';
import 'package:cypher/features/lock/lock_strings.dart';
import 'package:cypher/features/lock/privacy_cover.dart';
import 'package:cypher/features/settings/settings_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

/// Types [pin] on the on-screen pad and presses [submit].
/// Each key is scrolled into view first: on short screens (and the 800x600
/// test surface) the pad scrolls, as it would for a user.
Future<void> _enterPin(WidgetTester tester, String pin, String submit) async {
  for (final digit in pin.split('')) {
    final key = find.descendant(
      of: find.byType(TextButton),
      matching: find.text(digit),
    );
    await tester.ensureVisible(key);
    await tester.tap(key);
    await tester.pump();
  }
  // When the PIN length is known the pad checks on the last digit and shows
  // no button; otherwise press it.
  final button = find.widgetWithText(FilledButton, submit);
  if (button.evaluate().isNotEmpty) {
    await tester.ensureVisible(button);
    await tester.tap(button);
  }
  await tester.pumpAndSettle();
}

/// Walks the app lifecycle the way the platform does.
Future<void> _background(WidgetTester tester) async {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pump();
  }
}

Future<void> _foreground(WidgetTester tester) async {
  for (final s in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pump();
  }
}

void main() {
  group('first run', () {
    testWidgets(
      'create and confirm a PIN, accept biometrics, land on accounts',
      (tester) async {
        final app = AppHarness();
        await app.pump(tester, start: LockStart.firstRun);
        expect(find.text(LockStrings.noRecovery), findsOneWidget);

        await _enterPin(tester, '482913', LockStrings.continueLabel);
        expect(find.text(LockStrings.confirmTitle), findsOneWidget);
        await _enterPin(tester, '482913', LockStrings.continueLabel);

        expect(find.text(LockStrings.biometricOfferTitle), findsOneWidget);
        await tester.tap(find.text(LockStrings.biometricOfferYes));
        await tester.pumpAndSettle();

        expect(find.byType(AccountsScreen), findsOneWidget);
        expect(app.lock.settings.biometricsEnabled, isTrue);
        expect(app.biometrics.prompts, 1); // the enabling check
        await app.unmount(tester);
      },
    );

    testWidgets('a mismatched confirmation starts over', (tester) async {
      final app = AppHarness();
      app.biometrics.available = false;
      await app.pump(tester, start: LockStart.firstRun);

      await _enterPin(tester, '482913', LockStrings.continueLabel);
      await _enterPin(tester, '111111', LockStrings.continueLabel);
      expect(find.text(LockStrings.mismatch), findsOneWidget);
      expect(find.text(LockStrings.createTitle), findsOneWidget);
      expect(app.lock.state, isA<LockNeedsSetup>());
      await app.unmount(tester);
    });

    testWidgets('the continue button needs at least 6 digits', (tester) async {
      final app = AppHarness();
      await app.pump(tester, start: LockStart.firstRun);
      for (final d in '12345'.split('')) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, LockStrings.continueLabel),
      );
      expect(button.onPressed, isNull);
      await app.unmount(tester);
    });
  });

  group('unlock', () {
    testWidgets('checks on the last digit, with no Unlock button', (
      tester,
    ) async {
      final app = AppHarness();
      await app.pump(tester, start: LockStart.locked);
      expect(
        find.widgetWithText(FilledButton, LockStrings.unlock),
        findsNothing,
      );
      for (final d in testPin.split('')) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byType(AccountsScreen), findsOneWidget);
      await app.unmount(tester);
    });

    testWidgets('an older PIN shows the button once, then goes automatic', (
      tester,
    ) async {
      final app = AppHarness();
      await app.pump(tester, start: LockStart.locked, legacyPin: true);
      expect(
        find.widgetWithText(FilledButton, LockStrings.unlock),
        findsOneWidget,
      );
      await _enterPin(tester, testPin, LockStrings.unlock);
      expect(find.byType(AccountsScreen), findsOneWidget);

      app.lock.lock();
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, LockStrings.unlock),
        findsNothing,
      );
      await app.unmount(tester);
    });

    testWidgets('nothing about accounts is shown while locked', (tester) async {
      final app = AppHarness();
      await app.seed([hotpAccount('SecretBank')]);
      await app.pump(tester, start: LockStart.locked);

      expect(find.text(LockStrings.unlockTitle), findsOneWidget);
      expect(find.text('SecretBank'), findsNothing);
      expect(find.byType(AccountsScreen), findsNothing);

      await _enterPin(tester, testPin, LockStrings.unlock);
      expect(find.text('SecretBank'), findsOneWidget);
      await app.unmount(tester);
    });

    testWidgets('wrong PINs warn, then lock the pad for 30 s', (tester) async {
      final app = AppHarness();
      await app.pump(tester, start: LockStart.locked);

      await _enterPin(tester, '000000', LockStrings.unlock);
      expect(find.text(LockStrings.wrongPin(3)), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await _enterPin(tester, '000000', LockStrings.unlock);
      }
      expect(find.textContaining('Too many wrong PINs'), findsOneWidget);

      // The pad ignores input during the wait.
      await tester.tap(find.text('4'));
      await tester.pump();
      expect(app.lock.state, isA<LockLocked>());

      app.clock.advance(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Too many wrong PINs'), findsNothing);
      await _enterPin(tester, testPin, LockStrings.unlock);
      expect(find.byType(AccountsScreen), findsOneWidget);
      await app.unmount(tester);
    });

    testWidgets('biometrics are offered automatically when enabled', (
      tester,
    ) async {
      final app = AppHarness();
      await app.pump(tester);
      await app.lock.setBiometricsEnabled(true, reason: 'r');
      app.lock.lock();
      await app.unmount(tester);

      // Restart: the lock screen prompts once on its own.
      final prompts = app.biometrics.prompts;
      await app.pump(tester, start: LockStart.locked);
      await tester.pumpAndSettle();
      expect(app.biometrics.prompts, prompts + 1);
      expect(find.byType(AccountsScreen), findsOneWidget);
      await app.unmount(tester);
    });

    testWidgets('a cancelled prompt leaves the PIN pad usable', (tester) async {
      final app = AppHarness();
      await app.pump(tester);
      await app.lock.setBiometricsEnabled(true, reason: 'r');
      app.lock.lock();
      await app.unmount(tester);

      app.biometrics.nextResult = BiometricResult.cancelled;
      await app.pump(tester, start: LockStart.locked);
      await tester.pumpAndSettle();
      expect(find.text(LockStrings.unlockTitle), findsOneWidget);
      expect(find.byTooltip('Use fingerprint or face'), findsOneWidget);
      await _enterPin(tester, testPin, LockStrings.unlock);
      expect(find.byType(AccountsScreen), findsOneWidget);
      await app.unmount(tester);
    });

    testWidgets('forgot PIN explains there is no recovery', (tester) async {
      final app = AppHarness();
      await app.pump(tester, start: LockStart.locked);
      await tester.tap(find.text(LockStrings.forgotPin));
      await tester.pumpAndSettle();
      expect(find.text(LockStrings.forgotPinBody), findsOneWidget);
      await app.unmount(tester);
    });
  });

  group('auto-lock and privacy', () {
    testWidgets('a quick trip away stays unlocked; a long one locks', (
      tester,
    ) async {
      final app = AppHarness();
      await app.seed([hotpAccount('Bank')]);
      await app.pump(tester);

      await _background(tester);
      expect(find.byType(PrivacyCover), findsOneWidget);
      app.clock.advance(const Duration(seconds: 10));
      await _foreground(tester);
      expect(find.byType(PrivacyCover), findsNothing);
      expect(find.text('Bank'), findsOneWidget);

      await _background(tester);
      app.clock.advance(const Duration(seconds: 30));
      await _foreground(tester);
      await tester.pumpAndSettle();
      expect(find.text(LockStrings.unlockTitle), findsOneWidget);
      expect(find.text('Bank'), findsNothing);
      await app.unmount(tester);
    });

    testWidgets('inactive (e.g. app switcher) covers without locking', (
      tester,
    ) async {
      final app = AppHarness();
      await app.pump(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byType(PrivacyCover), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byType(PrivacyCover), findsNothing);
      expect(app.lock.state, isA<LockUnlocked>());
      await app.unmount(tester);
    });

    testWidgets('locking closes open screens; unlocking starts at home', (
      tester,
    ) async {
      final app = AppHarness();
      await app.pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(AccountsStrings.settings));
      await tester.pumpAndSettle();
      expect(find.text(SettingsStrings.title), findsOneWidget);

      await tester.tap(find.text(SettingsStrings.lockNow));
      await tester.pumpAndSettle();
      expect(find.text(LockStrings.unlockTitle), findsOneWidget);

      await _enterPin(tester, testPin, LockStrings.unlock);
      expect(find.byType(AccountsScreen), findsOneWidget);
      expect(find.text(SettingsStrings.title), findsNothing);
      await app.unmount(tester);
    });
  });

  group('settings', () {
    testWidgets('change the PIN', (tester) async {
      final app = AppHarness();
      await app.pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(AccountsStrings.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text(SettingsStrings.changePin));
      await tester.pumpAndSettle();

      await _enterPin(tester, '999999', SettingsStrings.continueLabel);
      await _enterPin(tester, '135790', SettingsStrings.continueLabel);
      await _enterPin(tester, '135790', SettingsStrings.continueLabel);
      expect(find.text(SettingsStrings.wrongCurrentPin), findsOneWidget);

      await _enterPin(tester, testPin, SettingsStrings.continueLabel);
      await _enterPin(tester, '135790', SettingsStrings.continueLabel);
      await _enterPin(tester, '135790', SettingsStrings.continueLabel);
      expect(find.text(SettingsStrings.pinChanged), findsOneWidget);

      app.lock.lock();
      expect(await app.lock.unlockWithPin('135790'), isA<PinAccepted>());
      await app.unmount(tester);
    });

    testWidgets('choose the auto-lock delay', (tester) async {
      final app = AppHarness();
      await app.pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(AccountsStrings.settings));
      await tester.pumpAndSettle();
      expect(find.text('After 30 seconds'), findsOneWidget);

      await tester.tap(find.text(SettingsStrings.autoLock));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Immediately'));
      await tester.pumpAndSettle();
      expect(app.lock.settings.autoLockAfter, Duration.zero);
      expect(find.text('Immediately'), findsOneWidget);
      await app.unmount(tester);
    });

    testWidgets('biometrics toggle is disabled without a sensor', (
      tester,
    ) async {
      final app = AppHarness();
      app.biometrics.available = false;
      await app.pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(AccountsStrings.settings));
      await tester.pumpAndSettle();
      expect(find.text(SettingsStrings.biometricsUnavailable), findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.onChanged, isNull);
      await app.unmount(tester);
    });
  });
}
