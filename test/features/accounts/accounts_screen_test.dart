import 'package:cypher/core/otp/otp_types.dart';
import 'package:cypher/data/account_repository.dart';
import 'package:cypher/features/accounts/account_display.dart';
import 'package:cypher/features/accounts/accounts_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

// RFC 4226 Appendix D codes for the shared test secret, by counter.
// TOTP with period 30 uses counter floor(T / 30).
const _counter0 = '755224';
const _counter1 = '287082';
const _counter2 = '359152';

/// A list tile merges its children into one semantics node, so a part (the
/// spelled-out code, the time left) is found inside the merged label.
Finder _inTileLabel(String part) =>
    find.bySemanticsLabel(RegExp(RegExp.escape(part)));

void main() {
  group('TOTP codes', () {
    testWidgets('shows the current code and the time left', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = AppHarness(unixSeconds: 59); // counter 1, 1 s left
      await app.seed([totpAccount('Example')]);
      await app.pump(tester);

      expect(find.text('287 082'), findsOneWidget);
      expect(
        _inTileLabel(AccountsStrings.codeLabel(_counter1)),
        findsOneWidget,
      );
      expect(_inTileLabel(AccountsStrings.secondsLeft(1)), findsOneWidget);
      semantics.dispose();
      await app.unmount(tester);
    });

    testWidgets('rolls over exactly at the period boundary', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = AppHarness(unixSeconds: 59);
      await app.seed([totpAccount('Example')]);
      await app.pump(tester);
      expect(find.text(formatCode(_counter1)), findsOneWidget);

      await app.advance(tester, const Duration(seconds: 1)); // T = 60
      expect(find.text(formatCode(_counter2)), findsOneWidget);
      expect(find.text(formatCode(_counter1)), findsNothing);
      expect(_inTileLabel(AccountsStrings.secondsLeft(30)), findsOneWidget);

      await app.advance(tester, const Duration(seconds: 29)); // T = 89
      expect(find.text(formatCode(_counter2)), findsOneWidget);
      expect(_inTileLabel(AccountsStrings.secondsLeft(1)), findsOneWidget);
      semantics.dispose();
      await app.unmount(tester);
    });

    testWidgets('a tick does not rebuild the tile menu', (tester) async {
      final app = AppHarness(unixSeconds: 59);
      await app.seed([totpAccount('Example')]);
      await app.pump(tester);
      final menu = find.byTooltip(AccountsStrings.accountMenu);
      final before = tester.widget(menu);

      await app.advance(tester, const Duration(seconds: 1)); // T = 60
      expect(find.text(formatCode(_counter2)), findsOneWidget);
      expect(identical(tester.widget(menu), before), isTrue);
      await app.unmount(tester);
    });

    testWidgets('tapping copies the code, never the secret', (tester) async {
      final app = AppHarness(unixSeconds: 0); // counter 0
      await app.seed([totpAccount('Example')]);
      await app.pump(tester);

      await tester.tap(find.text(formatCode(_counter0)));
      await tester.pump();

      expect(app.clipboard.copied, [_counter0]);
      expect(find.text(AccountsStrings.copied), findsOneWidget);
      await app.unmount(tester);
    });
  });

  group('HOTP codes', () {
    testWidgets('are hidden until the next code is requested', (tester) async {
      final app = AppHarness();
      await app.seed([hotpAccount('Bank')]);
      await app.pump(tester);
      expect(find.text(AccountsStrings.hotpHidden), findsOneWidget);

      // Tapping the hidden tile must not consume a counter value.
      await tester.tap(find.text(AccountsStrings.hotpHidden));
      await tester.pump();
      expect(app.repository.accounts.single.counter, 0);
      expect(app.clipboard.copied, isEmpty);

      await tester.tap(find.byTooltip(AccountsStrings.nextCode));
      await tester.pumpAndSettle();

      expect(find.text(formatCode(_counter1)), findsOneWidget);
      expect(app.repository.accounts.single.counter, 1);

      // The advanced counter is on disk.
      final fresh = app.newRepository();
      await fresh.unlock();
      expect(fresh.accounts.single.counter, 1);

      await tester.tap(find.text(formatCode(_counter1)));
      await tester.pump();
      expect(app.clipboard.copied, [_counter1]);
      await app.unmount(tester);
    });
  });

  group('list management', () {
    testWidgets('search filters by issuer and account name', (tester) async {
      final app = AppHarness();
      await app.seed([
        hotpAccount('GitHub', 'octocat'),
        hotpAccount('Google', 'alice@example.com'),
      ]);
      await app.pump(tester);
      expect(find.byTooltip(AccountsStrings.reorderHandle), findsNWidgets(2));

      await tester.tap(find.byTooltip(AccountsStrings.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'git');
      await tester.pumpAndSettle();
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('Google'), findsNothing);
      // No reordering while filtered.
      expect(find.byTooltip(AccountsStrings.reorderHandle), findsNothing);

      await tester.enterText(find.byType(TextField), 'ALICE');
      await tester.pumpAndSettle();
      expect(find.text('Google'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text(AccountsStrings.noMatches), findsOneWidget);

      await tester.tap(find.byTooltip(AccountsStrings.closeSearch));
      await tester.pumpAndSettle();
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('Google'), findsOneWidget);
      await app.unmount(tester);
    });

    testWidgets('dragging the handle reorders and persists', (tester) async {
      final app = AppHarness();
      await app.seed([hotpAccount('First'), hotpAccount('Second')]);
      await app.pump(tester);

      final handle = find.byTooltip(AccountsStrings.reorderHandle).first;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(app.repository.accounts.map((a) => a.issuer), ['Second', 'First']);
      final fresh = app.newRepository();
      await fresh.unlock();
      expect(fresh.accounts.map((a) => a.issuer), ['Second', 'First']);
      await app.unmount(tester);
    });

    testWidgets('rename through the edit sheet', (tester) async {
      final app = AppHarness();
      await app.seed([hotpAccount('Old name', 'me')]);
      await app.pump(tester);

      await tester.tap(find.byTooltip(AccountsStrings.accountMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AccountsStrings.edit));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, AccountsStrings.issuerLabel),
        '  New name  ',
      );
      await tester.tap(find.text(AccountsStrings.save));
      await tester.pumpAndSettle();

      expect(find.text('New name'), findsOneWidget);
      expect(find.text('Old name'), findsNothing);
      final stored = app.repository.accounts.single;
      expect(
        (stored.issuer, stored.accountName, stored.type),
        ('New name', 'me', OtpType.hotp),
      );
      await app.unmount(tester);
    });

    testWidgets('delete asks first, and cancel keeps the account', (
      tester,
    ) async {
      final app = AppHarness();
      await app.seed([hotpAccount('Keep'), hotpAccount('Remove')]);
      await app.pump(tester);

      Future<void> openDelete(String issuer) async {
        final tile = find.ancestor(
          of: find.text(issuer),
          matching: find.byType(ListTile),
        );
        await tester.tap(
          find.descendant(
            of: tile,
            matching: find.byTooltip(AccountsStrings.accountMenu),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(AccountsStrings.delete));
        await tester.pumpAndSettle();
      }

      await openDelete('Remove');
      expect(find.text(AccountsStrings.deleteTitle), findsOneWidget);
      await tester.tap(find.text(AccountsStrings.cancel));
      await tester.pumpAndSettle();
      expect(app.repository.accounts, hasLength(2));

      await openDelete('Remove');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(AccountsStrings.delete),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remove'), findsNothing);
      expect(app.repository.accounts.map((a) => a.issuer), ['Keep']);
      await app.unmount(tester);
    });
  });

  group('unreadable vault', () {
    testWidgets('explains the problem and starts over only when confirmed', (
      tester,
    ) async {
      final app = AppHarness();
      await app.seed([hotpAccount('Lost')]);
      app.secrets.values.clear(); // the vault key is gone
      await app.pump(tester);

      expect(find.text(AccountsStrings.unreadableTitle), findsOneWidget);
      expect(find.text(AccountsStrings.unreadableKeyMissing), findsOneWidget);
      expect(app.repository.state, isA<VaultUnreadable>());

      await tester.tap(find.text(AccountsStrings.startOver));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AccountsStrings.cancel));
      await tester.pumpAndSettle();
      expect(app.files.quarantined, isEmpty);

      await tester.tap(find.text(AccountsStrings.startOver));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(AccountsStrings.startOver),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AccountsStrings.emptyTitle), findsOneWidget);
      expect(app.files.quarantined, hasLength(1));
      await app.unmount(tester);
    });
  });

  group('copy failure', () {
    testWidgets('a failed copy says so instead of claiming success', (
      tester,
    ) async {
      final app = AppHarness(unixSeconds: 0);
      await app.seed([totpAccount('Example')]);
      await app.pump(tester);
      app.clipboard.failNextCopy = true;

      await tester.tap(find.text(formatCode(_counter0)));
      await tester.pump();

      expect(find.text(AccountsStrings.copyFailed), findsOneWidget);
      expect(find.text(AccountsStrings.copied), findsNothing);
      expect(app.clipboard.copied, isEmpty);
      await app.unmount(tester);
    });
  });
}
