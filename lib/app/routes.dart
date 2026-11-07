import 'package:flutter/material.dart';

import '../features/accounts/accounts_screen.dart';

/// Route names. Arguments passed with a route must never carry a secret or an
/// `otpauth://` URI: navigation state can surface in logs and restoration
/// data, so pass an account ID instead.
abstract final class AppRoutes {
  static const String accounts = '/';
}

Route<void> onGenerateRoute(RouteSettings settings) {
  final Widget screen = switch (settings.name) {
    AppRoutes.accounts => const AccountsScreen(),
    // Unknown names fall back to the home screen instead of throwing.
    _ => const AccountsScreen(),
  };
  return MaterialPageRoute<void>(builder: (_) => screen, settings: settings);
}
