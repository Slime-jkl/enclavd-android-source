import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';

/// The reply / edit / delete controls that sit on a comment row.
///
/// These used to hide behind a long press on the row, which nobody found.
/// They are plain icon buttons on the row now: reply on anyone's comment,
/// edit and delete on your own.
class CommentActionsBar extends StatelessWidget {
  const CommentActionsBar({
    super.key,
    required this.commentId,
    required this.canReply,
    required this.isOwner,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    this.iconSize = 13,
  });

  /// Row id, only used to key the buttons so a test (or a host) can aim at
  /// the right row when several are on screen.
  final int commentId;
  final bool canReply;
  final bool isOwner;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canReply)
          _button(Key('comment-reply-$commentId'), FontAwesomeIcons.reply,
              'Reply', palette.textSecondary, onReply),
        if (isOwner) ...[
          _button(Key('comment-edit-$commentId'), FontAwesomeIcons.pen, 'Edit',
              palette.textSecondary, onEdit),
          _button(Key('comment-delete-$commentId'), FontAwesomeIcons.trashCan,
              'Delete', palette.likeActive, onDelete),
        ],
      ],
    );
  }

  Widget _button(Key key, FaIconData icon, String label, Color color,
      VoidCallback onTap) {
    return Tooltip(
      message: label,
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: FaIcon(icon, size: iconSize, color: color),
        ),
      ),
    );
  }
}
