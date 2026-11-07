import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/system_clock.dart';
import 'app/vault_bootstrap.dart';
import 'core/security/platform/flutter_secure_clipboard.dart';
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
      ],
      child: const CypherApp(),
    ),
  );
}
