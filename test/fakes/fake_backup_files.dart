import 'dart:async';
import 'dart:typed_data';

import 'package:cypher/features/shared/backup_files.dart';

/// Stands in for the system save/open pickers. [saved] records what was
/// written; [nextOpen] is what the next [open] returns (`null` = cancelled).
final class FakeBackupFiles implements BackupFiles {
  @override
  bool canSave = true;

  final List<(String, Uint8List)> saved = [];

  /// When false, the next save behaves as if the user cancelled.
  bool confirmSave = true;

  /// When set, saves wait for it, like a user still in the "Save as" dialog.
  Completer<void>? holdSave;

  Object? nextOpen;

  @override
  Future<bool> save(String suggestedName, Uint8List bytes) async {
    await holdSave?.future;
    if (!confirmSave) return false;
    saved.add((suggestedName, Uint8List.fromList(bytes)));
    return true;
  }

  @override
  Future<Uint8List?> open() async {
    final next = nextOpen;
    if (next is Exception) throw next;
    return next as Uint8List?;
  }
}
