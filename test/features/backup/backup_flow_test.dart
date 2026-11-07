import 'dart:async';
import 'dart:typed_data';

import 'package:cypher/data/backup_service.dart';
import 'package:cypher/data/lock_service.dart';
import 'package:cypher/features/accounts/accounts_strings.dart';
import 'package:cypher/features/add_account/add_account_strings.dart';
import 'package:cypher/features/backup/backup_strings.dart';
import 'package:cypher/features/settings/settings_strings.dart';
import 'package:cypher/features/shared/backup_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

const _password = 'correct horse battery staple';

Future<void> _openSettings(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip(AccountsStrings.settings));
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _typePin(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    final key = find.descendant(
      of: find.byType(TextButton),
      matching: find.text(d),
    );
    await tester.ensureVisible(key);
    await tester.tap(key);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(TextField, label);

void main() {
  group('export', () {
    testWidgets('PIN first, then a confirmed password, then save', (
      tester,
    ) async {
      final app = AppHarness();
      await app.seed([hotpAccount('Bank')]);
      await app.pump(tester);
      await _openSettings(tester);
      expect(find.text('No backup yet'), findsOneWidget);
      await _tapText(tester, SettingsStrings.exportBackup);

      expect(find.text(BackupStrings.exportPinTitle), findsOneWidget);
      await _typePin(tester, '000000');
      expect(find.text(BackupStrings.wrongPin), findsOneWidget);
      await _typePin(tester, testPin);

      // Too short, then mismatched: no export possible.
      await tester.enterText(_field(BackupStrings.passwordLabel), 'short');
      await tester.pump();
      expect(find.textContaining('at least 10 characters'), findsOneWidget);
      await tester.enterText(_field(BackupStrings.passwordLabel), _password);
      await tester.enterText(_field(BackupStrings.confirmLabel), 'different');
      await tester.pump();
      expect(find.text(BackupStrings.mismatch), findsOneWidget);
      FilledButton exportButton() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, BackupStrings.export),
      );
      expect(exportButton().onPressed, isNull);

      await tester.enterText(_field(BackupStrings.confirmLabel), _password);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, BackupStrings.export));
      await tester.pumpAndSettle();

      expect(find.text(BackupStrings.saved), findsOneWidget);
      final (name, bytes) = app.backupFiles.saved.single;
      expect(
        name,
        matches(RegExp(r'^CypherAuth-backup-\d{4}-\d\d-\d\d\.cypher$')),
      );
      final restored = await app.backup.readBackup(bytes, _password);
      expect(restored.single.issuer, 'Bank');
      expect(app.backup.lastBackupAt, isNotNull);
      await app.unmount(tester);
    });

    testWidgets('cancelling the save dialog records nothing', (tester) async {
      final app = AppHarness();
      app.backupFiles.confirmSave = false;
      await app.pump(tester);
      await _openSettings(tester);
      await _tapText(tester, SettingsStrings.exportBackup);
      await _typePin(tester, testPin);
      await tester.enterText(_field(BackupStrings.passwordLabel), _password);
      await tester.enterText(_field(BackupStrings.confirmLabel), _password);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, BackupStrings.export));
      await tester.pumpAndSettle();

      expect(find.text(BackupStrings.notSaved), findsOneWidget);
      expect(app.backup.lastBackupAt, isNull);
      await app.unmount(tester);
    });

    testWidgets('a save confirmed after the app locked is still recorded', (
      tester,
    ) async {
      // The "Save as" dialog backgrounds the app, so with auto-lock set to
      // "Immediately" the export screen is gone before the save returns.
      final app = AppHarness();
      await app.seed([hotpAccount('Bank')]);
      final hold = app.backupFiles.holdSave = Completer<void>();
      await app.pump(tester);
      await _openSettings(tester);
      await _tapText(tester, SettingsStrings.exportBackup);
      await _typePin(tester, testPin);
      await tester.enterText(_field(BackupStrings.passwordLabel), _password);
      await tester.enterText(_field(BackupStrings.confirmLabel), _password);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, BackupStrings.export));
      await tester.pump(); // the spinner runs while the dialog is open

      app.lock.lock();
      await tester.pumpAndSettle();
      expect(find.text(BackupStrings.exportTitle), findsNothing);
      hold.complete();
      await tester.pumpAndSettle();

      expect(app.backupFiles.saved, hasLength(1));
      expect(app.backup.lastBackupAt, isNotNull);
      await app.unmount(tester);
    });

    testWidgets('too many wrong PINs lock the app', (tester) async {
      final app = AppHarness();
      await app.pump(tester);
      await _openSettings(tester);
      await _tapText(tester, SettingsStrings.exportBackup);
      for (var i = 0; i < 5; i++) {
        await _typePin(tester, '000000');
      }
      expect(app.lock.state, isA<LockLocked>());
      expect(find.text(BackupStrings.exportPinTitle), findsNothing);
      await app.unmount(tester);
    });

    testWidgets('unavailable where saving is not supported (iOS for now)', (
      tester,
    ) async {
      final app = AppHarness();
      app.backupFiles.canSave = false;
      await app.pump(tester);
      await _openSettings(tester);
      expect(find.text(SettingsStrings.exportUnavailable), findsOneWidget);
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, SettingsStrings.exportBackup),
      );
      expect(tile.enabled, isFalse);
      await app.unmount(tester);
    });
  });

  group('import', () {
    testWidgets('wrong password, then the confirm step adds the accounts', (
      tester,
    ) async {
      // Make a backup with one account, then import it into an empty vault.
      final source = AppHarness();
      await source.seed([hotpAccount('Restored'), hotpAccount('Second')]);
      await source.pump(tester);
      final file = await source.backup.export(_password);
      await source.unmount(tester);

      final app = AppHarness();
      app.backupFiles.nextOpen = file;
      await app.pump(tester);
      await _openSettings(tester);
      await _tapText(tester, SettingsStrings.importBackup);
      await _tapText(tester, BackupStrings.chooseFile);
      expect(find.text(BackupStrings.fileChosen), findsOneWidget);

      await tester.enterText(
        _field(BackupStrings.passwordLabel),
        'nope nope nope',
      );
      await tester.pump(); // the button enables on the next frame
      await tester.tap(
        find.widgetWithText(FilledButton, BackupStrings.decrypt),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(BackupStrings.problem(BackupProblem.wrongPasswordOrDamaged)),
        findsOneWidget,
      );

      await tester.enterText(_field(BackupStrings.passwordLabel), _password);
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, BackupStrings.decrypt),
      );
      await tester.pumpAndSettle();
      expect(find.text(AddAccountStrings.confirmTitle), findsOneWidget);
      await tester.tap(find.text(AddAccountStrings.confirmAdd(2)));
      await tester.pumpAndSettle();

      expect(app.repository.accounts.map((a) => a.issuer), [
        'Restored',
        'Second',
      ]);
      expect(find.text('Restored'), findsOneWidget); // back on the list
      await app.unmount(tester);
    });

    testWidgets('submitting an empty password does nothing', (tester) async {
      final app = AppHarness();
      app.backupFiles.nextOpen = Uint8List(100);
      await app.pump(tester);
      await _openSettings(tester);
      await _tapText(tester, SettingsStrings.importBackup);
      await _tapText(tester, BackupStrings.chooseFile);

      await tester.showKeyboard(_field(BackupStrings.passwordLabel));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      for (final problem in BackupProblem.values) {
        expect(find.text(BackupStrings.problem(problem)), findsNothing);
      }
      await app.unmount(tester);
    });

    testWidgets('a file that is not a backup is explained', (tester) async {
      final app = AppHarness();
      app.backupFiles.nextOpen = const BackupFileTooLarge();
      await app.pump(tester);
      await _openSettings(tester);
      await _tapText(tester, SettingsStrings.importBackup);
      await _tapText(tester, BackupStrings.chooseFile);
      expect(find.text(BackupStrings.fileTooLarge), findsOneWidget);
      await app.unmount(tester);
    });
  });

  group('reminder', () {
    testWidgets('shown with accounts and no backup; Later hides it', (
      tester,
    ) async {
      final app = AppHarness();
      await app.seed([hotpAccount('Bank')]);
      await app.pump(tester);
      await tester.pumpAndSettle();
      expect(find.text(AccountsStrings.backupReminder), findsOneWidget);
      await tester.tap(find.text(AccountsStrings.backupLater));
      await tester.pumpAndSettle();
      expect(find.text(AccountsStrings.backupReminder), findsNothing);
      await app.unmount(tester);
    });

    testWidgets('not shown once a backup exists', (tester) async {
      final app = AppHarness();
      await app.seed([hotpAccount('Bank')]);
      await app.pump(tester);
      await app.backup.recordBackupSaved();
      await tester.pumpAndSettle();
      expect(find.text(AccountsStrings.backupReminder), findsNothing);
      await app.unmount(tester);
    });

    testWidgets('not shown on an empty vault', (tester) async {
      final app = AppHarness();
      await app.pump(tester);
      await tester.pumpAndSettle();
      expect(find.text(AccountsStrings.backupReminder), findsNothing);
      await app.unmount(tester);
    });
  });
}
