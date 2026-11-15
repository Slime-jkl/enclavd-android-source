import 'package:flutter/material.dart';

import '../../theme/enclavd_theme.dart';

/// The single card chrome used across the app.
///
/// Every panel, sheet and dialog body should sit in one of these so radius,
/// border and surface colours never drift apart screen by screen.
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.radius = 12,
    this.color,
    this.borderColor,
    this.border = true,
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final bool border;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: color ?? context.enclavd.card,
        borderRadius: BorderRadius.circular(radius),
        border: border
            ? Border.all(color: borderColor ?? context.enclavd.border)
            : null,
      ),
      child: child,
    );
  }
}

/// A section heading inside a surface ("Strengths", "Trait balance", ...),
/// optionally with a trailing action.
class AppSectionLabel extends StatelessWidget {
  const AppSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      style: TextStyle(
        color: context.enclavd.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
    if (trailing == null) return label;
    return Row(
      children: [Expanded(child: label), trailing!],
    );
  }
}

/// A one-pixel divider that matches the card borders.
class AppDivider extends StatelessWidget {
  const AppDivider({super.key, this.vertical = false, this.indent = 0});

  final bool vertical;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final color = context.enclavd.divider;
    return vertical
        ? Container(width: 1, color: color)
        : Padding(
            padding: EdgeInsets.symmetric(horizontal: indent),
            child: Container(height: 1, color: color),
          );
  }
}
