import 'package:flutter/material.dart';

/// VibeShort dark theme — deep navy-black background, white text,
/// cyan primary with a violet accent. Gradients built from
/// [accent] → [accent2] give the cyan-to-violet look used on the
/// splash, logo and CTAs.
class AppTheme {
  AppTheme._();

  static const Color bg = Color(0xFF0A0A12);
  static const Color card = Color(0xFF15151F);
  static const Color accent = Color(0xFF00C2FF); // cyan
  static const Color accent2 = Color(0xFF7C4DFF); // violet
  static const Color muted = Color(0xFF9A97AD);

  /// Primary cyan → violet gradient.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [accent, accent2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: accent,
      secondary: accent2,
      surface: card,
      background: bg,
    );
    return ThemeData(
      useMaterial3: true,
      // Pin the clean default sans explicitly so the app never
      // inherits an exotic system font from the phone's theme.
      fontFamily: 'Roboto',
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        hintStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: bg,
        selectedItemColor: Colors.white,
        unselectedItemColor: muted,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
