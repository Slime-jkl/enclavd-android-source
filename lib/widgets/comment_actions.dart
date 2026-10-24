import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HapticFeedback

import '../theme/enclavd_theme.dart';

/// What a long press on a comment offers. Built per row: reply to someone
/// else's comment, edit or delete your own.
enum CommentAction { reply, edit, delete }

/// Opens the action menu at the point that was pressed. A long press is the
/// only way in - comment rows carry no buttons - so it also gives the light
/// haptic tick that tells the user the press landed.
///
/// Returns the chosen action, or null when dismissed.
Future<CommentAction?> showCommentActions(
  BuildContext context,
  Offset globalPosition, {
  required bool canReply,
  required bool isOwner,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject();
  if (overlay is! RenderBox) return null;
  // Only owners act on their own rows; everyone else can answer them.
  if (!isOwner && !canReply) return null;

  HapticFeedback.mediumImpact();
  final palette = context.enclavd;
  final chosen = await showMenu<CommentAction>(
    context: context,
    // Anchored where the finger is, not to a widget: rows are small and a
    // menu pinned to one corner reads as unrelated to the press.
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      overlay.size.width - globalPosition.dx,
      overlay.size.height - globalPosition.dy,
    ),
    color: palette.card,
    elevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: palette.border),
    ),
    items: [
      if (canReply)
        _item(CommentAction.reply, 'Reply', FontAwesomeIcons.reply,
            palette.textPrimary),
      if (isOwner) ...[
        _item(CommentAction.edit, 'Edit', FontAwesomeIcons.pen,
            palette.textPrimary),
        _item(CommentAction.delete, 'Delete', FontAwesomeIcons.trashCan,
            palette.likeActive),
      ],
    ],
  );
  return chosen;
}

PopupMenuItem<CommentAction> _item(
    CommentAction action, String label, FaIconData icon, Color color) {
  return PopupMenuItem<CommentAction>(
    value: action,
    height: 42,
    child: Row(
      children: [
        FaIcon(icon, size: 13, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
              color: color, fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
