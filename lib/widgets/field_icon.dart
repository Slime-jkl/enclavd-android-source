import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// 48x48 icon slot for InputDecoration, glyph centered.
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
