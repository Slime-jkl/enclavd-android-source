import 'package:flutter/material.dart';

import '../api/auth_service.dart'; // resolveMediaUrl
import '../api/social_service.dart';
import '../config/app_config.dart';
import '../theme/enclavd_theme.dart';
import 'enclavd_avatar.dart';

/// Horizontal row of follow-suggestion cards above the feed, Instagram
/// style: avatar, username, follow button per card. Tapping the avatar or
/// name opens the profile; the follow button toggles the follow.
class SuggestionRow extends StatelessWidget {
  const SuggestionRow({
    super.key,
    required this.users,
    required this.onOpenProfile,
    required this.onFollow,
    this.busyUserId,
  });

  final List<SuggestedUser> users;

  /// Opens the profile for a suggested user (avatar / name tap).
  final ValueChanged<int> onOpenProfile;

  /// Toggles the follow for a suggested user (button tap).
  final ValueChanged<SuggestedUser> onFollow;

  /// User id currently toggling; its button shows a spinner and the rest
  /// stay enabled (one in-flight follow at a time is enough).
  final int? busyUserId;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EnclavdColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              'Suggested for you',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: EnclavdColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 128,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final user = users[index];
                return _SuggestionCard(
                  user: user,
                  busy: busyUserId == user.id,
                  onOpenProfile: () => onOpenProfile(user.id),
                  onFollow: () => onFollow(user),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.user,
    required this.busy,
    required this.onOpenProfile,
    required this.onFollow,
  });

  final SuggestedUser user;
  final bool busy;
  final VoidCallback onOpenProfile;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Column(
        children: [
          InkWell(
            onTap: onOpenProfile,
            borderRadius: BorderRadius.circular(32),
            child: EnclavdAvatar(
              size: 64,
              url: resolveMediaUrl(AppConfig.apiBaseUrl,
                  avatarPath: user.profilePictureUrl),
              borderColor: PersonalityColors.forType(user.personalityType),
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: onOpenProfile,
            borderRadius: BorderRadius.circular(6),
            child: Text(
              user.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: EnclavdColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _FollowChip(busy: busy, label: user.followLabel, onPressed: onFollow),
        ],
      ),
    );
  }
}

/// Compact follow button for the suggestion card (site .follow-button
/// colors, smaller than the profile's full-size one).
class _FollowChip extends StatelessWidget {
  const _FollowChip({
    required this.busy,
    required this.label,
    required this.onPressed,
  });

  final bool busy;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: TextButton(
        onPressed: busy ? null : onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: EnclavdColors.primaryButton,
          disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
          disabledBackgroundColor:
              EnclavdColors.primaryButton.withValues(alpha: 0.6),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
          ),
          textStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        child: busy
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    );
  }
}
