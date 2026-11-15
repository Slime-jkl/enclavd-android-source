import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../../theme/enclavd_theme.dart';
import 'app_motion.dart';
import 'app_sheet.dart';

/// One choice rendered by [showAppOptionSheet].
class AppOption<T> {
  const AppOption({required this.value, required this.label, this.description});

  final T value;
  final String label;
  final String? description;
}

/// Opens the standard single-choice sheet.
///
/// Used by every tap-to-pick field whose options are short enough to list
/// (gender, sort order, visibility...), so the choice UI always has the same
/// sheet chrome, row height, selected treatment and checkmark.
Future<T?> showAppOptionSheet<T>({
  required BuildContext context,
  required List<AppOption<T>> options,
  required T? selected,
  String? title,
  String? subtitle,
}) {
  return showAppSheet<T>(
    context: context,
    title: title,
    subtitle: subtitle,
    builder: (sheetContext) {
      final palette = sheetContext.enclavd;
      return ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 4),
        itemCount: options.length,
        separatorBuilder: (context, index) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final option = options[index];
          final isSelected = option.value == selected;
          return Semantics(
            button: true,
            selected: isSelected,
            child: AnimatedContainer(
              duration: AppMotion.fast,
              decoration: BoxDecoration(
                color: isSelected
                    ? palette.link.withValues(alpha: 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? palette.link.withValues(alpha: 0.30)
                      : Colors.transparent,
                ),
              ),
              child: InkWell(
                onTap: () => Navigator.of(sheetContext).pop(option.value),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.label,
                              style: TextStyle(
                                color: isSelected
                                    ? palette.link
                                    : palette.textPrimary,
                                fontSize: 14.5,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                            if (option.description != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                option.description!,
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 10),
                        Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: palette.link.withValues(alpha: 0.16),
                          ),
                          child: FaIcon(
                            FontAwesomeIcons.check,
                            size: 10,
                            color: palette.link,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
