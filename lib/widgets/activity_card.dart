import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../api/activity_service.dart';
import '../api/auth_service.dart' show resolveMediaUrl;
import '../config/app_config.dart';
import '../theme/enclavd_theme.dart';
import '../utils/db_time.dart';
import '../utils/html_entities.dart';
import 'enclavd_avatar.dart';
import 'shimmer.dart';

/// One Activity feed row (the viewer's own likes/comments/follows).
///
/// Card layout mirrors the notification drawer rows: the other member's
/// avatar (post author for like/comment, the followed member for follow)
/// with the interaction-type chip pinned to its corner, a title line
/// naming the action, and a per-type detail block below (post preview /
/// own comment / the member's name line). Tapping opens the post or the
/// member's profile.
class ActivityCard extends StatelessWidget {
  const ActivityCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  final ActivityItem item;
  final VoidCallback onTap;

  static const Map<ActivityType, (FaIconData, Color)> _typeIcons = {
    ActivityType.like: (FontAwesomeIcons.heart, EnclavdColors.likeActive),
    ActivityType.comment: (FontAwesomeIcons.comment, EnclavdColors.link),
    ActivityType.follow: (FontAwesomeIcons.userPlus, Color(0xFF34D399)),
  };

  @override
  Widget build(BuildContext context) {
    final post = item.post;
    final user = item.user;
    // Avatar: the author of the engaged post, or the followed member.
    final avatarPath = (item.type == ActivityType.follow
            ? user?.profilePictureUrl
            : post?.profilePictureUrl) ??
        '/assets/default-avatar.png';
    final personality = item.type == ActivityType.follow
        ? PersonalityColors.forType(user?.personalityType)
        : PersonalityColors.forType(post?.personalityType);
    final (icon, iconColor) =
        _typeIcons[item.type] ?? (FontAwesomeIcons.bell, EnclavdColors.textSecondary);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: EnclavdColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: EnclavdColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    EnclavdAvatar(
                      size: 40,
                      url: resolveMediaUrl(AppConfig.apiBaseUrl,
                          avatarPath: avatarPath),
                      borderColor: personality ?? EnclavdColors.border,
                    ),
                    // Type chip on the avatar corner.
                    Positioned(
                      right: -4,
                      bottom: -4,
                      // alignment REQUIRED: tight constraints otherwise
                      // paint the glyph off-center.
                      child: Container(
                        width: 18,
                        height: 18,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: iconColor,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: EnclavdColors.card, width: 2),
                        ),
                        child: FaIcon(icon, size: 9, color: EnclavdColors.card),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _title(context),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            relativeTime(item.createdAt),
                            style: const TextStyle(
                                fontSize: 11,
                                color: EnclavdColors.textSecondary),
                          ),
                        ],
                      ),
                      ..._detail(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(BuildContext context) {
    final post = item.post;
    final user = item.user;
    final TextSpan handle;
    switch (item.type) {
      case ActivityType.like:
        final blocked = post?.isBlocked ?? false;
        handle = _handleSpan(
          username: post?.username ?? '',
          rank: post?.rank ?? 'Member',
          blocked: blocked,
        );
        return Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'You liked a post by '),
              handle,
              const TextSpan(text: "'s post"),
            ],
          ),
          style: const TextStyle(fontSize: 14, height: 1.3),
        );
      case ActivityType.comment:
        final blocked = post?.isBlocked ?? false;
        handle = _handleSpan(
          username: post?.username ?? '',
          rank: post?.rank ?? 'Member',
          blocked: blocked,
        );
        return Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'You commented on '),
              handle,
              const TextSpan(text: "'s post"),
            ],
          ),
          style: const TextStyle(fontSize: 14, height: 1.3),
        );
      case ActivityType.follow:
        final blocked = user?.isBlocked ?? false;
        handle = _handleSpan(
          username: user?.username ?? '',
          rank: user?.rank ?? 'Member',
          blocked: blocked,
        );
        return Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'You followed '),
              handle,
            ],
          ),
          style: const TextStyle(fontSize: 14, height: 1.3),
        );
    }
  }

  TextSpan _handleSpan({
    required String username,
    required String rank,
    required bool blocked,
  }) =>
      TextSpan(
        text: '@$username',
        style: TextStyle(
          color: blocked ? RankColors.forRank('Blocked') : RankColors.forRank(rank),
          fontWeight: FontWeight.w600,
          decoration: blocked ? TextDecoration.lineThrough : null,
          decorationColor: blocked ? RankColors.forRank('Blocked') : null,
        ),
      );

  /// The block under the title, per type. Returns [] when there is
  /// nothing extra to show (image-only post, member with no name line).
  List<Widget> _detail() {
    switch (item.type) {
      case ActivityType.like:
        final text = _preview(item.post?.content ?? '');
        if (text.isEmpty) return const [];
        return [
          const SizedBox(height: 6),
          _chip(Text('"$text"', maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, color: EnclavdColors.textSecondary))),
        ];
      case ActivityType.comment:
        final text = _preview(item.commentContent ?? '');
        if (text.isEmpty) return const [];
        return [
          const SizedBox(height: 6),
          _chip(Text(text, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFFD1D5DB)))), // gray-300
        ];
      case ActivityType.follow:
        final user = item.user;
        if (user == null) return const [];
        final line = user.fullName.isNotEmpty ? user.fullName : user.bio;
        if (line.isEmpty) return const [];
        return [
          const SizedBox(height: 2),
          Text(
            line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: EnclavdColors.textSecondary, fontSize: 12.5),
          ),
        ];
    }
  }

  Widget _chip(Widget child) => Container(
        padding: const EdgeInsets.all(8),
        width: double.infinity,
        decoration: BoxDecoration(
          color: EnclavdColors.cardSecondary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      );

  /// 50-char clamp, entity-decoded - same preview rule as the
  /// notification drawer rows.
  String _preview(String raw) {
    final decoded = decodeHtmlEntities(raw).trim();
    if (decoded.isEmpty) return '';
    return decoded.length > 50 ? '${decoded.substring(0, 50)}...' : decoded;
  }
}

/// Skeleton twin of [ActivityCard] for first-load shimmer lists.
class ActivityCardSkeleton extends StatelessWidget {
  const ActivityCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EnclavdColors.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBox(
              width: 40, height: 40, shape: BoxShape.circle),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 150, height: 13),
                SizedBox(height: 8),
                ShimmerBox(width: double.infinity, height: 13),
                SizedBox(height: 6),
                ShimmerBox(width: 110, height: 13),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
