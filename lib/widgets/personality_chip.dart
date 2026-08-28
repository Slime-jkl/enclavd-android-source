import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';

/// The canonical personality badge: uppercase type in its group color.
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
