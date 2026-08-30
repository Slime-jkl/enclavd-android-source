import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

/// The web's fa-* class names -> FontAwesomeIcons.
/// All entries are const: Flutter's release builds tree-shake icon fonts
/// and refuse non-constant IconData instances, so server-sent codepoints
/// can't render. New icons need a name-map entry and an app update.
FaIconData domainIconFor(String faClass) {
  switch (faClass) {
    case 'fa-music':
      return FontAwesomeIcons.music;
    case 'fa-masks-theater':
      return FontAwesomeIcons.masksTheater;
    case 'fa-lightbulb':
      return FontAwesomeIcons.lightbulb;
    case 'fa-bullhorn':
      return FontAwesomeIcons.bullhorn;
    case 'fa-futbol':
      return FontAwesomeIcons.futbol;
    case 'fa-film':
      return FontAwesomeIcons.film;
    case 'fa-gamepad':
      return FontAwesomeIcons.gamepad;
    case 'fa-fire':
      return FontAwesomeIcons.fire;
    case 'fa-play':
      return FontAwesomeIcons.play;
    case 'fa-trophy':
      return FontAwesomeIcons.trophy;
    case 'fa-puzzle-piece':
      return FontAwesomeIcons.puzzlePiece;
    case 'fa-globe':
      return FontAwesomeIcons.globe;
    case 'fa-comments':
      return FontAwesomeIcons.comments;
    case 'fa-sitemap':
      return FontAwesomeIcons.sitemap;
    case 'fa-th-large':
      return FontAwesomeIcons.tableCellsLarge;
    case 'fa-angle-right':
      return FontAwesomeIcons.angleRight;
    case 'fa-folder-open':
      return FontAwesomeIcons.folderOpen;
    default:
      return FontAwesomeIcons.globe;
  }
}

Color domainColorFromHex(String hex) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length != 6) return const Color(0xFF60A5FA);
  final value = int.tryParse(h, radix: 16);
  if (value == null) return const Color(0xFF60A5FA);
  return Color(0xFF000000 | value);
}
