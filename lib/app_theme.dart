import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF5B7BF2);
  static const Color primaryContainer = Color(0xFFD7E1FF);
  static const Color secondary = Color(0xFF7DA5FF);
  static const Color secondaryContainer = Color(0xFFDDE8FF);
  static const Color background = Color(0xFFF5F7FF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSoft = Color(0xFFF2F5FF);
  static const Color surfaceVariant = Color(0xFFE7ECF9);
  static const Color border = Color(0xFFC8D2E8);
  static const Color textPrimary = Color(0xFF17233A);
  static const Color textSecondary = Color(0xFF52627D);
  static const Color textHint = Color(0xFF8A98B1);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color soft = Color(0xFFEFF4FF);

  static ThemeData lightTheme(double fontScale, {String fontFamily = 'Arial'}) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: primary,
        onPrimary: Colors.white,
        secondary: secondary,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        error: error,
        onError: Colors.white,
        outline: border,
        shadow: Color(0x1F000000),
        inverseSurface: Color(0xFF1E293B),
        inversePrimary: Color(0xFF8BA2F5),
      ),
      scaffoldBackgroundColor: background,
      cardColor: surface,
      dividerColor: border,
      highlightColor: soft,
      splashColor: soft,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          fontFamily: fontFamily,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15 * fontScale,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15 * fontScale,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(fontSize: 15 * fontScale),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: surfaceSoft,
        filled: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary),
        ),
        hintStyle: TextStyle(color: textHint, fontSize: 14 * fontScale),
        labelStyle: TextStyle(color: textSecondary, fontSize: 14 * fontScale),
      ),
      textTheme: TextTheme(
        bodyMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14 * fontScale,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16 * fontScale,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 22 * fontScale,
          color: textPrimary,
          fontWeight: FontWeight.bold,
        ),
        labelLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14 * fontScale,
          color: textPrimary,
        ),
      ),
      dialogTheme: DialogThemeData(backgroundColor: surface),
    );
    return base;
  }

  static ThemeData darkTheme(double fontScale, {String fontFamily = 'Arial'}) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFF90B4FF),
        onPrimary: Color(0xFF0F172A),
        secondary: Color(0xFFA5C5FF),
        onSecondary: Color(0xFF0F172A),
        surface: Color(0xFF111827),
        onSurface: Colors.white,
        error: Color(0xFFF87171),
        onError: Colors.black,
        outline: Color(0xFF475569),
        shadow: Color(0x1F000000),
        inverseSurface: Color(0xFFF8FAFC),
        inversePrimary: Color(0xFF5B7BF2),
      ),
      scaffoldBackgroundColor: const Color(0xFF070E1D),
      cardColor: const Color(0xFF111827),
      dividerColor: const Color(0xFF334155),
      highlightColor: const Color(0xFF1E293B),
      splashColor: const Color(0xFF1E293B),
      appBarTheme: AppBarTheme(
        backgroundColor: Color(0xFF111827),
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          fontFamily: fontFamily,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF5B7BF2),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15 * fontScale,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF93B5FF),
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15 * fontScale,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF93B5FF),
          side: const BorderSide(color: Color(0xFF334155)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(fontSize: 15 * fontScale),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: const Color(0xFF111827),
        filled: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF93B5FF)),
        ),
        hintStyle: TextStyle(
          color: const Color(0xFF94A3B8),
          fontSize: 14 * fontScale,
        ),
        labelStyle: TextStyle(
          color: const Color(0xFFCBD5E1),
          fontSize: 14 * fontScale,
        ),
      ),
      textTheme: TextTheme(
        bodyMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14 * fontScale,
          color: Colors.white,
        ),
        bodyLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16 * fontScale,
          color: Colors.white,
        ),
        titleLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 22 * fontScale,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        labelLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14 * fontScale,
          color: Colors.white,
        ),
      ),
      dialogTheme: DialogThemeData(backgroundColor: const Color(0xFF111827)),
    );
    return base;
  }
}
