import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../services/sound_service.dart';
import '../theme/enclavd_theme.dart';
import 'ignite_flame.dart';

const Duration _flameDuration = Duration(milliseconds: 1500);

Future<LottieComposition>? _vortex;

Future<LottieComposition> _loadVortex() =>
    _vortex ??= AssetLottie('assets/animations/flame-vortex.lottie').load();

Future<LottieComposition>? _fireIcon;

Future<LottieComposition> _loadFireIcon() =>
    _fireIcon ??= AssetLottie('assets/animations/fire-icon.lottie').load();

// The file's colour is an After Effects Tint effect, which this player ignores.
const List<double> _tintBlackTo = [1, 0.9428, 0.2157];
const List<double> _tintWhiteTo = [1, 0, 0];

List<double> _rampMatrix(List<double> blackTo, List<double> whiteTo) {
  const luma = [0.2126, 0.7152, 0.0722];
  final rows = <double>[];
  for (var channel = 0; channel < 3; channel++) {
    final delta = whiteTo[channel] - blackTo[channel];
    rows.addAll([
      luma[0] * delta,
      luma[1] * delta,
      luma[2] * delta,
      0,
      blackTo[channel] * 255, // translation column is in 0-255 space
    ]);
  }
  rows.addAll(const [0, 0, 0, 1, 0]);
  return rows;
}

final ColorFilter _igniteTint =
    ColorFilter.matrix(_rampMatrix(_tintBlackTo, _tintWhiteTo));

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

class IgniteFlameOverlay extends StatelessWidget {
  const IgniteFlameOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LottieComposition>(
      future: _loadVortex(),
      builder: (context, snap) {
        final composition = snap.data;
        if (composition == null) return const SizedBox.expand();
        return ColorFiltered(
          colorFilter: _igniteTint,
          child: Lottie(
            composition: composition,
            fit: BoxFit.contain,
            repeat: false,
            animate: true,
          ),
        );
      },
    );
  }
}

mixin IgniteFlamePlayer<T extends StatefulWidget> on State<T> {
  bool flamePlaying = false;
  int _flameRun = 0;
  Timer? _flameTimer;

  // Keyed per press so a re-press restarts the flame.
  Widget get flameLayer => IgniteFlameOverlay(key: ValueKey<int>(_flameRun));

  void playIgniteFlame() {
    SoundService.instance.ignite();
    _flameTimer?.cancel();
    setState(() {
      _flameRun++;
      flamePlaying = true;
    });
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
