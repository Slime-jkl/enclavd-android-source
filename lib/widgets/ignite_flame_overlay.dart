import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../services/sound_service.dart';
import '../theme/enclavd_theme.dart';
import 'ignite_flame.dart';

/// How long the site's vortex runs (43 frames at 30fps) plus a beat, so a card
/// can drop the layer without waiting on the player.
const Duration _flameDuration = Duration(milliseconds: 1500);

/// Decoded once per app run: every press plays the same file, and the site
/// caches its payload the same way.
Future<LottieComposition>? _vortex;

Future<LottieComposition> _loadVortex() =>
    _vortex ??= AssetLottie('assets/animations/flame-vortex.lottie').load();

/// Same caching for the small fire.
Future<LottieComposition>? _fireIcon;

Future<LottieComposition> _loadFireIcon() =>
    _fireIcon ??= AssetLottie('assets/animations/fire-icon.lottie').load();

/// The small fire beside an igniter's name in the likers list: the site's own
/// fire-icon.lottie, looping. Nothing is drawn until it decodes, and it falls
/// back to the painted flame if it never does, so a row is never bare.
class IgniteFlameIcon extends StatelessWidget {
  const IgniteFlameIcon({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LottieComposition>(
      future: _loadFireIcon(),
      builder: (context, snap) {
        final composition = snap.data;
        if (composition == null) {
          return IgniteFlame(size: size, color: context.enclavd.igniteActive);
        }
        return SizedBox(
          width: size * 0.74,
          height: size,
          child: Lottie(
            composition: composition,
            fit: BoxFit.contain,
            repeat: true,
            animate: true,
          ),
        );
      },
    );
  }
}

/// The card flame: the site's own animation, played once over the card that
/// was ignited. Mount it in a Stack as a Positioned.fill; the web flips a CSS
/// class where the app mounts and drops the layer (see [IgniteFlamePlayer]).
class IgniteFlameOverlay extends StatelessWidget {
  const IgniteFlameOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LottieComposition>(
      future: _loadVortex(),
      builder: (context, snap) {
        final composition = snap.data;
        // The layer stays transparent until the flame is decoded; a decode
        // failure must never take a card down with it.
        if (composition == null) return const SizedBox.expand();

        return Lottie(
          composition: composition,
          // The site's layer letterboxes the 16:9 vortex in the card box.
          fit: BoxFit.contain,
          repeat: false,
          animate: true,
        );
      },
    );
  }
}

/// Card-side state for the flame: holds the layer up while the animation runs
/// and starts its sound with it. Mix into the State of a card whose build has
/// a Stack, and render [IgniteFlameOverlay] as a Positioned.fill while
/// [flamePlaying].
mixin IgniteFlamePlayer<T extends StatefulWidget> on State<T> {
  bool flamePlaying = false;
  Timer? _flameTimer;

  /// Plays the flame over this card, sound included. A grant and a re-press of
  /// a post that already holds the viewer's ignite both come through here.
  void playIgniteFlame() {
    SoundService.instance.ignite();
    _flameTimer?.cancel();
    setState(() => flamePlaying = true);
    _flameTimer = Timer(_flameDuration, () {
      if (mounted) setState(() => flamePlaying = false);
    });
  }

  @override
  void dispose() {
    _flameTimer?.cancel();
    super.dispose();
  }
}
