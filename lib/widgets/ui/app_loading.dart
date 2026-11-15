import 'package:flutter/material.dart';

import '../../theme/enclavd_theme.dart';

/// The app's spinner. One size, one stroke, one colour.
class AppSpinner extends StatelessWidget {
  const AppSpinner({super.key, this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(
          color ?? context.enclavd.textSecondary,
        ),
      ),
    );
  }
}

/// A breathing placeholder block used by list/card skeletons.
class AppSkeletonBox extends StatefulWidget {
  const AppSkeletonBox({
    super.key,
    this.height = 14,
    this.width,
    this.radius = 6,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  State<AppSkeletonBox> createState() => _AppSkeletonBoxState();
}

class _AppSkeletonBoxState extends State<AppSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.enclavd.cardSecondary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base.withValues(
            alpha: 0.55 + 0.35 * Curves.easeInOut.transform(_controller.value),
          ),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Simple centered busy state for whole panels.
class AppBusy extends StatelessWidget {
  const AppBusy({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppSpinner(size: 22),
          if (label != null) ...[
            const SizedBox(height: 10),
            Text(
              label!,
              style: TextStyle(
                color: context.enclavd.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
