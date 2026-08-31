import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'fa7_solid_map.dart';

/// Icons rendered dynamically: the server sends the FA6.7 solid codepoint
/// (icon_code / domain_icon_code) parsed from the site's own CSS, and the
/// app renders it against the bundled FA7 solid font. FA6/FA7 codepoints
/// are identical for every shared glyph, so any icon picked in the admin
/// catalog renders without an app update. New domains just work.
///
/// The generated kFa7Solid map is the const keep-list: every glyph is
/// referenced as a constant so release icon tree-shaking keeps the full
/// font (non-const IconData glyphs get stripped and render blank).
FaIconData domainIconFor(String faClass, {int? codePoint}) {
  final special = _fa7Dropped[faClass];
  if (special != null) return special;
  if (codePoint != null && codePoint > 0) {
    return FaIconData(IconData(
      codePoint, // ignore: non_const_argument_for_const_parameter - runtime value
      fontFamily: 'FontAwesomeSolid',
      fontPackage: 'font_awesome_flutter',
    ));
  }
  return kFa7Solid[faClass] ?? FontAwesomeIcons.globe;
}

/// FA6 catalog names whose codepoints Font Awesome 7 removed from the
/// solid font (the glyph is gone, not just renamed) - render the nearest
/// FA7 equivalent instead of a blank box.
const Map<String, FaIconData> _fa7Dropped = {
  'fa-user-alt': FontAwesomeIcons.user,
  'fa-user-large': FontAwesomeIcons.user,
  'fa-user-alt-slash': FontAwesomeIcons.userSlash,
  'fa-user-large-slash': FontAwesomeIcons.userSlash,
  'fa-headphones-alt': FontAwesomeIcons.headphones,
  'fa-headphones-simple': FontAwesomeIcons.headphones,
  'fa-handshake-alt': FontAwesomeIcons.handshake,
  'fa-handshake-simple': FontAwesomeIcons.handshake,
  'fa-handshake-alt-slash': FontAwesomeIcons.handshakeSlash,
  'fa-handshake-simple-slash': FontAwesomeIcons.handshakeSlash,
};

Color domainColorFromHex(String hex) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length != 6) return const Color(0xFF60A5FA);
  final value = int.tryParse(h, radix: 16);
  if (value == null) return const Color(0xFF60A5FA);
  return Color(0xFF000000 | value);
}
