import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../../theme/enclavd_theme.dart';
import 'app_motion.dart';

class AppTabItem {
  const AppTabItem({required this.label, this.icon});

  final String label;
  final FaIconData? icon;
}

/// The app-wide segmented control (profile info tabs, feed filters, ...).
///
/// Replaces ad-hoc TabBars and hand-rolled segment pills so the selected
/// state animates, sizes and colours the same everywhere.
class AppSegmentedTabs extends StatelessWidget {
  const AppSegmentedTabs({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    this.dense = false,
  });

  final List<AppTabItem> items;
  final int index;
  final ValueChanged<int> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.cardSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: _Segment(
                item: items[i],
                selected: i == index,
                dense: dense,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.item,
    required this.selected,
    required this.dense,
    required this.onTap,
  });

  final AppTabItem item;
  final bool selected;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    final color = selected ? palette.textPrimary : palette.textSecondary;
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.icon != null) ...[
          FaIcon(item.icon, size: dense ? 12 : 13, color: color),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: dense ? 12 : 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.enter,
          padding: EdgeInsets.symmetric(vertical: dense ? 7 : 9),
          decoration: BoxDecoration(
            color: selected ? palette.card : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? palette.border : Colors.transparent,
            ),
          ),
          child: content,
        ),
      ),
    );
  }
}
