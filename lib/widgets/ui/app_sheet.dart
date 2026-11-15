import 'package:flutter/material.dart';

import '../../theme/enclavd_theme.dart';
import 'app_motion.dart';

/// Opens the app's standard bottom sheet.
///
/// Every sheet gets the same surface, top radius, drag handle and safe-area
/// padding. Dismissal is by swiping down or tapping the backdrop - sheets do
/// not carry their own close "X".
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double? heightFactor,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (sheetContext) {
      final sheet = AppSheet(
        heightFactor: heightFactor,
        child: builder(sheetContext),
      );
      return sheet;
    },
  );
}

/// The chrome for a bottom sheet: card background, top radius, grab handle,
/// optional title/subtitle, optional pinned footer.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.footer,
    this.heightFactor,
    this.maxHeightFactor = 0.9,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 0),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? footer;
  final double? heightFactor;
  final double maxHeightFactor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * maxHeightFactor;

    final content = Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxHeight: heightFactor == null
            ? maxHeight
            : MediaQuery.sizeOf(context).height * heightFactor!,
      ),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(top: BorderSide(color: palette.border)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: palette.textSecondary.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (title != null) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title!,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Flexible(
            child: Padding(padding: padding, child: child),
          ),
          if (footer != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: footer!,
            ),
          ],
        ],
      ),
    );

    if (heightFactor == null) return content;
    return FractionallySizedBox(
      alignment: Alignment.bottomCenter,
      heightFactor: heightFactor,
      child: content,
    );
  }
}

/// A reusable staggered entrance for sheet/screens content.
class AppEnter extends StatelessWidget {
  const AppEnter({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.normal,
      curve: AppMotion.enter,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}
