import 'package:flutter/material.dart';

/// The CypherAuth shield, tinted to the theme's ink so it works in light and
/// dark mode. Decorative: screens state their purpose in text.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = 64, this.color});

  final double height;

  /// Defaults to the theme's on-surface ink.
  final Color? color;

  static const String asset = 'assets/icon/logo.png';

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ExcludeSemantics(
      child: Image.asset(
        asset,
        height: height,
        cacheHeight: (height * dpr).round(),
        color: color ?? Theme.of(context).colorScheme.onSurface,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
