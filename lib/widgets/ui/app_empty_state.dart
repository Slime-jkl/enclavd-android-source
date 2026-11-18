import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../../theme/enclavd_theme.dart';
import 'app_button.dart';

/// The one empty/error state used across the app.
///
/// A quiet icon, one line of what happened, one line of what to do next,
/// and at most one action. Keeping every empty list on this
/// shape means "nothing here yet" always looks intentional and always offers
/// a next step instead of a blank screen.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.compact = false,
  });

  final FaIconData icon;
  final String title;
  final String? message;

  /// The single next step. Omit for a dead end (an error without retry).
  final String? actionLabel;
  final VoidCallback? onAction;
  final FaIconData? actionIcon;

  /// Tighter vertical rhythm for states that sit inside a scrolling list
  /// (comments) instead of owning the whole body (feed).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = context.enclavd.link;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 24,
        vertical: compact ? 20 : 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(
            icon,
            size: compact ? 22 : 26,
            color: accent,
          ),
          SizedBox(height: compact ? 12 : 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.enclavd.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (message case final message?) ...[
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.enclavd.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
          if (onAction != null && actionLabel != null) ...[
            SizedBox(height: compact ? 14 : 18),
            AppButton(
              label: actionLabel!,
              icon: actionIcon,
              onPressed: onAction,
              size: AppButtonSize.small,
            ),
          ],
        ],
      ),
    );
  }
}
