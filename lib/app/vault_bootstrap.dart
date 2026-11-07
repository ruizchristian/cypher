import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/security/key_wrapper.dart';
import '../core/security/platform/flutter_secret_store.dart';
import '../data/account_repository.dart';
import '../data/vault_file_store.dart';

/// Builds the production [AccountRepository]: vault key in Keystore/Keychain,
/// vault file in the app's private support directory (not backed up; see
/// `android/app/src/main/res/xml/data_extraction_rules.xml`).
///
/// [directoryName] and [keyName] exist so the on-device integration test can
/// use its own vault without touching the real one.
Future<AccountRepository> openAccountRepository({
  String directoryName = 'vault',
  String keyName = StoredKeyWrapper.defaultStorageKey,
}) async {
  final support = await getApplicationSupportDirectory();
  return AccountRepository(
    keys: StoredKeyWrapper(const FlutterSecretStore(), storageKey: keyName),
    files: IoVaultFileStore(
      Directory('${support.path}${Platform.pathSeparator}$directoryName'),
    ),
  );
}
