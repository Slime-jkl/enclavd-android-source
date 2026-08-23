import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';

/// THE canonical full-page error state — centered icon, friendly,
/// non-technical message and a "Try again" button. Every screen's load
/// failure renders through this widget so the layout can never drift
/// (feed, profile, messages, notifications, articles, domains, search,
/// threads, settings, tickets…). Screens inside a RefreshIndicator keep
/// working: the view is always scrollable.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  /// Already user-friendly text (the API layer maps network and server
  /// failures to plain language before they reach here).
  final String message;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
      children: [
        const Center(
          child: FaIcon(FontAwesomeIcons.cloudArrowDown,
              size: 56, color: EnclavdColors.textSecondary),
        ),
        const SizedBox(height: 18),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: EnclavdColors.textSecondary,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: EnclavdColors.link,
              textStyle: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600),
            ),
            child: const Text('Try again'),
          ),
        ),
      ],
    );
  }
}
