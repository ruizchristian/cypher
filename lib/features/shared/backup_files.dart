import 'dart:typed_data';

/// Saving and opening backup files through the system's own pickers, so the
/// app never needs storage permissions.
abstract interface class BackupFiles {
  /// Whether saving is supported on this platform (Android now; iOS export
  /// waits until it can be built and tested on a Mac).
  bool get canSave;

  /// Asks the user where to save [bytes]. True if saved, false if they
  /// cancelled. Throws if the file could not be written.
  Future<bool> save(String suggestedName, Uint8List bytes);

  /// Lets the user pick a file. Returns `null` if they cancelled. Throws
  /// [BackupFileTooLarge] for files no real backup could be.
  Future<Uint8List?> open();
}

final class BackupFileTooLarge implements Exception {
  const BackupFileTooLarge();
}
