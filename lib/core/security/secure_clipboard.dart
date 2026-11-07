/// Copies one-time codes to the system clipboard and removes them again.
///
/// Only codes are copied, never secrets.
abstract interface class SecureClipboard {
  /// Copies [code] and schedules its removal.
  Future<void> copyCode(String code);

  /// Cancels any pending removal timer.
  void dispose();
}
