import 'dart:io';

import 'package:cypher/core/otp/otp_types.dart';
import 'package:cypher/features/accounts/accounts_strings.dart';
import 'package:cypher/features/add_account/add_account_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_qr_input.dart';
import '../../helpers/app_harness.dart';
import '../../helpers/migration_fixtures.dart';

// Base32 of the RFC 4226 test secret.
const _secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

// HOTP accounts keep the list free of the ticking countdown, so
// pumpAndSettle can settle.
String _hotpUri(String issuer) =>
    'otpauth://hotp/$issuer:me?secret=$_secret&issuer=$issuer&counter=0';

Future<void> _openOption(WidgetTester tester, String option) async {
  await tester.pumpAndSettle(); // let the add button finish animating in
  await tester.tap(find.text(AccountsStrings.addAccount));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option));
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester, int count) async {
  expect(find.text(AddAccountStrings.confirmTitle), findsOneWidget);
  await tester.tap(find.text(AddAccountStrings.confirmAdd(count)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the add button offers all four methods', (tester) async {
    final app = AppHarness();
    await app.pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text(AccountsStrings.addAccount));
    await tester.pumpAndSettle();
    for (final option in [
      AddAccountStrings.scanQr,
      AddAccountStrings.chooseImage,
      AddAccountStrings.enterManually,
      AddAccountStrings.pasteLink,
    ]) {
      expect(find.text(option), findsOneWidget, reason: option);
    }
    await app.unmount(tester);
  });

  group('scan', () {
    testWidgets('ignores other QR codes, then imports an account code', (
      tester,
    ) async {
      final app = AppHarness();
      await app.pump(tester);
      await _openOption(tester, AddAccountStrings.scanQr);

      app.scanner.show('https://example.com/menu');
      await tester.pump();
      expect(find.text(AddAccountStrings.notAnAccountCode), findsOneWidget);

      app.scanner.show(_hotpUri('GitHub'));
      await tester.pumpAndSettle();
      expect(find.text('GitHub'), findsOneWidget);
      // Repeated detections of the same code after acceptance are ignored.
      app.scanner.show(_hotpUri('GitHub'));
      await tester.pumpAndSettle();

      await _confirm(tester, 1);
      expect(find.text(AddAccountStrings.added(1)), findsOneWidget);
      expect(app.repository.accounts.single.issuer, 'GitHub');
      await app.unmount(tester);
    });

    testWidgets('assembles a multi-part export before confirming', (
      tester,
    ) async {
      final app = AppHarness();
      await app.pump(tester);
      await _openOption(tester, AddAccountStrings.scanQr);

      app.scanner.show(
        migrationUri([
          migrationAccount(issuer: 'A', type: 1, counter: 0),
        ], batchSize: 2),
      );
      await tester.pump();
      expect(find.text(AddAccountStrings.partProgress(1, 2)), findsOneWidget);
      expect(find.text(AddAccountStrings.confirmTitle), findsNothing);

      app.scanner.show(
        migrationUri(
          [migrationAccount(issuer: 'B', type: 1, counter: 0)],
          batchSize: 2,
          batchIndex: 1,
        ),
      );
      await tester.pumpAndSettle();
      await _confirm(tester, 2);
      expect(app.repository.accounts.map((a) => a.issuer), ['A', 'B']);
      await app.unmount(tester);
    });

    testWidgets('a code reported after leaving the screen is ignored', (
      tester,
    ) async {
      final app = AppHarness();
      await app.pump(tester);
      await _openOption(tester, AddAccountStrings.scanQr);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // The camera plugin decodes frames asynchronously, so a result can
      // land after the screen is disposed.
      app.scanner.show('https://example.com/late');
      app.scanner.show(_hotpUri('Late'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(AddAccountStrings.confirmTitle), findsNothing);
      expect(app.repository.accounts, isEmpty);
      await app.unmount(tester);
    });

    testWidgets('explains when the camera is unavailable', (tester) async {
      final app = AppHarness();
      await app.pump(tester);
      await _openOption(tester, AddAccountStrings.scanQr);
      app.scanner.failCamera();
      await tester.pump();
      expect(find.text(AddAccountStrings.cameraUnavailable), findsOneWidget);
      await app.unmount(tester);
    });
  });

  group('image', () {
    testWidgets('cancel is silent, no code is explained, a code imports', (
      tester,
    ) async {
      final app = AppHarness();
      await app.pump(tester);
      await _openOption(tester, AddAccountStrings.chooseImage);

      app.imageReader
        ..queue(FakeQrImageReader.cancel)
        ..queue(null)
        ..queue(_hotpUri('Bank'));

      await tester.tap(find.byIcon(Icons.photo_library_outlined));
      await tester.pumpAndSettle();
      expect(find.text(AddAccountStrings.imageInstructions), findsOneWidget);

      await tester.tap(find.byIcon(Icons.photo_library_outlined));
      await tester.pumpAndSettle();
      expect(find.text(AddAccountStrings.noCodeInImage), findsOneWidget);

      await tester.tap(find.byIcon(Icons.photo_library_outlined));
      await tester.pumpAndSettle();
      await _confirm(tester, 1);
      expect(app.repository.accounts.single.issuer, 'Bank');
      await app.unmount(tester);
    });
  });

  group('paste', () {
    testWidgets('rejects junk without echoing it, then imports a link', (
      tester,
    ) async {
      final app = AppHarness();
      await app.pump(tester);
      await _openOption(tester, AddAccountStrings.pasteLink);

      await tester.enterText(
        find.byType(TextField),
        'otpauth://totp/x?secret=$_secret&digits=12',
      );
      await tester.tap(find.text(AddAccountStrings.continueLabel));
      await tester.pumpAndSettle();
      expect(find.text(AddAccountStrings.invalidAccountCode), findsOneWidget);

      await tester.enterText(find.byType(TextField), _hotpUri('Linked'));
      await tester.tap(find.text(AddAccountStrings.continueLabel));
      await tester.pumpAndSettle();
      await _confirm(tester, 1);
      expect(app.repository.accounts.single.issuer, 'Linked');
      await app.unmount(tester);
    });
  });

  group('manual entry', () {
    Finder field(String label) => find.widgetWithText(TextField, label);

    testWidgets('shows field errors, then saves a valid account', (
      tester,
    ) async {
      final app = AppHarness();
      await app.pump(tester);
      await _openOption(tester, AddAccountStrings.enterManually);

      await tester.tap(find.text(AddAccountStrings.save));
      await tester.pumpAndSettle();
      expect(find.text(AddAccountStrings.nameMissing), findsOneWidget);
      expect(find.text(AddAccountStrings.secretMissing), findsOneWidget);

      await tester.enterText(field(AddAccountStrings.issuerLabel), 'Work VPN');
      await tester.enterText(field(AddAccountStrings.secretLabel), 'GEZD 0000');
      await tester.tap(find.text(AddAccountStrings.save));
      await tester.pumpAndSettle();
      expect(find.text(AddAccountStrings.secretInvalid), findsOneWidget);
      expect(find.text(AddAccountStrings.nameMissing), findsNothing);

      await tester.enterText(
        field(AddAccountStrings.secretLabel),
        'gezd gnbv gy3t qojq gezd gnbv gy3t qojq',
      );
      await tester.tap(find.text(AddAccountStrings.counterBased));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AddAccountStrings.save));
      await tester.pumpAndSettle();

      expect(find.text(AddAccountStrings.added(1)), findsOneWidget);
      final stored = app.repository.accounts.single;
      expect((stored.issuer, stored.type), ('Work VPN', OtpType.hotp));
      await app.unmount(tester);
    });

    testWidgets('the secret field is hidden and kept from the keyboard', (
      tester,
    ) async {
      final app = AppHarness();
      await app.pump(tester);
      await _openOption(tester, AddAccountStrings.enterManually);

      TextField secretField() =>
          tester.widget<TextField>(field(AddAccountStrings.secretLabel));
      expect(secretField().obscureText, isTrue);
      expect(secretField().enableSuggestions, isFalse);
      expect(secretField().autocorrect, isFalse);
      expect(secretField().enableIMEPersonalizedLearning, isFalse);

      await tester.tap(find.byTooltip(AddAccountStrings.showSecret));
      await tester.pump();
      expect(secretField().obscureText, isFalse);
      await app.unmount(tester);
    });
  });

  group('confirmation', () {
    testWidgets('accounts already in the vault are skipped', (tester) async {
      final app = AppHarness();
      await app.seed([hotpAccount('Dup', 'me')]);
      await app.pump(tester);
      await _openOption(tester, AddAccountStrings.pasteLink);

      await tester.enterText(find.byType(TextField), _hotpUri('Dup'));
      await tester.tap(find.text(AddAccountStrings.continueLabel));
      await tester.pumpAndSettle();

      expect(find.text(AddAccountStrings.allDuplicates), findsOneWidget);
      await tester.tap(find.text(AddAccountStrings.done));
      await tester.pumpAndSettle();
      expect(app.repository.accounts, hasLength(1));
      await app.unmount(tester);
    });

    testWidgets('a failed save adds nothing', (tester) async {
      final app = AppHarness();
      await app.pump(tester);
      await _openOption(tester, AddAccountStrings.scanQr);
      app.scanner.show(
        migrationUri([
          migrationAccount(issuer: 'A', type: 1, counter: 0),
          migrationAccount(issuer: 'B', type: 1, counter: 0),
        ]),
      );
      await tester.pumpAndSettle();

      app.files.failNextWrite = const FileSystemException('disk full');
      await tester.tap(find.text(AddAccountStrings.confirmAdd(2)));
      await tester.pumpAndSettle();

      expect(find.text(AddAccountStrings.saveFailed), findsOneWidget);
      expect(app.repository.accounts, isEmpty);
      final fresh = app.newRepository();
      await fresh.unlock();
      expect(fresh.accounts, isEmpty);
      await app.unmount(tester);
    });

    testWidgets('a code repeated within one import is added once', (
      tester,
    ) async {
      final app = AppHarness();
      await app.pump(tester);
      await _openOption(tester, AddAccountStrings.scanQr);
      app.scanner.show(
        migrationUri([
          migrationAccount(issuer: 'Twice', type: 1, counter: 0),
          migrationAccount(issuer: 'Twice', type: 1, counter: 0),
          migrationAccount(issuer: 'Other', type: 1, counter: 0),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text(AddAccountStrings.duplicatesSkipped(1)), findsOneWidget);
      await _confirm(tester, 2);
      expect(app.repository.accounts.map((a) => a.issuer), ['Twice', 'Other']);
      await app.unmount(tester);
    });

    testWidgets('keeps showing the saved accounts while it closes', (
      tester,
    ) async {
      final app = AppHarness();
      await app.pump(tester);
      await _openOption(tester, AddAccountStrings.pasteLink);
      await tester.enterText(find.byType(TextField), _hotpUri('Fresh'));
      await tester.tap(find.text(AddAccountStrings.continueLabel));
      await tester.pumpAndSettle();

      await tester.tap(find.text(AddAccountStrings.confirmAdd(1)));
      // Step through the exit transition: the screen must not flip to
      // "already in Cypher" once the vault contains the new account.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text(AddAccountStrings.allDuplicates), findsNothing);
      }
      await tester.pumpAndSettle();
      expect(app.repository.accounts.single.issuer, 'Fresh');
      await app.unmount(tester);
    });

    testWidgets('never shows the secret', (tester) async {
      final app = AppHarness();
      await app.pump(tester);
      await _openOption(tester, AddAccountStrings.pasteLink);
      await tester.enterText(find.byType(TextField), _hotpUri('Hidden'));
      await tester.tap(find.text(AddAccountStrings.continueLabel));
      await tester.pumpAndSettle();

      expect(find.text(AddAccountStrings.confirmTitle), findsOneWidget);
      expect(find.textContaining(_secret), findsNothing);
      expect(find.textContaining(_secret.toLowerCase()), findsNothing);
      await app.unmount(tester);
    });
  });
}
