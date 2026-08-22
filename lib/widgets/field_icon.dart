import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Icon slot for InputDecoration prefixIcon/suffixIcon.
///
/// InputDecorator hands the icon slot the FULL field width as loose
/// constraints. A bare `FaIcon` expands to fill that box and paints its
/// glyph at the top-left (the "icon jammed in the top-left corner of the
/// field" bug — hit repeatedly in this app). This widget keeps the
/// standard 48x48 icon slot (so the input's reserved width and the layout
/// never shift) and centers the glyph inside it via UnconstrainedBox —
/// the same footprint and behavior as the eye IconButton on the suffix
/// side.
class FieldIcon extends StatelessWidget {
  const FieldIcon(this.icon, {super.key, this.size = 18, this.color});

  final FaIconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: UnconstrainedBox(
        alignment: Alignment.center,
        child: FaIcon(icon, size: size, color: color),
      ),
    );
  }
}
