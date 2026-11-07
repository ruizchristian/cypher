import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/security/backup_cipher.dart';
import '../shared/backup_files.dart';

/// [BackupFiles] for the phone platforms.
///
/// Save: Android's "Save as" dialog through the `cypher/platform` channel
/// (`MainActivity.kt`). Open: the Flutter team's `file_selector`. On Android
/// no type filter is set, because the system cannot map the `.cypher`
/// extension to a type and might grey the file out; the file's own header is
/// validated instead.
final class PlatformBackupFiles implements BackupFiles {
  const PlatformBackupFiles([
    this._channel = const MethodChannel('cypher/platform'),
  ]);

  final MethodChannel _channel;

  @override
  bool get canSave => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> save(String suggestedName, Uint8List bytes) async {
    if (!canSave) throw UnsupportedError('Saving backups needs Android');
    final saved = await _channel.invokeMethod<bool>('saveBackup', {
      'name': suggestedName,
      'bytes': bytes,
    });
    return saved ?? false;
  }

  @override
  Future<Uint8List?> open() async {
    final file = await openFile(
      acceptedTypeGroups: defaultTargetPlatform == TargetPlatform.iOS
          ? const [
              XTypeGroup(
                label: 'CypherAuth backup',
                uniformTypeIdentifiers: ['public.data'],
              ),
            ]
          : const [],
    );
    if (file == null) return null;
    if (await file.length() > BackupCipher.maxFileBytes) {
      throw const BackupFileTooLarge();
    }
    return file.readAsBytes();
  }
}
