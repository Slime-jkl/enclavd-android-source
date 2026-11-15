import 'package:flutter/material.dart';

/// Extends a widget's pointer hit area without changing layout.
///
/// A transparent [GestureDetector] is inserted into the app overlay, exactly
/// over [child] plus [horizontalPadding]/[verticalPadding] on every side. It
/// may extend past the child's layout box (even past a card edge) without
/// shifting anything. When the nearest scrollable can actually scroll the
/// overlay is removed, so drags through the margin keep scrolling; the
/// enlarged hit area is only active on non-scrolling pages.
class ExpandedTapArea extends StatefulWidget {
  const ExpandedTapArea({
    super.key,
    required this.child,
    required this.onTap,
    this.horizontalPadding = 12,
    this.verticalPadding = 12,
    this.coverChild = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double horizontalPadding;
  final double verticalPadding;

  /// Whether the transparent overlay also sits on top of [child].
  ///
  /// Leave it true for decorative children (a plain link label). Set it false
  /// when the child has its own touch feedback and must receive the pointer
  /// itself; the overlay then only covers the padding ring around it.
  final bool coverChild;

  @override
  State<ExpandedTapArea> createState() => _ExpandedTapAreaState();
}

class _ExpandedTapAreaState extends State<ExpandedTapArea>
    with WidgetsBindingObserver {
  final _targetKey = GlobalKey();
  OverlayEntry? _entry;
  Rect? _hitRect;
  ScrollPosition? _scrollPosition;
  bool _scrollableContent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollPosition?.removeListener(_onScrollMetrics);
    _removeEntry();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback(_syncOverlay);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(_syncOverlay);
    return KeyedSubtree(key: _targetKey, child: widget.child);
  }

  void _syncOverlay(Duration _) {
    if (!mounted) return;

    final box = _targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      _removeEntry();
      return;
    }

    _bindScrollPosition();

    if (widget.onTap == null || _scrollableContent) {
      _removeEntry();
      return;
    }

    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null || !overlayBox.hasSize) {
      _removeEntry();
      return;
    }

    final topLeft = overlayBox.globalToLocal(box.localToGlobal(Offset.zero));
    final rect = Rect.fromLTWH(
      topLeft.dx - widget.horizontalPadding,
      topLeft.dy - widget.verticalPadding,
      box.size.width + widget.horizontalPadding * 2,
      box.size.height + widget.verticalPadding * 2,
    );

    if (_entry == null) {
      _hitRect = rect;
      _entry = OverlayEntry(builder: _buildEntry);
      overlay.insert(_entry!);
    } else {
      _hitRect = rect;
      _entry!.markNeedsBuild();
    }
  }

  Widget _buildEntry(BuildContext context) {
    final rect = _hitRect;
    if (rect == null) return const SizedBox.shrink();
    if (widget.coverChild) {
      return Positioned.fromRect(
        rect: rect,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: const SizedBox.expand(),
        ),
      );
    }

    // Only the padding ring is covered, so a tap inside the child still
    // reaches the child's own gesture recognizer.
    final hitHeight = rect.height - widget.verticalPadding * 2;
    Widget strip(double left, double top, double width, double height) {
      return Positioned(
        left: left,
        top: top,
        width: width,
        height: height,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: const SizedBox.expand(),
        ),
      );
    }

    return Positioned.fromRect(
      rect: rect,
      child: Stack(
        children: [
          strip(0, 0, rect.width, widget.verticalPadding),
          strip(
            0,
            rect.height - widget.verticalPadding,
            rect.width,
            widget.verticalPadding,
          ),
          strip(0, widget.verticalPadding, widget.horizontalPadding, hitHeight),
          strip(
            rect.width - widget.horizontalPadding,
            widget.verticalPadding,
            widget.horizontalPadding,
            hitHeight,
          ),
        ],
      ),
    );
  }

  void _removeEntry() {
    final entry = _entry;
    if (entry == null) return;
    entry.remove();
    entry.dispose();
    _entry = null;
    _hitRect = null;
  }

  void _bindScrollPosition() {
    final targetContext = _targetKey.currentContext;
    if (targetContext == null) return;

    final position = Scrollable.maybeOf(targetContext)?.position;
    if (position == _scrollPosition) {
      _scrollableContent = (position?.maxScrollExtent ?? 0) > 0;
      return;
    }

    _scrollPosition?.removeListener(_onScrollMetrics);
    _scrollPosition = position;
    _scrollPosition?.addListener(_onScrollMetrics);
    _scrollableContent = (position?.maxScrollExtent ?? 0) > 0;
  }

  void _onScrollMetrics() {
    final scrollable = (_scrollPosition?.maxScrollExtent ?? 0) > 0;
    if (scrollable != _scrollableContent && mounted) {
      setState(() => _scrollableContent = scrollable);
    }
  }
}
