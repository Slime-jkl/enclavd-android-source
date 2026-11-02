import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme/enclavd_theme.dart';
import 'onscreen_ticker.dart';
import 'shimmer.dart';

/// Inline animated emoji. Compositions live in the bundle as zipped dotLottie
/// assets, so there is no network hop: the only wait is unpacking and parsing
/// one, and the shimmer covers it. Lottie's own cache (capped in main) keeps
/// parsed compositions around while the emoji stays on screen.
class AnimatedEmoji extends StatelessWidget {
  const AnimatedEmoji({super.key, required this.name, this.size = 18});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return OnscreenTicker(
      child: SizedBox(
        width: size,
        height: size,
        child: Lottie.asset(
          'assets/gifs/emojis/$name.lottie',
          width: size,
          height: size,
          fit: BoxFit.contain,
          repeat: true,
          frameBuilder: (context, child, composition) => composition == null
              ? ShimmerBox(width: size, height: size, borderRadius: size * 0.22)
              : child,
          errorBuilder: (context, error, stack) => _Missing(
            label: ':$name:',
            size: size,
          ),
        ),
      ),
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing({required this.label, required this.size});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style:
              TextStyle(fontSize: size, color: context.enclavd.textSecondary),
        ),
      ),
    );
  }
}
