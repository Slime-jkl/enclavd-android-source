import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HapticFeedback

import '../api/feed_service.dart'; // Post
import '../theme/enclavd_theme.dart';
import '../utils/db_time.dart';

/// What a long press on a post offers. Edit/delete only exist on your own
/// posts; the sheet opens for anyone so the timestamps stay reachable.
enum PostAction { edit, delete }

/// Opens the post drawer: the post's id and stamps on top, the actions
/// below when there are any. Returns the chosen action, or null when the
/// sheet is dismissed.
Future<PostAction?> showPostActions(
  BuildContext context, {
  required Post post,
  bool canEdit = false,
  bool canDelete = false,
}) {
  // Same tick the comment menu gives: the press landed, something is coming.
  HapticFeedback.mediumImpact();
  return showModalBottomSheet<PostAction>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _PostActionsSheet(
      post: post,
      canEdit: canEdit,
      canDelete: canDelete,
    ),
  );
}

class _PostActionsSheet extends StatelessWidget {
  const _PostActionsSheet({
    required this.post,
    required this.canEdit,
    required this.canDelete,
  });

  final Post post;
  final bool canEdit;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    final edited = post.editedAt;
    final hasActions = canEdit || canDelete;
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Post #${post.id}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Posted ${absoluteTime(post.createdAt)}',
                    style: TextStyle(fontSize: 12, color: palette.textSecondary),
                  ),
                  if (edited != null && edited.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Edited ${absoluteTime(edited)}',
                      style:
                          TextStyle(fontSize: 12, color: palette.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (hasActions)
              Divider(height: 1, thickness: 1, color: palette.divider),
            if (canEdit)
              _Action(
                icon: FontAwesomeIcons.pen,
                label: 'Edit post',
                color: palette.textPrimary,
                onTap: () => Navigator.of(context).pop(PostAction.edit),
              ),
            if (canDelete)
              _Action(
                icon: FontAwesomeIcons.trashCan,
                label: 'Delete post',
                color: palette.likeActive,
                onTap: () => Navigator.of(context).pop(PostAction.delete),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final FaIconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            FaIcon(icon, size: 14, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                  color: color, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
