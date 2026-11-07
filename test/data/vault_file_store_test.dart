import 'dart:io';
import 'dart:typed_data';

import 'package:cypher/data/vault_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late IoVaultFileStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cypher_vault_test');
    store = IoVaultFileStore(
      Directory('${temp.path}${Platform.pathSeparator}vault'),
      now: () => DateTime.utc(2026, 11, 7),
    );
  });

  tearDown(() => temp.delete(recursive: true));

  List<String> names() =>
      store.directory.listSync().map((e) => e.uri.pathSegments.last).toList()
        ..sort();

  test('reads null before the first write', () async {
    expect(await store.read(), isNull);
  });

  test('creates the directory and round-trips bytes', () async {
    await store.write(Uint8List.fromList([1, 2, 3]));
    expect(await store.read(), [1, 2, 3]);
    expect(names(), ['vault.bin']);
  });

  test('replaces the vault without leaving a temp file', () async {
    await store.write(Uint8List.fromList([1]));
    await store.write(Uint8List.fromList([2, 2]));
    expect(await store.read(), [2, 2]);
    expect(names(), ['vault.bin']);
  });

  test(
    'a leftover temp file from a crash does not affect reads or writes',
    () async {
      await store.write(Uint8List.fromList([7]));
      await File(
        '${store.directory.path}${Platform.pathSeparator}vault.bin.tmp',
      ).writeAsBytes([9, 9, 9]);
      expect(await store.read(), [7]);
      await store.write(Uint8List.fromList([8]));
      expect(await store.read(), [8]);
    },
  );

  test('quarantine moves the vault aside and keeps its bytes', () async {
    await store.write(Uint8List.fromList([5, 5]));
    final name = await store.quarantine();
    expect(
      name,
      'vault.unreadable-${DateTime.utc(2026, 11, 7).millisecondsSinceEpoch}.bin',
    );
    expect(await store.read(), isNull);
    final moved = File('${store.directory.path}${Platform.pathSeparator}$name');
    expect(await moved.readAsBytes(), [5, 5]);
  });
}
