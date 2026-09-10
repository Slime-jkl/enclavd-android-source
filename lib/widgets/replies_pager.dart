import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';

/// Compact page bar for the forum reply list: chevron prev/next around a
/// 'Page X of Y' label. The thread screen shows one above the first
/// reply and one under the last; the bar is hidden entirely when the
/// thread fits a single page.
class RepliesPager extends StatelessWidget {
  const RepliesPager({
    super.key,
    required this.page,
    required this.pages,
    required this.onPage,
    this.busy = false,
  });

  final int page;
  final int pages;
  final ValueChanged<int> onPage;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final canPrev = page > 1 && !busy;
    final canNext = page < pages && !busy;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: canPrev ? () => onPage(page - 1) : null,
          icon: FaIcon(FontAwesomeIcons.chevronLeft,
              size: 15, color: context.enclavd.textPrimary),
          disabledColor: context.enclavd.textSecondary,
          visualDensity: VisualDensity.compact,
          tooltip: 'Older replies',
        ),
        // The count label swaps for a spinner while a page loads, so a
        // tap gives instant feedback without the bar jumping width.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: busy
              ? Padding(
                  key: const ValueKey('busy'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: context.enclavd.link),
                  ),
                )
              : Padding(
                  key: const ValueKey('label'),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text.rich(
                    TextSpan(
                      text: 'Page $page',
                      style: TextStyle(
                          color: context.enclavd.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                      children: [
                        TextSpan(
                          text: ' of $pages',
                          style: TextStyle(
                            color: context.enclavd.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        IconButton(
          onPressed: canNext ? () => onPage(page + 1) : null,
          icon: FaIcon(FontAwesomeIcons.chevronRight,
              size: 15, color: context.enclavd.textPrimary),
          disabledColor: context.enclavd.textSecondary,
          visualDensity: VisualDensity.compact,
          tooltip: 'Newer replies',
        ),
      ],
    );
  }
}
