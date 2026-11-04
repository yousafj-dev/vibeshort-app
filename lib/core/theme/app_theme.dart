import 'package:flutter/material.dart';

/// VibeShort theming — brand is cyan → violet on deep navy-black
/// (dark, the default) with a light alternative the user can pick
/// in Settings (build 16: Dark / Light mode).
///
/// Chrome colors ([bg], [card], [muted], [text], [hairline]) are
/// getters driven by [lightMode] so every screen that reads them
/// at build time follows the chosen mode; flipping the mode and
/// rebuilding the app (see PrefsService.themeNotifier in main)
/// re-themes the whole UI. Media surfaces that must stay dark in
/// BOTH modes (camera, video editor) use the pinned [bgDark] /
/// [cardDark] / [mutedDark] constants instead.
class AppTheme {
  AppTheme._();

  // ---- Brand (same in both modes) ----
  static const Color accent = Color(0xFF00C2FF); // cyan
  static const Color accent2 = Color(0xFF7C4DFF); // violet

  /// Primary cyan → violet gradient.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [accent, accent2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ---- Dark palette (default; pinned for always-dark surfaces) ----
  static const Color bgDark = Color(0xFF0A0A12);
  static const Color cardDark = Color(0xFF15151F);
  static const Color mutedDark = Color(0xFF9A97AD);
  static const Color textDark = Colors.white;
  static const Color hairlineDark = Color(0x1AFFFFFF);

  // ---- Light palette ----
  static const Color bgLight = Color(0xFFF5F5FA);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color mutedLight = Color(0xFF62617A);
  static const Color textLight = Color(0xFF16161F);
  static const Color hairlineLight = Color(0x1A000000);

  /// False = dark mode (default). Set from the persisted device
  /// preference by PrefsService before the first frame, and on
  /// every Settings change.
  static bool lightMode = false;

  static Color get bg => lightMode ? bgLight : bgDark;
  static Color get card => lightMode ? cardLight : cardDark;
  static Color get muted => lightMode ? mutedLight : mutedDark;

  /// Primary foreground (text / chrome icons) for the mode.
  static Color get text => lightMode ? textLight : textDark;

  /// Hairline dividers / subtle borders for the mode.
  static Color get hairline => lightMode ? hairlineLight : hairlineDark;

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: accent,
      secondary: accent2,
      surface: cardDark,
      background: bgDark,
    );
    return _base(
      scheme: scheme,
      scaffold: bgDark,
      appBarBg: bgDark,
      appBarFg: textDark,
      inputFill: cardDark,
      hint: mutedDark,
      navBg: bgDark,
      navSelected: textDark,
      navUnselected: mutedDark,
      cardColor: cardDark,
      hairline: hairlineDark,
    );
  }

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: accent,
      secondary: accent2,
      surface: cardLight,
      background: bgLight,
    );
    return _base(
      scheme: scheme,
      scaffold: bgLight,
      appBarBg: bgLight,
      appBarFg: textLight,
      // Fields sit on white cards and on the light scaffold:
      // a soft grey-violet well reads clearly on both.
      inputFill: Color(0xFFECECF3),
      hint: mutedLight,
      navBg: bgLight,
      navSelected: textLight,
      navUnselected: mutedLight,
      cardColor: cardLight,
      hairline: hairlineLight,
    );
  }

  static ThemeData _base({
    required ColorScheme scheme,
    required Color scaffold,
    required Color appBarBg,
    required Color appBarFg,
    required Color inputFill,
    required Color hint,
    required Color navBg,
    required Color navSelected,
    required Color navUnselected,
    required Color cardColor,
    required Color hairline,
  }) {
    return ThemeData(
      useMaterial3: true,
      // Pin the clean default sans explicitly so the app never
      // inherits an exotic system font from the phone's theme.
      fontFamily: 'Roboto',
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBg,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: appBarFg),
        actionsIconTheme: IconThemeData(color: appBarFg),
        titleTextStyle: TextStyle(
          color: appBarFg,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        hintStyle: TextStyle(color: hint),
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
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: navBg,
        selectedItemColor: navSelected,
        unselectedItemColor: navUnselected,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        type: BottomNavigationBarType.fixed,
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: cardColor),
      dividerTheme: DividerThemeData(color: hairline, thickness: 1),
    );
  }
}
