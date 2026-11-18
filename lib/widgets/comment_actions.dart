import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';

/// The reply / edit / delete controls that sit under a comment body.
///
/// These used to hide behind a long press on the row, which nobody found.
/// They were then icon-only buttons crammed onto the header line, which made
/// the header noisy and the targets tiny. They are now small labelled actions
/// under the body, matching the website's comment footer.
class CommentActionsBar extends StatelessWidget {
  const CommentActionsBar({
    super.key,
    required this.commentId,
    required this.canReply,
    required this.isOwner,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
  });

  /// Row id, only used to key the buttons so a test (or a host) can aim at
  /// the right row when several are on screen.
  final int commentId;
  final bool canReply;
  final bool isOwner;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    return Wrap(
      spacing: 12,
      children: [
        if (canReply)
          _button(Key('comment-reply-$commentId'), FontAwesomeIcons.reply,
              'Reply', palette.textSecondary, onReply),
        if (isOwner) ...[
          _button(Key('comment-edit-$commentId'), FontAwesomeIcons.pen, 'Edit',
              palette.textSecondary, onEdit),
          _button(
              Key('comment-delete-$commentId'),
              FontAwesomeIcons.solidTrashCan,
              'Delete',
              palette.likeActive,
              onDelete),
        ],
      ],
    );
  }

  Widget _button(
      Key key, FaIconData icon, String label, Color color, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FaIcon(icon, size: 11, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
