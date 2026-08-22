import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';

/// A pulsing placeholder block, styled like the site's card skeletons
/// (gray-850 fill with a soft highlight sweep). Used while posts, images
/// and avatars load so the feed never shows empty space or jank.
///
/// Performance: one AnimationController per Shimmer, driven by an
/// AnimatedBuilder that only repaints the child subtree — cheap enough to
/// have several on screen at once (feed skeleton cards).
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Gentle opacity pulse between the two tones.
        final t = _controller.value;
        final base = widget.baseColor ?? const Color(0xFF1A2333); // gray-850
        final highlight = widget.highlightColor ?? const Color(0xFF232F44);
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
          color: EnclavdColors.cardSecondary,
          shape: shape,
          borderRadius: shape == BoxShape.circle
              ? null
              : BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

/// Full skeleton of a post card — mirrors the site's card-skeleton-layer
/// (avatar row, three content lines, image block, action bar).
class PostCardSkeleton extends StatelessWidget {
  const PostCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author row: avatar + name line
            Row(
              children: [
                ShimmerBox(width: 35, height: 35, shape: BoxShape.circle),
                SizedBox(width: 8),
                ShimmerBox(width: 120, height: 14),
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
            ShimmerBox(width: double.infinity, height: 140, borderRadius: 8),
            SizedBox(height: 14),
            // Action bar
            Row(
              children: [
                ShimmerBox(width: 26, height: 22, borderRadius: 4),
                SizedBox(width: 28),
                ShimmerBox(width: 26, height: 22, borderRadius: 4),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
