import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/system_clock.dart';
import 'app/vault_bootstrap.dart';
import 'core/security/platform/flutter_secret_store.dart';
import 'core/security/platform/flutter_secure_clipboard.dart';
import 'core/security/platform/local_auth_biometrics.dart';
import 'data/lock_service.dart';
import 'features/add_account/zxing_qr_input.dart';
import 'features/shared/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await openAccountRepository();
  const clock = SystemClock();
  final lock = LockService(
    store: const FlutterSecretStore(),
    repository: repository,
    biometrics: LocalAuthBiometrics(),
    now: clock.now,
  );
  await lock.initialize();
  runApp(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(clock),
        accountRepositoryProvider.overrideWithValue(repository),
        lockServiceProvider.overrideWithValue(lock),
        secureClipboardProvider.overrideWithValue(FlutterSecureClipboard()),
        qrScannerBuilderProvider.overrideWithValue(zxingScanner),
        qrImageReaderProvider.overrideWithValue(ZxingQrImageReader()),
      ],
      child: const CypherApp(),
    ),
  );
}
