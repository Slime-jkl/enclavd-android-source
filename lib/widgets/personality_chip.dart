import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';

/// The site's personality badge (MBTI) as a small pill tinted by the
/// personality group color — the native counterpart of
/// render_personality_badge(). Shared by the user-menu drawer, search
/// results and the article author row.
class PersonalityChip extends StatelessWidget {
  const PersonalityChip({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final color =
        PersonalityColors.forType(type) ?? EnclavdColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        type,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }
}
