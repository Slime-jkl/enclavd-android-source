import 'package:flutter/material.dart';

import '../../theme/enclavd_theme.dart';
import 'app_sheet.dart';
import 'app_xs_button.dart';

/// Opens the app's standard date picker: the same bottom-sheet chrome as every
/// other picker, a themed calendar and a pinned Cancel/OK footer.
///
/// The actions are deliberately split to the two edges of the card (Cancel
/// leading, OK trailing) and rendered as [AppXsButton]s - tiny labels with a
/// large invisible hit area - instead of Material's adjacent dialog buttons.
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = 'Select date',
  String? subtitle,
}) {
  return showAppSheet<DateTime>(
    context: context,
    title: title,
    subtitle: subtitle,
    heightFactor: 0.66,
    builder: (sheetContext) => _AppDatePickerBody(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );
}

class _AppDatePickerBody extends StatefulWidget {
  const _AppDatePickerBody({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_AppDatePickerBody> createState() => _AppDatePickerBodyState();
}

class _AppDatePickerBodyState extends State<_AppDatePickerBody> {
  late DateTime _selected = widget.initialDate;

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    return Column(
      children: [
        Expanded(
          child: Theme(
            data: Theme.of(context).copyWith(
              datePickerTheme: DatePickerThemeData(
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                headerBackgroundColor: Colors.transparent,
                headerForegroundColor: palette.textPrimary,
                weekdayStyle: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                dayForegroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? palette.primaryButtonText
                      : palette.textPrimary,
                ),
                dayBackgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? palette.link
                      : Colors.transparent,
                ),
                dayOverlayColor: WidgetStateProperty.resolveWith(
                  (states) => palette.link.withValues(alpha: 0.08),
                ),
                todayForegroundColor: WidgetStatePropertyAll(palette.link),
                todayBorder: BorderSide(color: palette.link),
                yearForegroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? palette.primaryButtonText
                      : palette.textPrimary,
                ),
                yearBackgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? palette.link
                      : Colors.transparent,
                ),
                dividerColor: palette.divider,
              ),
            ),
            child: CalendarDatePicker(
              initialDate: _selected,
              firstDate: widget.firstDate,
              lastDate: widget.lastDate,
              onDateChanged: (date) => setState(() => _selected = date),
            ),
          ),
        ),
        Divider(height: 1, color: palette.divider),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              AppXsButton(
                label: 'Cancel',
                tone: AppXsButtonTone.neutral,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const Spacer(),
              AppXsButton(
                label: 'OK',
                onPressed: () => Navigator.of(context).pop(_selected),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
