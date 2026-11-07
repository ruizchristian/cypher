import 'package:flutter/material.dart';

import '../shared/app_logo.dart';
import 'lock_strings.dart';

/// Covers the whole app while it is inactive or in the background, so the
/// iOS app-switcher snapshot never shows codes. (Android also has
/// FLAG_SECURE, which blanks the recents thumbnail.)
class PrivacyCover extends StatelessWidget {
  const PrivacyCover({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: LockStrings.coverLabel,
      child: ColoredBox(
        color: scheme.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(height: 80),
              const SizedBox(height: 16),
              Text(
                LockStrings.appName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
