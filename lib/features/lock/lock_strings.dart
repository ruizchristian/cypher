/// User-facing text for the lock screens, kept in one place for later
/// localization.
abstract final class LockStrings {
  static const String appName = 'CypherAuth';

  // Setup
  static const String createTitle = 'Create a PIN';
  static const String createBody =
      'Your PIN protects your codes. Use at least 6 digits.';
  static const String confirmTitle = 'Confirm your PIN';
  static const String confirmBody = 'Enter the same PIN again.';
  static const String mismatch = "The PINs didn't match. Start again.";
  static const String noRecovery =
      "CypherAuth can't recover a forgotten PIN. Keep an encrypted backup "
      'of your accounts.';
  static const String continueLabel = 'Continue';

  // Biometric offer
  static const String biometricOfferTitle = 'Unlock with biometrics?';
  static const String biometricOfferBody =
      'Use your fingerprint or face instead of typing your PIN. Your PIN '
      'still works.';
  static const String biometricOfferYes = 'Use biometrics';
  static const String biometricOfferNo = 'Not now';
  static const String biometricReason = 'Unlock CypherAuth';
  static const String biometricEnableReason =
      'Confirm to use biometrics for CypherAuth';

  // Unlock
  static const String unlockTitle = 'Enter your PIN';
  static const String unlock = 'Unlock';
  static String wrongPin(int attemptsBeforeWait) => attemptsBeforeWait == 0
      ? 'Wrong PIN. One more wrong PIN starts a wait.'
      : 'Wrong PIN. $attemptsBeforeWait more '
            '${attemptsBeforeWait == 1 ? 'try' : 'tries'} before a wait.';
  static String waitFor(Duration remaining) {
    final s = remaining.inSeconds;
    final text = s >= 120
        ? '${(s / 60).ceil()} minutes'
        : s >= 60
        ? '1 minute ${s - 60} s'
        : '$s s';
    return 'Too many wrong PINs. Try again in $text.';
  }

  static const String biometricLockedOut =
      'Biometrics are locked after too many attempts. Use your PIN.';
  static const String forgotPin = 'Forgot your PIN?';
  static const String forgotPinBody =
      "CypherAuth can't recover your PIN: it is never stored, only checked. "
      'To start over, uninstall CypherAuth, reinstall it, and restore your '
      'accounts from an encrypted backup. Without a backup, the accounts on '
      'this device cannot be recovered.';
  static const String ok = 'OK';
  static const String unlockFailed =
      "Your accounts couldn't be opened. Try again.";

  // Privacy cover
  static const String coverLabel = 'CypherAuth is hidden';
}
