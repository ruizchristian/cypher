/// User-facing text for Settings, kept in one place for later localization.
abstract final class SettingsStrings {
  static const String title = 'Settings';
  static const String security = 'Security';
  static const String biometrics = 'Unlock with fingerprint or face';
  static const String biometricsUnavailable =
      'No fingerprint or face is set up on this device.';
  static const String biometricsNotEnabled =
      "Biometrics weren't turned on: the check didn't succeed.";
  static const String autoLock = 'Auto-lock';
  static const String changePin = 'Change PIN';
  static const String lockNow = 'Lock now';
  static const String backup = 'Backup';
  static const String exportBackup = 'Export backup';
  static const String importBackup = 'Import backup';
  static const String exportUnavailable =
      "Exporting isn't available on this device yet.";
  static String lastBackup(DateTime? at) {
    if (at == null) return 'No backup yet';
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Last backup: ${at.year}-${two(at.month)}-${two(at.day)}';
  }

  static const String biometricEnableReason =
      'Confirm to use biometrics for CypherAuth';

  static String autoLockLabel(Duration after) {
    if (after == Duration.zero) return 'Immediately';
    if (after.inMinutes >= 1) {
      return after.inMinutes == 1
          ? 'After 1 minute'
          : 'After ${after.inMinutes} minutes';
    }
    return 'After ${after.inSeconds} seconds';
  }

  // Change PIN
  static const String currentPinTitle = 'Enter your current PIN';
  static const String newPinTitle = 'Choose a new PIN';
  static const String newPinBody = 'Use at least 6 digits.';
  static const String confirmNewPinTitle = 'Confirm your new PIN';
  static const String wrongCurrentPin = 'That is not your current PIN.';
  static const String mismatch = "The PINs didn't match. Choose again.";
  static const String continueLabel = 'Continue';
  static const String pinChanged = 'PIN changed.';
  static const String saveFailed = "Couldn't save the change. Try again.";
}
