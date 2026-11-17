import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';
import 'ui/app_surface.dart';

/// Pulsing placeholder block, styled like the site's card skeletons.
class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
  });

  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Gentle opacity pulse between the two tones.
        final t = _controller.value;
        // Dark pair: gray-850 tones; light pair: slate-300 -> slate-200.
        final base = widget.baseColor ??
            (light ? const Color(0xFFCBD5E1) : const Color(0xFF1A2333));
        final highlight = widget.highlightColor ??
            (light ? const Color(0xFFE2E8F0) : const Color(0xFF232F44));
        final color = Color.lerp(base, highlight, (t * 2).clamp(0.0, 1.0))!;
        return ColorFiltered(
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A rounded shimmer rectangle (avatar, image block, text line).
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = 6,
    this.shape = BoxShape.rectangle,
  });

  final double? width;
  final double height;
  final double borderRadius;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: context.enclavd.cardSecondary,
          shape: shape,
          borderRadius: shape == BoxShape.circle
              ? null
              : BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

/// Full skeleton of a post card, matching the card's final chrome so the
/// list does not jump when real posts replace the placeholders.
class PostCardSkeleton extends StatelessWidget {
  const PostCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppSurface(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.fromLTRB(14, 12, 14, 6),
      radius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author row: avatar + name line
          Row(
            children: [
              ShimmerBox(width: 36, height: 36, shape: BoxShape.circle),
              SizedBox(width: 10),
              ShimmerBox(width: 120, height: 13),
              Spacer(),
              ShimmerBox(width: 26, height: 11),
            ],
          ),
          SizedBox(height: 14),
          // Content lines
          ShimmerBox(width: double.infinity, height: 13),
          SizedBox(height: 8),
          ShimmerBox(width: double.infinity, height: 13),
          SizedBox(height: 8),
          ShimmerBox(width: 200, height: 13),
          SizedBox(height: 14),
          // Image block
          ShimmerBox(width: double.infinity, height: 140, borderRadius: 10),
          SizedBox(height: 14),
          // Action bar
          Row(
            children: [
              ShimmerBox(width: 18, height: 18, borderRadius: 4),
              SizedBox(width: 30),
              ShimmerBox(width: 18, height: 18, borderRadius: 4),
              SizedBox(width: 30),
              ShimmerBox(width: 18, height: 18, borderRadius: 4),
            ],
          ),
          SizedBox(height: 8),
        ],
      ),
    );
  }
}
