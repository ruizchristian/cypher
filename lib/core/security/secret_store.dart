/// Platform secure storage (Android Keystore / iOS Keychain) as a small
/// key-value interface, so code above it can be tested with an in-memory fake.
abstract interface class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}
