import 'package:flutter/material.dart';

/// "Ink + one accent": near-black on white (and the reverse in dark mode),
/// matching the black-and-white logo, with a single deep-teal accent for the
/// countdown, buttons and focus. Red is reserved for warnings and errors.
abstract final class AppTheme {
  // Accent: deep teal. #0F766E on white is ~5.4:1 (WCAG AA for text);
  // the lighter dark-mode tone keeps the same hue.
  static const Color _tealLight = Color(0xFF0F766E);
  static const Color _tealDark = Color(0xFF5EC4B8);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final accent = isLight ? _tealLight : _tealDark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _tealLight,
          brightness: brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.neutral,
        ).copyWith(
          primary: accent,
          onPrimary: isLight ? Colors.white : const Color(0xFF00201D),
          surface: isLight ? Colors.white : const Color(0xFF0E1012),
          onSurface: isLight
              ? const Color(0xFF111315)
              : const Color(0xFFECEEEF),
          onSurfaceVariant: isLight
              ? const Color(0xFF5B6166)
              : const Color(0xFFA3A9AE),
          surfaceContainerLowest: isLight
              ? Colors.white
              : const Color(0xFF0A0B0C),
          surfaceContainerLow: isLight
              ? const Color(0xFFF6F7F7)
              : const Color(0xFF15181A),
          surfaceContainer: isLight
              ? const Color(0xFFF1F2F3)
              : const Color(0xFF1A1D20),
          surfaceContainerHigh: isLight
              ? const Color(0xFFEBEDEE)
              : const Color(0xFF212528),
          surfaceContainerHighest: isLight
              ? const Color(0xFFE3E6E8)
              : const Color(0xFF2A2E31),
          outline: isLight ? const Color(0xFF8A9095) : const Color(0xFF6E757A),
          outlineVariant: isLight
              ? const Color(0xFFDCE0E2)
              : const Color(0xFF2E3336),
          secondaryContainer: isLight
              ? const Color(0xFFE3F1EF)
              : const Color(0xFF16302D),
          onSecondaryContainer: isLight
              ? const Color(0xFF0B3B37)
              : const Color(0xFFCDE9E5),
          error: isLight ? const Color(0xFFC62828) : const Color(0xFFFF8A80),
        );

    final base = ThemeData(colorScheme: scheme);
    final text = base.textTheme;
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.onSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.surface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.onSurface,
        foregroundColor: scheme.surface,
        elevation: 2,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Finite width: Size.fromHeight would force infinite width and
          // crash buttons placed in a Row.
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          // Finite width: Size.fromHeight would force infinite width and
          // crash buttons placed in a Row.
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20),
      ),
    );
  }
}
