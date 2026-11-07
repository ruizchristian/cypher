import '../../core/security/backup_cipher.dart';
import '../../data/backup_service.dart';

/// User-facing text for backups, kept in one place for later localization.
abstract final class BackupStrings {
  // Export
  static const String exportTitle = 'Export backup';
  static const String exportPinTitle = 'Enter your PIN to export';
  static const String exportPinBody =
      'A backup contains every account, so CypherAuth checks it is you.';
  static const String wrongPin = 'Wrong PIN.';
  static const String continueLabel = 'Continue';
  static const String passwordIntro =
      'Choose a password for this backup. You will need it to restore your '
      'accounts. CypherAuth cannot recover it.';
  static const String passwordLabel = 'Backup password';
  static const String confirmLabel = 'Confirm password';
  static const String showPassword = 'Show password';
  static const String hidePassword = 'Hide password';
  static const String mismatch = "The passwords don't match.";
  static const String export = 'Export';
  static const String encrypting =
      'Encrypting… this takes a few seconds on purpose, to make the password '
      'hard to guess.';
  static String fileName(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'CypherAuth-backup-${now.year}-${two(now.month)}-${two(now.day)}'
        '.cypher';
  }

  static const String saved =
      'Backup saved. Keep the password somewhere safe: without it the backup '
      "can't be opened.";
  static const String notSaved = 'The backup was not saved.';
  static const String saveFailed =
      "The backup couldn't be written to that location. Try another one.";
  static const String exportUnavailable =
      "Exporting isn't available on this device yet.";

  static String passwordHint(String password) {
    final length = password.runes.length;
    if (length < BackupPassword.minLength) {
      return 'Use at least ${BackupPassword.minLength} characters. A few '
          'unrelated words make a strong, memorable password.';
    }
    if (length < 16) {
      return 'OK. Longer is stronger: try a few unrelated words.';
    }
    return 'Strong.';
  }

  // Import
  static const String importTitle = 'Import backup';
  static const String importIntro =
      'Choose a CypherAuth backup file. Its accounts are added to the ones '
      'already here; duplicates are skipped.';
  static const String chooseFile = 'Choose backup file';
  static const String fileChosen = 'Backup file chosen.';
  static const String decrypt = 'Open backup';
  static const String decrypting = 'Opening… this takes a few seconds.';
  static const String fileTooLarge = 'That file is too large to be a backup.';
  static const String openFailed = "That file couldn't be opened.";

  static String problem(BackupProblem problem) => switch (problem) {
    BackupProblem.notABackup => "That file isn't a CypherAuth backup.",
    BackupProblem.newerVersion =>
      'This backup was made by a newer version of CypherAuth, or is not a '
          'valid backup.',
    BackupProblem.tooLarge => fileTooLarge,
    BackupProblem.wrongPasswordOrDamaged =>
      "Couldn't open the backup: the password is wrong, or the file is "
          'damaged.',
    BackupProblem.tooManyAccounts =>
      'This backup holds more accounts than CypherAuth can import at once.',
  };
}
