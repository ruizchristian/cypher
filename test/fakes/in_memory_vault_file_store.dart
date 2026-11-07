import 'dart:async';
import 'dart:typed_data';

import 'package:cypher/data/vault_file_store.dart';

/// [VaultFileStore] fake that can fail or pause writes on demand.
final class InMemoryVaultFileStore implements VaultFileStore {
  Uint8List? data;
  final List<Uint8List> quarantined = [];
  int writeCount = 0;

  /// When set, the next write throws this instead of storing anything.
  Object? failNextWrite;

  /// When set, writes wait for this before storing.
  Completer<void>? writeGate;

  @override
  Future<Uint8List?> read() async =>
      data == null ? null : Uint8List.fromList(data!);

  @override
  Future<void> write(Uint8List bytes) async {
    final failure = failNextWrite;
    if (failure != null) {
      failNextWrite = null;
      throw failure;
    }
    await writeGate?.future;
    data = Uint8List.fromList(bytes);
    writeCount++;
  }

  @override
  Future<String> quarantine() async {
    quarantined.add(data!);
    data = null;
    return 'vault.unreadable-${quarantined.length}.bin';
  }
}
