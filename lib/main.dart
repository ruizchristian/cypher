import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/system_clock.dart';
import 'app/vault_bootstrap.dart';
import 'core/security/platform/flutter_secure_clipboard.dart';
import 'features/add_account/zxing_qr_input.dart';
import 'features/shared/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await openAccountRepository();
  runApp(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(const SystemClock()),
        accountRepositoryProvider.overrideWithValue(repository),
        secureClipboardProvider.overrideWithValue(FlutterSecureClipboard()),
        qrScannerBuilderProvider.overrideWithValue(zxingScanner),
        qrImageReaderProvider.overrideWithValue(ZxingQrImageReader()),
      ],
      child: const CypherApp(),
    ),
  );
}
