import 'dart:typed_data';

import 'package:cypher/core/security/key_wrapper.dart';
import 'package:cypher/core/security/vault_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/in_memory_secret_store.dart';

void main() {
  late InMemorySecretStore store;
  late StoredKeyWrapper wrapper;

  setUp(() {
    store = InMemorySecretStore();
    wrapper = StoredKeyWrapper(store);
  });

  test('stores and reads back a key', () async {
    final key = VaultCipher.newKey();
    await wrapper.storeKey(key);
    expect(await wrapper.readKey(), key);
  });

  test('returns null when no key is stored', () async {
    expect(await wrapper.readKey(), isNull);
  });

  test('deletes the key', () async {
    await wrapper.storeKey(VaultCipher.newKey());
    await wrapper.deleteKey();
    expect(await wrapper.readKey(), isNull);
  });

  test(
    'treats an undecodable or wrong-length stored value as missing',
    () async {
      store.values[StoredKeyWrapper.defaultStorageKey] = 'not base64!';
      expect(await wrapper.readKey(), isNull);
      store.values[StoredKeyWrapper.defaultStorageKey] = 'AAAA';
      expect(await wrapper.readKey(), isNull);
    },
  );

  test('refuses to store a key of the wrong length', () {
    expect(() => wrapper.storeKey(Uint8List(16)), throwsArgumentError);
  });

  test('honours a custom storage key', () async {
    final custom = StoredKeyWrapper(store, storageKey: 'other');
    await custom.storeKey(VaultCipher.newKey());
    expect(store.values.keys, ['other']);
  });
}
