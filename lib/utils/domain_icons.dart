import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

/// Category icon mapping — the site's fa-* class names → FontAwesomeIcons.
///
/// The domain fetcher assigns fa-* names (with fallbacks for unset icons);
/// the API ships them verbatim. This maps the ones the site uses plus
/// sensible defaults; unknown names fall back to fa-folder (the site's
/// own fallback).
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
      return FontAwesomeIcons.folder;
  }
}

/// Category accent color — the site's hex strings ('#60a5fa') → Color.
/// Invalid/empty values fall back to the site's default blue (#60a5fa).
Color domainColorFromHex(String hex) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length != 6) return const Color(0xFF60A5FA);
  final value = int.tryParse(h, radix: 16);
  if (value == null) return const Color(0xFF60A5FA);
  return Color(0xFF000000 | value);
}
