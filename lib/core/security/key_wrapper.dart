import 'dart:convert';
import 'dart:typed_data';

import 'secret_store.dart';
import 'vault_cipher.dart';

/// Holds the vault's data-encryption key (DEK).
///
/// This is the seam for v2's auth-bound keys (docs/system-plan.md §6.1): a v2
/// implementation unwraps the DEK with a biometric- or PIN-protected key, and
/// nothing that depends on this interface has to change.
abstract interface class KeyWrapper {
  /// The stored DEK, or `null` if none is stored or it is unusable.
  Future<Uint8List?> readKey();

  Future<void> storeKey(Uint8List key);

  Future<void> deleteKey();
}

/// v1: the DEK sits in platform secure storage, protected by the Keystore or
/// Keychain but not bound to user authentication.
final class StoredKeyWrapper implements KeyWrapper {
  StoredKeyWrapper(this._store, {this.storageKey = defaultStorageKey});

  static const String defaultStorageKey = 'cypher.vault.dek.v1';

  final SecretStore _store;
  final String storageKey;

  @override
  Future<Uint8List?> readKey() async {
    final encoded = await _store.read(storageKey);
    if (encoded == null) return null;
    try {
      final key = base64.decode(encoded);
      if (key.length == VaultCipher.keyLength) return key;
      key.fillRange(0, key.length, 0);
      return null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> storeKey(Uint8List key) {
    if (key.length != VaultCipher.keyLength) {
      throw ArgumentError('Vault keys are ${VaultCipher.keyLength} bytes');
    }
    return _store.write(storageKey, base64.encode(key));
  }

  @override
  Future<void> deleteKey() => _store.delete(storageKey);
}
