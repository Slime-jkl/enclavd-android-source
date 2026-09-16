import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/social_service.dart';
import '../theme/enclavd_theme.dart';
import 'ignite_flame.dart';

/// Fallback for the daily-limit dialog: the server's own wording wins.
const String kIgniteLimitCopy =
    'You can ignite only one post each day, you already ignited one today.';

/// The ignite control: the fire in an action row, the limit dialog and the
/// burst. Feed and forum cards share it, so both spend the same allowance.
class IgniteButton extends StatefulWidget {
  const IgniteButton({
    super.key,
    required this.postId,
    required this.ignited,
    required this.social,
    this.size = 22,
    this.onResult,
  });

  final int postId;

  final bool ignited;
  final SocialService social;

  final double size;

  /// Fired after a press that spent or replayed the ignite; never on the
  /// limit case, which shows the dialog itself.
  final void Function(IgniteResult result)? onResult;

  @override
  State<IgniteButton> createState() => _IgniteButtonState();
}

class _IgniteButtonState extends State<IgniteButton> {
  late bool _ignited = widget.ignited;
  bool _busy = false;

  @override
  void didUpdateWidget(IgniteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A reload is authoritative while nothing is in flight.
    if (!_busy && oldWidget.ignited != widget.ignited) {
      _ignited = widget.ignited;
    }
  }

  Future<void> _press() async {
    if (_busy) return;
    setState(() => _busy = true);

    final IgniteResult result;
    try {
      result = await widget.social.ignite(widget.postId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('Could not ignite this post. Try again.');
      return;
    }
    if (!mounted) return;

    if (result.limitReached) {
      setState(() => _busy = false);
      await showIgniteLimitDialog(context, result.message);
      return;
    }
    if (!result.granted && !result.alreadyIgnited) {
      setState(() => _busy = false);
      _toast('Could not ignite this post. Try again.');
      return;
    }

    setState(() {
      _busy = false;
      _ignited = true;
    });
    widget.onResult?.call(result);
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _press,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Center(
            child: _ignited
                ? IgniteFlame(
                    key: const ValueKey('ignite-flame'),
                    size: widget.size,
                    color: context.enclavd.igniteActive,
                  )
                : FaIcon(
                    FontAwesomeIcons.fire,
                    key: const ValueKey('ignite-fire'),
                    color: context.enclavd.textSecondary,
                    size: widget.size * 0.9,
                  ),
          ),
        ),
      ),
    );
  }
}

/// The day's limit, in the server's own words.
Future<void> showIgniteLimitDialog(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IgniteFlame(size: 34, color: context.enclavd.igniteActive),
          const SizedBox(height: 14),
          Text(
            message.isEmpty ? kIgniteLimitCopy : message,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.enclavd.textPrimary, height: 1.45),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}
