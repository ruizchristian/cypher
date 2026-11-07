import 'package:cypher/core/security/secret_store.dart';

/// [SecretStore] fake. [values] is exposed so tests can inspect or corrupt it.
final class InMemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
