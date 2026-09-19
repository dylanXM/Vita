import 'package:flutter/material.dart';

/// WeChat-style visual language: white surfaces, light grey dividers, a green
/// brand accent, rounded avatars and message bubbles. References WeChat's
/// interaction mindset without copying any of its assets or branding.
class VitaColors {
  VitaColors._();

  /// Brand / accent green.
  static const Color green = Color(0xFF07C160);

  /// User message bubble green.
  static const Color bubbleGreen = Color(0xFF95EC69);

  /// Page background (chat surfaces).
  static const Color pageBg = Color(0xFFEDEDED);

  /// Card / white surface.
  static const Color surface = Colors.white;

  /// Light grey dividers.
  static const Color divider = Color(0xFFE5E5E5);

  /// Primary text.
  static const Color text = Color(0xFF191919);

  /// Secondary text.
  static const Color subText = Color(0xFF888888);

  /// Unselected tab icon.
  static const Color tabInactive = Color(0xFF8A8A8A);
}

class VitaTheme {
  VitaTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: false,
      primaryColor: VitaColors.green,
      scaffoldBackgroundColor: VitaColors.pageBg,
      fontFamily: null,
    );
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: VitaColors.green,
        primary: VitaColors.green,
        surface: VitaColors.surface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: VitaColors.surface,
        elevation: 0,
        centerTitle: true,
        foregroundColor: VitaColors.text,
        titleTextStyle: TextStyle(
          color: VitaColors.text,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: VitaColors.divider,
        thickness: 0.5,
        space: 0.5,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: VitaColors.pageBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: VitaColors.subText, fontSize: 15),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: VitaColors.green,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
