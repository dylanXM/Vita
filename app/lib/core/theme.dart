import 'package:flutter/material.dart';

/// Vita design system — a WeChat-inspired modern visual language with
/// light and dark palettes.
///
/// White (or near-black) grouped surfaces on a soft canvas, the brand green
/// accent, hairline separators and compact spacing. Every page resolves its
/// colors through `context.vita`, which returns the [VitaThemeData] matching
/// the current theme brightness — so light/dark/system modes and live system
/// brightness changes re-render the whole app automatically.

class VitaThemeData {
  const VitaThemeData({
    required this.brightness,
    required this.green,
    required this.greenDark,
    required this.greenTint,
    required this.bubbleGreen,
    required this.red,
    required this.pageBg,
    required this.surface,
    required this.divider,
    required this.chevron,
    required this.text,
    required this.subText,
    required this.hint,
    required this.tabInactive,
    required this.glass,
    required this.glassRing,
    required this.glassShadow,
    required this.selectionPill,
    required this.shimmerA,
    required this.shimmerB,
  });

  /// Light palette (default).
  static const VitaThemeData light = VitaThemeData(
    brightness: Brightness.light,
    green: Color(0xFF07C160),
    greenDark: Color(0xFF06AD56),
    greenTint: Color(0xFFE3F8EC),
    bubbleGreen: Color(0xFF95EC69),
    red: Color(0xFFFA5151),
    pageBg: Color(0xFFF5F6F7),
    surface: Colors.white,
    divider: Color(0xFFECECEC),
    chevron: Color(0xFFCCCCCC),
    text: Color(0xFF191919),
    subText: Color(0xFF888888),
    hint: Color(0xFFBBBBBB),
    tabInactive: Color(0xCC1A1A1A),
    glass: Color(0xA6FFFFFF),
    glassRing: Color(0xFFDBDBDB),
    glassShadow: Color(0x26000000),
    selectionPill: Color(0xCCE2E2E2),
    shimmerA: Color(0xFFF2F3F5),
    shimmerB: Color(0xFFE4E6E9),
  );

  /// Dark palette.
  static const VitaThemeData dark = VitaThemeData(
    brightness: Brightness.dark,
    green: Color(0xFF0ACB72),
    greenDark: Color(0xFF08A85E),
    greenTint: Color(0x330ACB72),
    bubbleGreen: Color(0xFF3E9B4F),
    red: Color(0xFFFF6B6B),
    pageBg: Color(0xFF0F0F11),
    surface: Color(0xFF1C1C1E),
    divider: Color(0xFF2C2C2E),
    chevron: Color(0xFF5A5A5E),
    text: Color(0xFFF5F5F7),
    subText: Color(0xFF98989E),
    hint: Color(0xFF6E6E73),
    tabInactive: Color(0xCCEDEDED),
    glass: Color(0x8C2C2C2E),
    glassRing: Color(0xFF48484A),
    glassShadow: Color(0x66000000),
    selectionPill: Color(0xCC3A3A3C),
    shimmerA: Color(0xFF2A2A2C),
    shimmerB: Color(0xFF3A3A3C),
  );

  final Brightness brightness;

  /// Brand / accent green (WeChat green).
  final Color green;

  /// Pressed / darker green.
  final Color greenDark;

  /// Light green tint for selected chips and icon backgrounds.
  final Color greenTint;

  /// User message bubble green.
  final Color bubbleGreen;

  /// Destructive red (sign out, negative amounts).
  final Color red;

  /// Page background.
  final Color pageBg;

  /// Card / bar surface.
  final Color surface;

  /// Hairline dividers and borders.
  final Color divider;

  /// Trailing list chevron.
  final Color chevron;

  /// Primary text.
  final Color text;

  /// Secondary text.
  final Color subText;

  /// Hint text.
  final Color hint;

  /// Unselected tab icon/label (iOS 27: near-opaque black, darkened by glass).
  final Color tabInactive;

  /// Liquid Glass capsule fill (translucent).
  final Color glass;

  /// Liquid Glass edge ring.
  final Color glassRing;

  /// Liquid Glass drop shadow.
  final Color glassShadow;

  /// Selection pill inside the glass tab bar.
  final Color selectionPill;

  /// Shimmer placeholder colors.
  final Color shimmerA;
  final Color shimmerB;

  /// Tokens matching the current theme brightness of [context].
  static VitaThemeData of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// Brand gradient for hero surfaces (profile header, balance card, mark).
  LinearGradient get brandGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF12C56C), Color(0xFF059457)],
      );
}

extension VitaTokens on BuildContext {
  /// Resolved Vita design tokens for the current theme brightness.
  ///
  /// Use this instead of hard-coded colors: `context.vita.text`,
  /// `context.vita.surface`, ... It re-renders automatically when the
  /// app or system switches between light and dark.
  VitaThemeData get vita => VitaThemeData.of(this);
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

/// Standard Vita text styles, resolved for the current brightness.
///
/// Access through the tokens: `context.vita.pageTitle`, `context.vita.sub`, ...
extension VitaTextStyle on VitaThemeData {
  TextStyle get display => TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: text,
        height: 1.2,
      );

  TextStyle get pageTitle => TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: text,
        height: 1.25,
      );

  TextStyle get sectionTitle => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: text,
      );

  TextStyle get title => TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: text,
      );

  TextStyle get body => TextStyle(
        fontSize: 16,
        color: text,
        height: 1.4,
      );

  TextStyle get sub => TextStyle(
        fontSize: 13,
        color: subText,
        height: 1.4,
      );

  TextStyle get caption => TextStyle(
        fontSize: 11,
        color: subText,
      );
}

class VitaTheme {
  VitaTheme._();

  static ThemeData get light => _base(VitaThemeData.light);
  static ThemeData get dark => _base(VitaThemeData.dark);

  static ThemeData _base(VitaThemeData t) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: t.green,
        brightness: t.brightness,
        primary: t.green,
        surface: t.surface,
      ),
      scaffoldBackgroundColor: t.pageBg,
    );
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: t.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: t.divider, width: 0.5)),
        centerTitle: true,
        foregroundColor: t.text,
        titleTextStyle: TextStyle(
          color: t.text,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: t.green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: t.green.withValues(alpha: 0.4),
          minimumSize: const Size.fromHeight(50),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.text,
          side: BorderSide(color: t.divider),
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.green,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: t.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: t.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: t.green, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: t.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: t.red, width: 1.5),
        ),
        hintStyle: TextStyle(color: t.hint, fontSize: 15),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: t.pageBg,
        selectedColor: t.greenTint,
        checkmarkColor: t.green,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: t.divider),
        labelStyle: TextStyle(fontSize: 14, color: t.text),
      ),
      dividerTheme: DividerThemeData(
        color: t.divider,
        thickness: 0.5,
        space: 0.5,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF3B3B3B),
        contentTextStyle: TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        titleTextStyle:
            TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: t.text),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surface,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
    );
  }
}
