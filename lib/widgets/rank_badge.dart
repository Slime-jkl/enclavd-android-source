import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

/// The site's rank badge (getRankStyles()['badge'] from config/ranks.php):
/// a tiny pill with the rank's FA icon + name, rank-colored background and
/// border, dark text. The site renders it at text-xs * scale(0.75); here
/// ~10px reads cleanly on a phone without the web's transform hack.
/// Used in the likers sheet and the profile header.
class RankBadge extends StatelessWidget {
  const RankBadge({super.key, required this.rank});

  final String rank;

  static const Map<String, _RankBadgeStyle> _styles = {
    // badge_bg / badge_border / badge_text / icon (config/ranks.php).
    'SysOp': _RankBadgeStyle(
      bg: Color(0xFF7E22CE), // bg-purple-700
      border: Color(0xFFA855F7), // border-purple-500
      text: Color(0xFF030712), // text-gray-950
      icon: FontAwesomeIcons.code, // fa-code
    ),
    'Admin': _RankBadgeStyle(
      bg: Color(0xFFDC2626), // bg-red-600
      border: Color(0xFFEF4444), // border-red-500
      text: Color(0xFF030712),
      icon: FontAwesomeIcons.shieldHalved, // fa-shield-alt (FA6 name)
    ),
    'Officer': _RankBadgeStyle(
      bg: Color(0xFF2563EB), // bg-blue-600
      border: Color(0xFF3B82F6), // border-blue-500
      text: Color(0xFF030712),
      icon: FontAwesomeIcons.gavel, // fa-gavel
    ),
    'Founding Member': _RankBadgeStyle(
      bg: Color(0xFFCA8A04), // bg-yellow-600
      border: Color(0xFFEAB308), // border-yellow-500
      text: Color(0xFF030712),
      icon: FontAwesomeIcons.crown, // fa-crown
    ),
    'Labcoat': _RankBadgeStyle(
      bg: Color(0x4DD1D5DB), // bg-gray-300/30
      border: Color(0x66D1D5DB), // border-gray-300/40
      text: Color(0xFF030712),
      icon: FontAwesomeIcons.flask, // fa-flask
    ),
    'Member': _RankBadgeStyle(
      bg: Color(0xFF030712), // bg-gray-950
      border: Color(0xFF1F2937), // border-gray-800
      text: Color(0xFF6B7280), // text-gray-500
      icon: FontAwesomeIcons.user, // fa-user
    ),
    'Blocked': _RankBadgeStyle(
      bg: Color(0xFF0A0A0A), // bg-neutral-950
      border: Color(0xFF262626), // border-neutral-800
      text: Color(0xFF737373), // text-neutral-500
      icon: FontAwesomeIcons.ban, // fa-ban
    ),
  };

  @override
  Widget build(BuildContext context) {
    final style = _styles[rank] ?? _styles['Member']!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(4), // rounded
        border: Border.all(color: style.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(style.icon, size: 9, color: style.text),
          const SizedBox(width: 3),
          Text(
            rank,
            style: TextStyle(
              fontSize: 10,
              height: 1.1,
              fontWeight: FontWeight.w600, // font-medium
              color: style.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankBadgeStyle {
  const _RankBadgeStyle({
    required this.bg,
    required this.border,
    required this.text,
    required this.icon,
  });

  final Color bg;
  final Color border;
  final Color text;
  final FaIconData icon;
}
