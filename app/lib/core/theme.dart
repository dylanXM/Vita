import 'package:flutter/material.dart';

/// Vita design system — a WeChat-inspired modern visual language.
///
/// White surfaces on a light grey canvas, the brand green accent, soft card
/// shadows, pill actions and generous spacing. Every page pulls from the
/// tokens below so the app stays visually consistent.

class VitaColors {
  VitaColors._();

  /// Brand / accent green (WeChat green).
  static const Color green = Color(0xFF07C160);

  /// Pressed / darker green.
  static const Color greenDark = Color(0xFF06AD56);

  /// Light green tint for selected chips and icon backgrounds.
  static const Color greenTint = Color(0xFFE3F8EC);

  /// User message bubble green.
  static const Color bubbleGreen = Color(0xFF95EC69);

  /// Destructive red (sign out, negative amounts).
  static const Color red = Color(0xFFFA5151);

  /// Page background.
  static const Color pageBg = Color(0xFFF5F6F7);

  /// White surface.
  static const Color surface = Colors.white;

  /// Hairline dividers and borders.
  static const Color divider = Color(0xFFECECEC);

  /// Primary text.
  static const Color text = Color(0xFF191919);

  /// Secondary text.
  static const Color subText = Color(0xFF888888);

  /// Hint text.
  static const Color hint = Color(0xFFBBBBBB);

  /// Unselected tab icon.
  static const Color tabInactive = Color(0xFF8A8A8A);

  /// Brand gradient for hero surfaces (profile header, balance card, mark).
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF12C56C), Color(0xFF059457)],
  );
}

class VitaRadius {
  VitaRadius._();

  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double pill = 999;
}

class VitaShadow {
  VitaShadow._();

  /// Subtle card elevation (WeChat 8.0 style).
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, 2)),
  ];

  /// Slightly stronger elevation for floating elements.
  static const List<BoxShadow> float = [
    BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 6)),
  ];
}

class VitaText {
  VitaText._();

  static const TextStyle display = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    color: VitaColors.text,
    height: 1.2,
  );

  static const TextStyle pageTitle = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: VitaColors.text,
    height: 1.25,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: VitaColors.text,
  );

  static const TextStyle title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: VitaColors.text,
  );

  static const TextStyle body = TextStyle(
    fontSize: 16,
    color: VitaColors.text,
    height: 1.4,
  );

  static const TextStyle sub = TextStyle(
    fontSize: 13,
    color: VitaColors.subText,
    height: 1.4,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11,
    color: VitaColors.subText,
  );
}

class VitaTheme {
  VitaTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: VitaColors.green,
        primary: VitaColors.green,
        surface: VitaColors.surface,
      ),
      scaffoldBackgroundColor: VitaColors.pageBg,
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: VitaColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: VitaColors.text,
        titleTextStyle: TextStyle(
          color: VitaColors.text,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: VitaColors.green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: VitaColors.green.withValues(alpha: 0.4),
          minimumSize: const Size.fromHeight(50),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VitaRadius.pill)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: VitaColors.text,
          side: const BorderSide(color: VitaColors.divider),
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VitaRadius.pill)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: VitaColors.green,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VitaRadius.md),
          borderSide: const BorderSide(color: VitaColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VitaRadius.md),
          borderSide: const BorderSide(color: VitaColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VitaRadius.md),
          borderSide: const BorderSide(color: VitaColors.green, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VitaRadius.md),
          borderSide: const BorderSide(color: VitaColors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VitaRadius.md),
          borderSide: const BorderSide(color: VitaColors.red, width: 1.5),
        ),
        hintStyle: const TextStyle(color: VitaColors.hint, fontSize: 15),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: VitaColors.pageBg,
        selectedColor: VitaColors.greenTint,
        checkmarkColor: VitaColors.green,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: VitaColors.divider),
        labelStyle: const TextStyle(fontSize: 14, color: VitaColors.text),
      ),
      dividerTheme: const DividerThemeData(
        color: VitaColors.divider,
        thickness: 0.5,
        space: 0.5,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF3B3B3B),
        contentTextStyle: TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: VitaColors.text),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
    );
  }
}
