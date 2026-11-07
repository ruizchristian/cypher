import 'dart:io';
import 'dart:typed_data';

/// Persistence for the encrypted vault blob.
abstract interface class VaultFileStore {
  /// The stored bytes, or `null` if no vault exists.
  Future<Uint8List?> read();

  /// Replaces the vault atomically: readers see either the old or the new
  /// bytes, never a partial write.
  Future<void> write(Uint8List data);

  /// Moves the current vault aside so a fresh one can be created without
  /// destroying the old file. Returns the name it was moved to.
  Future<String> quarantine();
}

final class IoVaultFileStore implements VaultFileStore {
  IoVaultFileStore(this.directory, {this._now = DateTime.now});

  static const String fileName = 'vault.bin';

  final Directory directory;
  final DateTime Function() _now;

  File get _file => _child(fileName);

  File get _temp => _child('$fileName.tmp');

  File _child(String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  @override
  Future<Uint8List?> read() async {
    final file = _file;
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> write(Uint8List data) async {
    await directory.create(recursive: true);
    final temp = _temp;
    await temp.writeAsBytes(data, flush: true);
    await temp.rename(_file.path);
  }

  @override
  Future<String> quarantine() async {
    final name =
        'vault.unreadable-${_now().toUtc().millisecondsSinceEpoch}.bin';
    await _file.rename(_child(name).path);
    return name;
  }
}
