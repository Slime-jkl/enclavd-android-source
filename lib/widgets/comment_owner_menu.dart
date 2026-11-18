import 'dart:ui';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/auth_service.dart'; // resolveMediaUrl
import '../api/social_service.dart';
import '../theme/enclavd_theme.dart';
import '../utils/db_time.dart';
import 'enclavd_avatar.dart';
import 'ui/app_motion.dart';

/// Long-press menu for a comment you wrote.
///
/// Everything behind the comment blurs away so only the row you are acting on
/// stays legible, and the destructive action waits behind that deliberate
/// gesture instead of sitting in the row's action bar.
Future<void> showCommentOwnerMenu(
  BuildContext context, {
  required Comment comment,
  required String apiBaseUrl,
  required VoidCallback onDelete,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Comment actions',
    barrierColor: Colors.transparent,
    transitionDuration: AppMotion.fast,
    pageBuilder: (context, _, __) => _CommentOwnerMenu(
        comment: comment, apiBaseUrl: apiBaseUrl, onDelete: onDelete),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _CommentOwnerMenu extends StatelessWidget {
  const _CommentOwnerMenu({
    required this.comment,
    required this.apiBaseUrl,
    required this.onDelete,
  });

  final Comment comment;
  final String apiBaseUrl;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    final blocked = comment.isBlocked;
    final nameColor = blocked
        ? palette.rankName('Blocked')
        : palette.rankNameFromCss(comment.nameColor);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: const ColoredBox(color: Color(0x59000000)),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.border),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 32,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          EnclavdAvatar(
                            size: 30,
                            url: resolveMediaUrl(apiBaseUrl,
                                avatarPath: comment.profilePictureUrl),
                            rank: blocked ? 'Blocked' : comment.rank,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  comment.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: nameColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                    decoration: blocked
                                        ? TextDecoration.lineThrough
                                        : null,
                                    decorationColor: nameColor,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  relativeTime(comment.createdAtUtc),
                                  style: TextStyle(
                                    color: palette.textSecondary,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        comment.content,
                        maxLines: 10,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Divider(height: 1, color: palette.divider),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              onDelete();
                            },
                            icon: FaIcon(
                              FontAwesomeIcons.solidTrashCan,
                              size: 13,
                              color: palette.likeActive,
                            ),
                            label: Text(
                              'Delete',
                              style: TextStyle(
                                color: palette.likeActive,
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
