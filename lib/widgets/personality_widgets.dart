import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../theme/enclavd_theme.dart';

/// Shared blocks of the personality results layout.
class CardBox extends StatelessWidget {
  const CardBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EnclavdColors.border),
      ),
      child: child,
    );
  }
}

// icon + text list row (site list-disc list-inside).
class BulletList extends StatelessWidget {
  const BulletList({
    super.key,
    required this.icon,
    required this.color,
    required this.items,
  });

  final FaIconData icon;
  final Color color;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: FaIcon(icon, size: 12, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item,
                      style: const TextStyle(fontSize: 13.5, height: 1.4)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// personality-type pill
class PersonalityTypeBadge extends StatelessWidget {
  const PersonalityTypeBadge({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final color = PersonalityColors.forType(type) ??
        EnclavdColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        type,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: color,
        ),
      ),
    );
  }
}

// type card: "The {core traits}" + description + strengths / growth areas
class PersonalityInfoCard extends StatelessWidget {
  const PersonalityInfoCard({
    super.key,
    required this.title,
    required this.description,
    required this.strengths,
    required this.weaknesses,
  });

  final String title;
  final String description;
  final List<String> strengths;
  final List<String> weaknesses;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The $title',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(description,
              style: const TextStyle(
                  color: EnclavdColors.textSecondary, height: 1.45)),
          const SizedBox(height: 16),
          BulletList(
            icon: FontAwesomeIcons.star,
            color: const Color(0xFF4ADE80), // green-400
            items: strengths,
          ),
          const SizedBox(height: 14),
          BulletList(
            icon: FontAwesomeIcons.triangleExclamation,
            color: const Color(0xFFF87171), // red-400
            items: weaknesses,
          ),
        ],
      ),
    );
  }
}

/// One split percentage bar with both side labels
class TraitBar extends StatelessWidget {
  const TraitBar({
    super.key,
    required this.label,
    required this.first,
    required this.firstPercent,
    required this.firstColor,
    required this.second,
    required this.secondColor,
  });

  final String label;
  final String first;
  final int firstPercent;
  final Color firstColor;
  final String second;
  final Color secondColor;

  @override
  Widget build(BuildContext context) {
    final secondPercent = 100 - firstPercent;
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text.rich(TextSpan(children: [
                TextSpan(
                  text: '$firstPercent%',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                    text: '  $first',
                    style: const TextStyle(
                        color: EnclavdColors.textSecondary)),
              ])),
              Text.rich(TextSpan(children: [
                TextSpan(
                  text: '$secondPercent%',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                    text: '  $second',
                    style: const TextStyle(
                        color: EnclavdColors.textSecondary)),
              ])),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: ColoredBox(
                color: const Color(0xFF6B7280), // gray-500 track
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: firstPercent,
                      child: ColoredBox(color: firstColor),
                    ),
                    Expanded(
                      flex: secondPercent,
                      child: ColoredBox(color: secondColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
