import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../secret_store.dart';

/// [SecretStore] backed by `flutter_secure_storage`.
///
/// Android: Keystore-wrapped AES-GCM (the plugin's default cipher).
/// iOS: Keychain, `first_unlock_this_device` and not synchronizable, so items
/// never reach iCloud or another device.
final class FlutterSecretStore implements SecretStore {
  const FlutterSecretStore([this._storage = _defaultStorage]);

  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
