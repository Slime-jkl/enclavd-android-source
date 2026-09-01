import 'package:flutter/material.dart';

/// Enclavd design system, ported 1:1 from the website's Tailwind tokens
/// (public_html/input.css + config/ranks.php +
/// components/personality_badge.php). The inline comments on each color
/// name the source class.
class EnclavdColors {
  EnclavdColors._();

  static const background = Color(0xFF030712); // gray-950
  static const card = Color(0xFF111827); // gray-900
  static const cardSecondary = Color(0xFF1F2937); // gray-800
  static const border = Color(0xFF1F2937); // gray-800
  static const divider = Color(0xFF374151); // gray-700
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9CA3AF); // gray-400
  static const link = Color(0xFF60A5FA); // blue-400
  // donate.php pay-btn: bg-blue-500, hover bg-blue-400, text-gray-900.
  static const primaryButton = Color(0xFF3B82F6); // blue-500
  static const primaryButtonHover = Color(0xFF60A5FA); // blue-400
  static const primaryButtonText = Color(0xFF111827); // gray-900
  static const likeActive = Color(0xFFF87171); // red-400
  static const warning = Color(0xFFFACC15); // yellow-400
}

/// Rank -> name color (config/ranks.php `name_color`).
class RankColors {
  RankColors._();

  static const Map<String, Color> colors = {
    'SysOp': Color(0xFFC084FC), // purple-400
    'Admin': Color(0xFFF87171), // red-400
    'Officer': Color(0xFF60A5FA), // blue-400
    'Founding Member': Color(0xFFFACC15), // yellow-400
    'Labcoat': Color(0xFFFFFFFF), // white
    'Member': Color(0xFF9CA3AF), // gray-400
    'Blocked': Color(0xFF737373), // neutral-500 (line-through in CSS)
  };

  static Color forRank(String rank) => colors[rank] ?? colors['Member']!;
}

/// Maps the server's Tailwind name_color class to our palette.
Color rankColorFromCssClass(String cssClass) {
  if (cssClass.contains('purple')) return RankColors.forRank('SysOp');
  if (cssClass.contains('red')) return RankColors.forRank('Admin');
  if (cssClass.contains('blue')) return RankColors.forRank('Officer');
  if (cssClass.contains('yellow')) return RankColors.forRank('Founding Member');
  return RankColors.forRank('Member');
}

/// Personality type -> accent color (components/personality_badge.php).
/// Groups: NT=fuchsia, NF=amber, SJ=red, SP=blue.
class PersonalityColors {
  PersonalityColors._();

  static const Map<String, Color> colors = {
    'INTJ': Color(0xFFC026D3), // fuchsia-600
    'ENTJ': Color(0xFFC026D3),
    'INTP': Color(0xFFC026D3),
    'ENTP': Color(0xFFC026D3),
    'INFJ': Color(0xFFD97706), // amber-600
    'ENFJ': Color(0xFFD97706),
    'INFP': Color(0xFFD97706),
    'ENFP': Color(0xFFD97706),
    'ISFJ': Color(0xFFDC2626), // red-600
    'ESFJ': Color(0xFFDC2626),
    'ISFP': Color(0xFFDC2626),
    'ESFP': Color(0xFFDC2626),
    'ISTJ': Color(0xFF2563EB), // blue-600
    'ESTJ': Color(0xFF2563EB),
    'ISTP': Color(0xFF2563EB),
    'ESTP': Color(0xFF2563EB),
  };

  static Color? forType(String? type) =>
      type == null ? null : colors[type.toUpperCase()];
}

ThemeData buildEnclavdTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: EnclavdColors.background,
    fontFamily: 'Montserrat',
    colorScheme: const ColorScheme.dark(
      primary: EnclavdColors.primaryButton,
      // Dark text on the light blue (pay-btn style); FilledButton and the
      // like derive their foreground from onPrimary.
      onPrimary: EnclavdColors.primaryButtonText,
      secondary: EnclavdColors.link,
      surface: EnclavdColors.card,
      error: Color(0xFFF87171),
    ),
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: EnclavdColors.background,
      elevation: 0,
      foregroundColor: EnclavdColors.textPrimary,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: EnclavdColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16), // rounded-2xl
        side: const BorderSide(color: EnclavdColors.border, width: 2),
      ),
      margin: const EdgeInsets.only(bottom: 24),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: EnclavdColors.primaryButton,
        foregroundColor: EnclavdColors.primaryButtonText,
        disabledBackgroundColor:
            EnclavdColors.primaryButton.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8), // rounded-lg
        ),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: EnclavdColors.link,
        textStyle: const TextStyle(fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: EnclavdColors.card,
      hintStyle: const TextStyle(color: EnclavdColors.textSecondary),
      labelStyle: const TextStyle(color: EnclavdColors.textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: EnclavdColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: EnclavdColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: EnclavdColors.link, width: 2),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: EnclavdColors.divider,
      thickness: 1,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: EnclavdColors.textPrimary,
      displayColor: EnclavdColors.textPrimary,
    ),
  );
}
