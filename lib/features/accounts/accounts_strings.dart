/// User-facing text for the accounts feature, kept in one place for later
/// localization.
abstract final class AccountsStrings {
  static const String screenTitle = 'CypherAuth';
  static const String emptyTitle = 'No accounts yet';
  static const String emptyBody =
      'Tap "Add account" to set up your first one, or restore a backup '
      'from Settings → Import backup.';
  static const String backupReminder =
      "You don't have a backup yet. If you forget your PIN or lose this "
      "phone, your accounts can't be recovered.";
  static const String backupNow = 'Back up';
  static const String backupLater = 'Later';
  static const String addAccount = 'Add account';
  static const String noMatches = 'No matching accounts';
  static const String searchHint = 'Search accounts';
  static const String search = 'Search';
  static const String closeSearch = 'Close search';
  static const String lockNow = 'Lock now';
  static const String settings = 'Settings';
  static const String saveFailed = "Couldn't save your change. Try again.";

  static const String copied = 'Code copied. It will be cleared in 30 seconds.';
  static const String copyFailed = "Couldn't copy the code.";
  static const String hotpHidden = 'Tap ↻ to show the next code';
  static const String nextCode = 'Generate next code';
  static const String accountMenu = 'Account options';
  static const String reorderHandle = 'Drag to reorder';
  static const String edit = 'Edit';
  static const String delete = 'Delete';

  static String secondsLeft(int seconds) =>
      seconds == 1 ? '1 second left' : '$seconds seconds left';
  static String codeLabel(String code) => 'Code ${code.split('').join(' ')}';

  // Edit sheet
  static const String editTitle = 'Edit account';
  static const String issuerLabel = 'Issuer';
  static const String accountLabel = 'Account';
  static const String save = 'Save';
  static const String cancel = 'Cancel';
  static const String deleteTitle = 'Delete this account?';
  static String deleteBody(String name) =>
      '"$name" will be removed from CypherAuth. You will lose access to its codes '
      "unless you can set it up again or restore it from a backup. This can't "
      'be undone.';
  static const String untitled = 'Unnamed account';

  // Unreadable vault
  static const String unreadableTitle = "Your accounts can't be opened";
  static const String unreadableKeyMissing =
      "The key that protects your accounts is no longer available on this "
      'device. This can happen after a system reset or when data is moved to '
      'a new phone.';
  static const String unreadableDecryptFailed =
      'The saved accounts file could not be decrypted. It may be damaged.';
  static const String unreadableCorrupt = 'The saved accounts file is damaged.';
  static const String unreadableKept =
      'Nothing has been deleted. If you start over, the old file is kept on '
      'this device, and you can restore your accounts from a backup in '
      'Settings → Import backup.';
  static const String startOver = 'Start over with no accounts';
  static const String startOverConfirmTitle = 'Start over?';
  static const String startOverConfirmBody =
      'CypherAuth will open with no accounts. Your old file is kept, but CypherAuth '
      "can't read it.";
}
