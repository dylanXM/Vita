import 'package:flutter/material.dart';

/// Vita design system — a warm, chat-forward visual language with light and
/// dark palettes, plus four switchable brand color schemes (palettes).
///
/// White (or near-black) grouped surfaces on a soft canvas, a brand accent
/// color, hairline separators and compact spacing. Every page resolves its
/// colors through `context.vita`, which returns the [VitaThemeData] matching
/// the current theme brightness **and the user-selected [VitaPalette]** — so
/// light/dark/system mode changes and live palette switches re-render the
/// whole app automatically.
///
/// The palette is carried on the [ThemeData] as a [VitaPaletteToken]
/// extension, so widget tests that only provide `VitaTheme.light` (violet)
/// keep working without registering a settings controller.

/// Switchable brand color schemes. [VitaPalette.violet] is the default.
enum VitaPalette {
  /// Dream Violet — romantic, private (default).
  violet,

  /// Warm Coral — warm, waiting.
  coral,

  /// Dusk Rose — tender, intimate.
  rose,

  /// Lake Teal — calm, dependable.
  teal;

  /// Stable storage key value (persisted in SharedPreferences).
  String get storageKey => name;
}

/// Brand accent colors for one palette at one brightness.
@immutable
class Brand {
  const Brand({
    required this.green,
    required this.greenDark,
    required this.greenTint,
    required this.bubbleGreen,
    required this.gradient,
  });

  final Color green;
  final Color greenDark;
  final Color greenTint;
  final Color bubbleGreen;
  final List<Color> gradient;
}

/// Resolved brand colors for a [VitaPalette].
class VitaBrandColors {
  const VitaBrandColors._(this.light, this.dark);

  final Brand light;
  final Brand dark;

  static const Map<VitaPalette, VitaBrandColors> _table = {
    VitaPalette.violet: VitaBrandColors._(
      Brand(
        green: Color(0xFF7C5CFC),
        greenDark: Color(0xFF6344E8),
        greenTint: Color(0xFFF0EDFF),
        bubbleGreen: Color(0xFFDCD4FF),
        gradient: [Color(0xFF8B6CFF), Color(0xFF5A3AE0)],
      ),
      Brand(
        green: Color(0xFF9D85FF),
        greenDark: Color(0xFF7C5CFC),
        greenTint: Color(0x339D85FF),
        bubbleGreen: Color(0xFF4A3A8F),
        gradient: [Color(0xFFA78BFA), Color(0xFF6344E8)],
      ),
    ),
    VitaPalette.coral: VitaBrandColors._(
      Brand(
        green: Color(0xFFFF6B5B),
        greenDark: Color(0xFFE8543F),
        greenTint: Color(0xFFFFEDE9),
        bubbleGreen: Color(0xFFFFC9BC),
        gradient: [Color(0xFFFF7A5C), Color(0xFFE84A30)],
      ),
      Brand(
        green: Color(0xFFFF8A7A),
        greenDark: Color(0xFFFF6B5B),
        greenTint: Color(0x33FF8A7A),
        bubbleGreen: Color(0xFF7A3A2E),
        gradient: [Color(0xFFFF8A7A), Color(0xFFE8543F)],
      ),
    ),
    VitaPalette.rose: VitaBrandColors._(
      Brand(
        green: Color(0xFFE8557A),
        greenDark: Color(0xFFD13F66),
        greenTint: Color(0xFFFDEAF0),
        bubbleGreen: Color(0xFFF9C7D6),
        gradient: [Color(0xFFF06A90), Color(0xFFC93060)],
      ),
      Brand(
        green: Color(0xFFF2789A),
        greenDark: Color(0xFFE8557A),
        greenTint: Color(0x33F2789A),
        bubbleGreen: Color(0xFF7A3550),
        gradient: [Color(0xFFF2789A), Color(0xFFD13F66)],
      ),
    ),
    VitaPalette.teal: VitaBrandColors._(
      Brand(
        green: Color(0xFF0FB5AE),
        greenDark: Color(0xFF0B9A94),
        greenTint: Color(0xFFE3F7F5),
        bubbleGreen: Color(0xFFB6EBE6),
        gradient: [Color(0xFF14C4BC), Color(0xFF08807C)],
      ),
      Brand(
        green: Color(0xFF35C9C2),
        greenDark: Color(0xFF0FB5AE),
        greenTint: Color(0x3335C9C2),
        bubbleGreen: Color(0xFF1F5A56),
        gradient: [Color(0xFF35C9C2), Color(0xFF0B9A94)],
      ),
    ),
  };

  static VitaBrandColors of(VitaPalette p) => _table[p] ?? _table[VitaPalette.violet]!;
}

/// Carries the active [VitaPalette] on [ThemeData] so `context.vita` can
/// resolve brand colors without reaching for the settings controller.
@immutable
class VitaPaletteToken extends ThemeExtension<VitaPaletteToken> {
  const VitaPaletteToken(this.palette);

  final VitaPalette palette;

  @override
  VitaPaletteToken copyWith({VitaPalette? palette}) =>
      VitaPaletteToken(palette ?? this.palette);

  @override
  VitaPaletteToken lerp(ThemeExtension<VitaPaletteToken>? other, double t) =>
      this;
}

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
    required this.brandGradient,
  });

  /// Light palette for the default (violet) scheme. Kept as a const for
  /// backward compatibility with existing tests and the app boot path.
  static const VitaThemeData light = VitaThemeData(
    brightness: Brightness.light,
    green: Color(0xFF7C5CFC),
    greenDark: Color(0xFF6344E8),
    greenTint: Color(0xFFF0EDFF),
    bubbleGreen: Color(0xFFDCD4FF),
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
    brandGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF8B6CFF), Color(0xFF5A3AE0)],
    ),
  );

  /// Dark palette for the default (violet) scheme.
  static const VitaThemeData dark = VitaThemeData(
    brightness: Brightness.dark,
    green: Color(0xFF9D85FF),
    greenDark: Color(0xFF7C5CFC),
    greenTint: Color(0x339D85FF),
    bubbleGreen: Color(0xFF4A3A8F),
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
    brandGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFA78BFA), Color(0xFF6344E8)],
    ),
  );

  /// Build a light palette for any [palette].
  factory VitaThemeData.lightFor(VitaPalette palette) =>
      VitaThemeData._build(palette, Brightness.light);

  /// Build a dark palette for any [palette].
  factory VitaThemeData.darkFor(VitaPalette palette) =>
      VitaThemeData._build(palette, Brightness.dark);

  factory VitaThemeData._build(VitaPalette palette, Brightness brightness) {
    if (palette == VitaPalette.violet) {
      return brightness == Brightness.light ? light : dark;
    }
    final brand = VitaBrandColors.of(palette);
    final b = brightness == Brightness.light ? brand.light : brand.dark;
    final base = brightness == Brightness.light ? light : dark;
    return VitaThemeData(
      brightness: brightness,
      green: b.green,
      greenDark: b.greenDark,
      greenTint: b.greenTint,
      bubbleGreen: b.bubbleGreen,
      red: base.red,
      pageBg: base.pageBg,
      surface: base.surface,
      divider: base.divider,
      chevron: base.chevron,
      text: base.text,
      subText: base.subText,
      hint: base.hint,
      tabInactive: base.tabInactive,
      glass: base.glass,
      glassRing: base.glassRing,
      glassShadow: base.glassShadow,
      selectionPill: base.selectionPill,
      shimmerA: base.shimmerA,
      shimmerB: base.shimmerB,
      brandGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: b.gradient,
      ),
    );
  }

  final Brightness brightness;

  /// Brand / accent color.
  final Color green;

  /// Pressed / darker brand color.
  final Color greenDark;

  /// Tint for selected chips and icon backgrounds.
  final Color greenTint;

  /// Outgoing (user) message bubble color.
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

  /// Unselected tab icon/label.
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

  /// Brand gradient for hero surfaces.
  final LinearGradient brandGradient;

  /// Tokens matching the current theme brightness and palette of [context].
  static VitaThemeData of(BuildContext context) {
    final ext = Theme.of(context).extension<VitaPaletteToken>();
    final palette = ext?.palette ?? VitaPalette.violet;
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? VitaThemeData.darkFor(palette)
        : VitaThemeData.lightFor(palette);
  }
}

extension VitaTokens on BuildContext {
  /// Resolved Vita design tokens for the current theme brightness and palette.
  ///
  /// Use this instead of hard-coded colors: `context.vita.text`,
  /// `context.vita.surface`, ... It re-renders automatically when the
  /// app switches light/dark or changes palette.
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

  /// Subtle card elevation.
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, 2)),
  ];

  /// Slightly stronger elevation for floating elements.
  static const List<BoxShadow> float = [
    BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 6)),
  ];
}

/// Standard Vita text styles, resolved for the current brightness.
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

  /// Default (violet) light theme — kept for the app boot path and tests.
  static ThemeData get light => lightFor(VitaPalette.violet);
  static ThemeData get dark => darkFor(VitaPalette.violet);

  /// Light [ThemeData] for an explicit [palette].
  static ThemeData lightFor(VitaPalette palette) =>
      _base(VitaThemeData.lightFor(palette), palette);

  /// Dark [ThemeData] for an explicit [palette].
  static ThemeData darkFor(VitaPalette palette) =>
      _base(VitaThemeData.darkFor(palette), palette);

  static ThemeData _base(VitaThemeData t, VitaPalette palette) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: t.green,
        brightness: t.brightness,
        primary: t.green,
        surface: t.surface,
      ),
      scaffoldBackgroundColor: t.pageBg,
      extensions: [VitaPaletteToken(palette)],
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
