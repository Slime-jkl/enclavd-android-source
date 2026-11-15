import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../../theme/app_typography.dart';
import '../../theme/enclavd_theme.dart';
import '../brand_logo.dart';
import '../ui/app_sheet.dart';
import '../ui/app_surface.dart';

/// Shared shell for the signed-out screens (login, register, recovery).
///
/// One centred column: brand, headline, a single card holding the form, and
/// an optional footer. Background, max width and vertical rhythm live here so
/// every auth screen keeps the same proportions and entrance motion.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.footer,
    this.leading,
    this.maxWidth = 400,
    this.scrollController,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// Content below the form card (secondary route to the other auth screen).
  final Widget? footer;

  /// Optional top-left action, e.g. a back affordance on register.
  final Widget? leading;

  final double maxWidth;

  /// Optional controller so callers can reset the scroll offset (e.g. when a
  /// multi-step form swaps its content).
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            const horizontal = 20.0;
            const vertical = 28.0;
            return SingleChildScrollView(
              controller: scrollController,
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(
                horizontal: horizontal,
                vertical: vertical,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: viewport.maxHeight - vertical * 2,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: AppEnter(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (leading != null) ...[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: leading!,
                            ),
                            const SizedBox(height: 12),
                          ],
                          const Center(child: BrandLogo(height: 32)),
                          const SizedBox(height: 28),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: AppTypography.h3.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              subtitle!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 13.5,
                                height: 1.35,
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          AppSurface(
                            radius: 16,
                            padding: const EdgeInsets.all(20),
                            child: child,
                          ),
                          if (footer != null) ...[
                            const SizedBox(height: 18),
                            footer!,
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

enum AuthNoticeTone { error, warning, success, info }

/// Inline status message used by the auth forms. One line of colour, an icon
/// and readable body text - never a bare coloured paragraph.
class AuthNotice extends StatelessWidget {
  const AuthNotice({
    super.key,
    required this.message,
    this.tone = AuthNoticeTone.error,
  });

  final String message;
  final AuthNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    final light = Theme.of(context).brightness == Brightness.light;
    final (color, icon) = switch (tone) {
      AuthNoticeTone.error => (
          palette.error,
          FontAwesomeIcons.circleExclamation,
        ),
      AuthNoticeTone.warning => (palette.warning, FontAwesomeIcons.clock),
      AuthNoticeTone.success => (
          light ? const Color(0xFF15803D) : const Color(0xFF4ADE80),
          FontAwesomeIcons.circleCheck,
        ),
      AuthNoticeTone.info => (palette.link, FontAwesomeIcons.circleInfo),
    };

    return Semantics(
      liveRegion: tone == AuthNoticeTone.error,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: FaIcon(icon, size: 13, color: color),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: color, fontSize: 12.5, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
