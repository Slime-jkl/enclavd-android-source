import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';

/// Show/hide control for a nested reply group: '3 replies' when the
/// group is collapsed, 'Hide replies' when open. Sits under the group
/// at the nested text column and toggles it.
class RepliesToggle extends StatelessWidget {
  const RepliesToggle({
    super.key,
    required this.count,
    required this.open,
    required this.onTap,
  });

  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = open
        ? (count == 1 ? 'Hide reply' : 'Hide replies')
        : (count == 1 ? '1 reply' : '$count replies');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(
                open
                    ? FontAwesomeIcons.chevronUp
                    : FontAwesomeIcons.chevronDown,
                size: 11,
                color: EnclavdColors.link),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: EnclavdColors.link,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
