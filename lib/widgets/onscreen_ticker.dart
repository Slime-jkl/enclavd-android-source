import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Runs [child]'s tickers only while it is near the screen.
///
/// Some pages build every child up front (a thread's replies), so a long page
/// would otherwise keep every Lottie and shimmer pumping frames nobody can
/// see. Scroll events are coalesced to one check per frame.
class OnscreenTicker extends StatefulWidget {
  const OnscreenTicker({super.key, required this.child, this.margin = 420});

  final Widget child;

  /// How far outside the viewport the child still counts as on screen.
  final double margin;

  @override
  State<OnscreenTicker> createState() => _OnscreenTickerState();
}

class _OnscreenTickerState extends State<OnscreenTicker> {
  ScrollPosition? _position;
  double _viewportHeight = 800;
  bool _enabled = true;
  bool _queued = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _viewportHeight = MediaQuery.maybeSizeOf(context)?.height ?? 800;

    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_onScroll);
      _position = position;
      _position?.addListener(_onScroll);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (_queued) return;
    _queued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      _check();
    });
  }

  void _check() {
    if (!mounted) return;

    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;

    final top = box.localToGlobal(Offset.zero).dy;
    final near = top + box.size.height >= -widget.margin &&
        top <= _viewportHeight + widget.margin;

    if (near != _enabled) {
      setState(() => _enabled = near);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TickerMode(enabled: _enabled, child: widget.child);
  }
}
