import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app's color roles. Access via `context.colors` — reading it registers
/// a dependency on Theme, so widgets rebuild when the theme mode changes.
class AppPalette {
  final Color background;
  final Color primarySurface;
  final Color secondarySurface;
  final Color primaryAccent;
  final Color secondaryAccent;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;

  /// Foreground for content sitting on a [primaryAccent] background
  /// (button labels, selected chips). Inverts with the accent.
  final Color onAccent;

  const AppPalette({
    required this.background,
    required this.primarySurface,
    required this.secondarySurface,
    required this.primaryAccent,
    required this.secondaryAccent,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.onAccent,
  });

  static const light = AppPalette(
    background: Color(0xFFF7F7F5),
    primarySurface: Color(0xFFFFFFFF),
    secondarySurface: Color(0xFFEFEFEF),
    primaryAccent: Color(0xFF111111),
    secondaryAccent: Color(0xFF5C5C5C),
    border: Color(0xFFE4E4E7),
    textPrimary: Color(0xFF111111),
    textSecondary: Color(0xFF666666),
    onAccent: Color(0xFFFFFFFF),
  );

  static const dark = AppPalette(
    background: Color(0xFF141414),
    primarySurface: Color(0xFF1E1E1E),
    secondarySurface: Color(0xFF2A2A2A),
    primaryAccent: Color(0xFFF5F5F5),
    secondaryAccent: Color(0xFFB0B0B0),
    border: Color(0xFF2A2A2A),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xFF9A9A9A),
    onAccent: Color(0xFF141414),
  );
}

extension ThemeColors on BuildContext {
  AppPalette get colors => Theme.of(this).brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;
}

class AppTheme {
  static ThemeData get lightTheme => _themeFor(AppPalette.light, Brightness.light);
  static ThemeData get darkTheme => _themeFor(AppPalette.dark, Brightness.dark);

  static ThemeData _themeFor(AppPalette p, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: p.background,
      primaryColor: p.primaryAccent,
      colorScheme: brightness == Brightness.light
          ? ColorScheme.light(
              primary: p.primaryAccent,
              secondary: p.secondaryAccent,
              surface: p.primarySurface,
              onPrimary: p.primarySurface,
              onSurface: p.textPrimary,
            )
          : ColorScheme.dark(
              primary: p.primaryAccent,
              secondary: p.secondaryAccent,
              surface: p.primarySurface,
              onPrimary: p.background,
              onSurface: p.textPrimary,
            ),
      textTheme: GoogleFonts.interTextTheme().copyWith(
        displayLarge: GoogleFonts.inter(
          color: p.textPrimary,
          fontWeight: FontWeight.bold,
          letterSpacing: -1.0,
        ),
        displayMedium: GoogleFonts.inter(
          color: p.textPrimary,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        headlineLarge: GoogleFonts.inter(
          color: p.textPrimary,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        headlineMedium: GoogleFonts.inter(
          color: p.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: GoogleFonts.inter(
          color: p.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: GoogleFonts.inter(color: p.textPrimary),
        bodyMedium: GoogleFonts.inter(color: p.textSecondary),
        labelLarge: GoogleFonts.inter(
          color: p.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: p.primaryAccent),
        titleTextStyle: TextStyle(
          color: p.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
