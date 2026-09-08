import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:shared_preferences/shared_preferences.dart';

/// Design tokens for one brightness, ported 1:1 from the website's
/// Tailwind tokens (public_html/input.css + config/ranks.php +
/// components/personality_badge.php). The inline comments on each color
/// name the source class. Every widget reads colors through
/// Theme.of(context).extension<EnclavdPalette>(), so flipping between the
/// dark and light instances repaints the whole app.
@immutable
class EnclavdPalette extends ThemeExtension<EnclavdPalette> {
  const EnclavdPalette({
    required this.background,
    required this.card,
    required this.cardSecondary,
    required this.border,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.link,
    required this.primaryButton,
    required this.primaryButtonHover,
    required this.primaryButtonText,
    required this.likeActive,
    required this.warning,
    required this.error,
    required this.rankNameColors,
    required this.personalityGroupColors,
  });

  final Color background; // page bg (gray-950 / gray-100)
  final Color card; // card + drawer + input fill (gray-900 / gray-50)
  final Color cardSecondary; // chips, secondary fills (gray-800 / gray-200)
  final Color border; // card borders (gray-800 / gray-200)
  final Color divider; // hairline dividers (gray-700 / gray-200)
  final Color textPrimary; // body + headings (white / gray-900)
  final Color textSecondary; // secondary text (gray-400 / gray-600)
  final Color link; // links + icon accents (blue-400 / blue-600)
  final Color primaryButton; // button fill (blue-500 / blue-600)
  final Color primaryButtonHover; // donate hover (blue-400 / blue-700)
  final Color primaryButtonText; // button label (gray-900 / white)
  final Color likeActive; // red-400 / red-500
  final Color warning; // yellow-400 / amber-700
  final Color error; // red-400 / red-600

  /// Rank -> name color (config/ranks.php `name_color`). The light map
  /// steps 400-level accents down to 600/700s so names keep contrast on
  /// light cards.
  final Map<String, Color> rankNameColors;

  /// Personality group (NT/NF/SF/ST) accent, 600s on dark, 700s on light.
  final Map<String, Color> personalityGroupColors;

  static const dark = EnclavdPalette(
    background: Color(0xFF030712), // gray-950
    card: Color(0xFF111827), // gray-900
    cardSecondary: Color(0xFF1F2937), // gray-800
    border: Color(0xFF1F2937), // gray-800
    divider: Color(0xFF374151), // gray-700
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF9CA3AF), // gray-400
    link: Color(0xFF60A5FA), // blue-400
    primaryButton: Color(0xFF3B82F6), // blue-500
    primaryButtonHover: Color(0xFF60A5FA), // blue-400
    primaryButtonText: Color(0xFF111827), // gray-900
    likeActive: Color(0xFFF87171), // red-400
    warning: Color(0xFFFACC15), // yellow-400
    error: Color(0xFFF87171), // red-400
    rankNameColors: {
      'SysOp': Color(0xFFC084FC), // purple-400
      'Admin': Color(0xFFF87171), // red-400
      'Officer': Color(0xFF60A5FA), // blue-400
      'Founding Member': Color(0xFFFACC15), // yellow-400
      'Labcoat': Color(0xFFFFFFFF), // white
      'Member': Color(0xFF9CA3AF), // gray-400
      'Blocked': Color(0xFF737373), // neutral-500 (line-through in CSS)
    },
    personalityGroupColors: {
      'NT': Color(0xFFC026D3), // fuchsia-600
      'NF': Color(0xFFD97706), // amber-600
      'SF': Color(0xFFDC2626), // red-600
      'ST': Color(0xFF2563EB), // blue-600
    },
  );

  static const light = EnclavdPalette(
    // Cool-gray ladder mirrored from the dark stack: page gray-100,
    // cards gray-50 (never pure white), chips/borders gray-200.
    background: Color(0xFFF3F4F6), // gray-100
    card: Color(0xFFF9FAFB), // gray-50
    cardSecondary: Color(0xFFE5E7EB), // gray-200
    border: Color(0xFFE5E7EB), // gray-200
    divider: Color(0xFFE5E7EB), // gray-200
    textPrimary: Color(0xFF111827), // gray-900
    textSecondary: Color(0xFF4B5563), // gray-600
    link: Color(0xFF2563EB), // blue-600
    primaryButton: Color(0xFF2563EB), // blue-600 (white label ~5:1)
    primaryButtonHover: Color(0xFF1D4ED8), // blue-700
    primaryButtonText: Color(0xFFFFFFFF), // white
    likeActive: Color(0xFFEF4444), // red-500
    warning: Color(0xFFB45309), // amber-700
    error: Color(0xFFDC2626), // red-600
    rankNameColors: {
      'SysOp': Color(0xFF9333EA), // purple-600
      'Admin': Color(0xFFDC2626), // red-600
      'Officer': Color(0xFF2563EB), // blue-600
      'Founding Member': Color(0xFFB45309), // amber-700
      'Labcoat': Color(0xFF374151), // gray-700
      'Member': Color(0xFF4B5563), // gray-600
      'Blocked': Color(0xFF525252), // neutral-600
    },
    personalityGroupColors: {
      'NT': Color(0xFFA21CAF), // fuchsia-700
      'NF': Color(0xFFB45309), // amber-700
      'SF': Color(0xFFB91C1C), // red-700
      'ST': Color(0xFF1D4ED8), // blue-700
    },
  );

  /// The palette the current context paints with. Falls back to dark for
  /// bare test harnesses that never mount the Enclavd theme (the old
  /// static colors behaved the same way).
  static EnclavdPalette of(BuildContext context) =>
      Theme.of(context).extension<EnclavdPalette>() ?? dark;

  Color rankName(String rank) =>
      rankNameColors[rank] ?? rankNameColors['Member']!;

  /// Maps the server's Tailwind name_color class to our palette.
  Color rankNameFromCss(String cssClass) {
    if (cssClass.contains('purple')) return rankName('SysOp');
    if (cssClass.contains('red')) return rankName('Admin');
    if (cssClass.contains('blue')) return rankName('Officer');
    if (cssClass.contains('yellow')) return rankName('Founding Member');
    return rankName('Member');
  }

  /// Personality type -> group accent. A type like INTJ colors from its
  /// 2nd + 3rd letters (NT), matching the site's badge groups.
  Color? personalityColor(String? type) {
    if (type == null || type.length != 4) return null;
    final t = type.toUpperCase();
    return personalityGroupColors[t.substring(1, 3)];
  }

  @override
  EnclavdPalette copyWith({
    Color? background,
    Color? card,
    Color? cardSecondary,
    Color? border,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? link,
    Color? primaryButton,
    Color? primaryButtonHover,
    Color? primaryButtonText,
    Color? likeActive,
    Color? warning,
    Color? error,
    Map<String, Color>? rankNameColors,
    Map<String, Color>? personalityGroupColors,
  }) {
    return EnclavdPalette(
      background: background ?? this.background,
      card: card ?? this.card,
      cardSecondary: cardSecondary ?? this.cardSecondary,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      link: link ?? this.link,
      primaryButton: primaryButton ?? this.primaryButton,
      primaryButtonHover: primaryButtonHover ?? this.primaryButtonHover,
      primaryButtonText: primaryButtonText ?? this.primaryButtonText,
      likeActive: likeActive ?? this.likeActive,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      rankNameColors: rankNameColors ?? this.rankNameColors,
      personalityGroupColors:
          personalityGroupColors ?? this.personalityGroupColors,
    );
  }

  @override
  EnclavdPalette lerp(ThemeExtension<EnclavdPalette>? other, double t) {
    if (other is! EnclavdPalette) return this;
    // The maps hold semantic accents; swap them as a unit at the midpoint
    // instead of lerping each entry.
    final maps = t < 0.5 ? this : other;
    return EnclavdPalette(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardSecondary: Color.lerp(cardSecondary, other.cardSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      link: Color.lerp(link, other.link, t)!,
      primaryButton: Color.lerp(primaryButton, other.primaryButton, t)!,
      primaryButtonHover:
          Color.lerp(primaryButtonHover, other.primaryButtonHover, t)!,
      primaryButtonText:
          Color.lerp(primaryButtonText, other.primaryButtonText, t)!,
      likeActive: Color.lerp(likeActive, other.likeActive, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      rankNameColors: maps.rankNameColors,
      personalityGroupColors: maps.personalityGroupColors,
    );
  }
}

/// Shorthand: `context.enclavd.background` instead of digging the
/// extension out of the theme.
extension EnclavdThemeContext on BuildContext {
  EnclavdPalette get enclavd => EnclavdPalette.of(this);
}

/// Persisted brightness choice. Dark matches the site, so it is the
/// default; the notifier drives the MaterialApp rebuild on switch.
class ThemePrefs {
  ThemePrefs._();

  static const lightModeKey = 'light_mode';

  /// Live value. Read once at startup, then flipped by the settings row.
  static final lightMode = ValueNotifier<bool>(false);

  /// Loads the stored choice before runApp so the first frame is right.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    lightMode.value = prefs.getBool(lightModeKey) ?? false;
  }

  /// Applies immediately and persists.
  static Future<void> setLightMode(bool value) async {
    lightMode.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(lightModeKey, value);
  }
}

/// Builds the theme for one brightness. `buildEnclavdTheme()` (no args)
/// keeps meaning "the dark design" for tests and callers that predate the
/// light mode.
ThemeData buildEnclavdTheme({bool light = false}) {
  final pal = light ? EnclavdPalette.light : EnclavdPalette.dark;
  final base = ThemeData(
    brightness: light ? Brightness.light : Brightness.dark,
    scaffoldBackgroundColor: pal.background,
    fontFamily: 'Montserrat',
    colorScheme: light
        ? const ColorScheme.light(
            // White label on the deeper blue-600 fill; scheme-primary
            // widgets (FilledButton defaults, switches, checks) inherit.
            primary: Color(0xFF2563EB), // blue-600
            onPrimary: Color(0xFFFFFFFF), // white
            secondary: Color(0xFF1D4ED8), // blue-700
            surface: Color(0xFFF9FAFB), // gray-50
            error: Color(0xFFDC2626), // red-600
          )
        : const ColorScheme.dark(
            primary: Color(0xFF3B82F6), // blue-500
            onPrimary: Color(0xFF111827), // gray-900
            secondary: Color(0xFF60A5FA), // blue-400
            surface: Color(0xFF111827), // gray-900
            error: Color(0xFFF87171), // red-400
          ),
    extensions: [pal],
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: pal.background,
      elevation: 0,
      foregroundColor: pal.textPrimary,
      centerTitle: false,
      // Dark theme wants light status-bar icons and vice versa.
      systemOverlayStyle:
          light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
    ),
    cardTheme: CardThemeData(
      color: pal.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16), // rounded-2xl
        side: BorderSide(color: pal.border, width: 2),
      ),
      margin: const EdgeInsets.only(bottom: 24),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: pal.primaryButton,
        foregroundColor: pal.primaryButtonText,
        disabledBackgroundColor: pal.primaryButton.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8), // rounded-lg
        ),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: pal.link,
        textStyle: const TextStyle(fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: pal.card,
      hintStyle: TextStyle(color: pal.textSecondary),
      labelStyle: TextStyle(color: pal.textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: pal.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: pal.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: pal.link, width: 2),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: pal.divider,
      thickness: 1,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: pal.textPrimary,
      displayColor: pal.textPrimary,
    ),
  );
}
