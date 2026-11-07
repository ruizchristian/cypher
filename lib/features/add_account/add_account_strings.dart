/// User-facing text for adding accounts, kept in one place for later
/// localization.
abstract final class AddAccountStrings {
  static const String addAccount = 'Add account';
  static const String scanQr = 'Scan QR code';
  static const String scanQrHint = 'Use the camera';
  static const String chooseImage = 'Choose image';
  static const String chooseImageHint = 'Read a QR code from a screenshot';
  static const String enterManually = 'Enter setup key';
  static const String enterManuallyHint = 'Type the key the website shows';
  static const String pasteLink = 'Paste link';
  static const String pasteLinkHint = 'An otpauth:// or export link';

  // Scanner
  static const String scanTitle = 'Scan QR code';
  static const String scanInstructions =
      'Point the camera at the QR code shown when you turn on two-factor '
      'authentication.';
  static const String cameraUnavailable =
      "The camera isn't available. Allow camera access in Settings, or "
      'choose an image or enter the setup key instead.';
  static String partProgress(int received, int total) =>
      'Read part $received of $total. Show the next code.';

  // Image
  static const String imageTitle = 'Choose image';
  static const String imageInstructions =
      'Choose a screenshot or photo that shows the QR code.';
  static const String chooseImageButton = 'Choose image';
  static const String noCodeInImage = 'No QR code was found in that image.';
  static String imagePartProgress(int received, int total) =>
      'Read part $received of $total. Choose the image with the next code.';

  // Paste
  static const String pasteTitle = 'Paste link';
  static const String pasteLabel = 'Link';
  static const String pasteHint = 'otpauth://totp/…';
  static const String continueLabel = 'Continue';
  static String pasteNeedsMore(int received, int total) =>
      'Read part $received of $total. Paste the next link.';

  // Manual entry
  static const String manualTitle = 'Enter setup key';
  static const String issuerLabel = 'Service (issuer)';
  static const String issuerHint = 'e.g. GitHub';
  static const String accountLabel = 'Account';
  static const String accountHint = 'e.g. you@example.com';
  static const String secretLabel = 'Setup key';
  static const String showSecret = 'Show setup key';
  static const String hideSecret = 'Hide setup key';
  static const String typeLabel = 'Type';
  static const String timeBased = 'Time-based';
  static const String counterBased = 'Counter-based';
  static const String advanced = 'Advanced';
  static const String algorithmLabel = 'Algorithm';
  static const String digitsLabel = 'Digits';
  static const String periodLabel = 'Period (seconds)';
  static const String counterLabel = 'Counter';
  static const String save = 'Add account';

  static const String nameMissing = 'Enter a service or account name.';
  static const String secretMissing = 'Enter the setup key.';
  static const String secretInvalid =
      'This key has characters a setup key cannot contain. Keys use the '
      'letters A–Z and the digits 2–7.';
  static const String periodInvalid = 'Enter a whole number of seconds.';
  static const String counterInvalid = 'Enter a whole number, 0 or more.';

  // Import problems
  static const String notAnAccountCode =
      "This isn't a two-factor account code.";
  static const String invalidAccountCode =
      'This account code is incomplete or damaged.';
  static const String unsupportedAlgorithm =
      'This account uses an algorithm Cypher does not support.';
  static const String tooManyAccounts =
      'This export holds more accounts than Cypher can import at once.';

  // Confirm
  static const String confirmTitle = 'Add accounts';
  static String confirmAdd(int count) =>
      count == 1 ? 'Add 1 account' : 'Add $count accounts';
  static String duplicatesSkipped(int count) => count == 1
      ? '1 account is already in Cypher and will be skipped.'
      : '$count accounts are already in Cypher and will be skipped.';
  static const String allDuplicates =
      'Every account here is already in Cypher.';
  static const String timeBasedShort = 'Time-based';
  static const String counterBasedShort = 'Counter-based';
  static String added(int count) =>
      count == 1 ? 'Account added.' : '$count accounts added.';
  static const String saveFailed = "Couldn't save. Nothing was added.";
  static const String done = 'Done';
}
