import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../api/activity_service.dart';
import '../api/auth_service.dart' show resolveMediaUrl;
import '../api/profile_service.dart' show FollowListItem;
import '../config/app_config.dart';
import '../theme/enclavd_theme.dart';
import '../utils/db_time.dart';
import 'enclavd_avatar.dart';
import 'personality_chip.dart';
import 'shimmer.dart';

/// The action strip above an Activity entry: a colored icon, the action
/// ("You liked" / "You commented" / "You followed") and the relative time.
/// The entry content below it is a normal post card (like/comment) or a
/// member card (follow).
class ActivityNote extends StatelessWidget {
  const ActivityNote({super.key, required this.item});

  final ActivityItem item;

  static const Map<ActivityType, (FaIconData, String)> _actions = {
    ActivityType.like: (FontAwesomeIcons.heart, 'You liked'),
    ActivityType.comment: (FontAwesomeIcons.comment, 'You commented'),
    ActivityType.follow: (FontAwesomeIcons.userPlus, 'You followed'),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, action) =
        _actions[item.type] ?? (FontAwesomeIcons.heart, 'You liked');
    final color = switch (item.type) {
      ActivityType.like => context.enclavd.likeActive,
      ActivityType.comment => context.enclavd.link,
      ActivityType.follow => const Color(0xFF34D399),
    };
    return Row(
      children: [
        FaIcon(icon, size: 13, color: color),
        const SizedBox(width: 7),
        Text(
          action,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFFD1D5DB), // gray-300
          ),
        ),
        const Spacer(),
        Text(
          relativeTime(item.createdAt),
          style:
              TextStyle(fontSize: 11.5, color: context.enclavd.textSecondary),
        ),
      ],
    );
  }
}

/// Member row for a follow entry: the followed member's avatar, rank-colored
/// username (+ personality chip) and a one-line full name / bio.
class ActivityFollowCard extends StatelessWidget {
  const ActivityFollowCard(
      {super.key, required this.user, required this.onTap});

  final FollowListItem user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final blocked = user.isBlocked;
    final nameColor = blocked
        ? context.enclavd.rankName('Blocked')
        : context.enclavd.rankName(user.rank);
    final personality = context.enclavd.personalityColor(user.personalityType);
    final line = user.fullName.isNotEmpty ? user.fullName : user.bio;
    return Material(
      color: context.enclavd.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: context.enclavd.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              EnclavdAvatar(
                size: 44,
                url: resolveMediaUrl(AppConfig.apiBaseUrl,
                    avatarPath: user.profilePictureUrl),
                borderColor: personality ?? context.enclavd.border,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: nameColor,
                              fontWeight: FontWeight.w600,
                              decoration:
                                  blocked ? TextDecoration.lineThrough : null,
                              decorationColor: nameColor,
                            ),
                          ),
                        ),
                        if (user.personalityType != null) ...[
                          const SizedBox(width: 6),
                          PersonalityChip(type: user.personalityType!),
                        ],
                      ],
                    ),
                    if (line.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.enclavd.textSecondary,
                            fontSize: 12.5),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton twin of an activity entry (action strip + post card block).
class ActivityCardSkeleton extends StatelessWidget {
  const ActivityCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: ShimmerBox(width: 110, height: 12),
        ),
        SizedBox(height: 10),
        PostCardSkeleton(),
      ],
    );
  }
}
