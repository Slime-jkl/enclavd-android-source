import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';

/// THE canonical personality badge — the feed post-card pill (site's
/// render_personality_badge): neutral card background, fully-rounded,
/// the MBTI type in UPPERCASE tinted by its personality group color.
///
/// Every personality badge in the app uses this widget — post cards,
/// the liked-by sheet, search results, the user-menu drawer and the
/// article author row — so the design can never drift again.
class PersonalityChip extends StatelessWidget {
  const PersonalityChip({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final color =
        PersonalityColors.forType(type) ?? EnclavdColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: EnclavdColors.cardSecondary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        type.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
