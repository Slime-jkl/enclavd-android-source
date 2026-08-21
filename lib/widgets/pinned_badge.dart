import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

/// The site's pinned-article badge (articles.php): a red-700 chip with a
/// fire icon + "PINNED", shadowed so it reads over any cover image.
/// Used on the Updates list cards and the article detail hero.
class PinnedBadge extends StatelessWidget {
  const PinnedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFB91C1C), // bg-red-700
        borderRadius: BorderRadius.circular(6), // rounded-md
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(FontAwesomeIcons.fire, size: 9, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'PINNED',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
