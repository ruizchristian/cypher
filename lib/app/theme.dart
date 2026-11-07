import 'package:flutter/material.dart';

/// Light and dark themes share one seed so both palettes stay in step.
abstract final class AppTheme {
  static const Color _seed = Color(0xFF2E5BFF);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      ),
    );
  }
}
