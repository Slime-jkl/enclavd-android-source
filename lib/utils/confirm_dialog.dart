import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';

/// Standard destructive confirm (matches the thread-delete dialog):
/// Cancel dismisses, the red Delete proceeds. True only on Delete.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete',
              style: TextStyle(color: EnclavdColors.likeActive)),
        ),
      ],
    ),
  );
  return confirmed == true;
}
