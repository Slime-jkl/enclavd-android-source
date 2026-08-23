import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/auth_service.dart';
import '../api/social_service.dart';
import '../screens/profile_screen.dart';
import '../theme/enclavd_theme.dart';
import 'error_view.dart';
import 'enclavd_avatar.dart';
import 'personality_chip.dart';
import 'rank_badge.dart';
import 'shimmer.dart';

/// "Liked by" list — port of the site's showLikers modal (likes.js):
/// black overlay, "Liked by" header with × close, rows styled like the
/// app's feed cards: 40px avatar (personality border), rank-colored
/// username (w600), personality pill, the site's rank badge chip (icon +
/// rank name, rank bg + border) and the server-formatted
/// "August 12, 2026 at 10:32 AM" timestamp.
/// Tapping a row opens that member's profile.
class LikersSheet extends StatefulWidget {
  const LikersSheet({
    super.key,
    required this.postId,
    required this.social,
    required this.apiBaseUrl,
  });

  final int postId;
  final SocialService social;
  final String apiBaseUrl;

  @override
  State<LikersSheet> createState() => _LikersSheetState();
}

class _LikersSheetState extends State<LikersSheet> {
  List<Liker>? _likers;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final likers = await widget.social.likers(widget.postId);
      if (!mounted) return;
      setState(() {
        _likers = likers;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load likes.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header (site: "Liked by" + fa-times close).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                const Text('Liked by',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const FaIcon(FontAwesomeIcons.xmark,
                      size: 18, color: EnclavdColors.textSecondary),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: EnclavdColors.divider),
          Flexible(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        shrinkWrap: true,
        children: const [
          _LikerRowSkeleton(),
          _LikerRowSkeleton(),
          _LikerRowSkeleton(),
        ],
      );
    }
    if (_error != null) {
return ErrorView(message: _error!, onRetry: _load);
    }
    final likers = _likers ?? const [];
    if (likers.isEmpty) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FaIcon(FontAwesomeIcons.heart,
              size: 40, color: EnclavdColors.textSecondary),
          SizedBox(height: 12),
          Text('No likes yet',
              style: TextStyle(color: EnclavdColors.textSecondary)),
        ],
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: likers.length,
      separatorBuilder: (_, index) =>
          const Divider(height: 1, color: EnclavdColors.divider),
      itemBuilder: (context, index) => _LikerRow(
        liker: likers[index],
        apiBaseUrl: widget.apiBaseUrl,
      ),
    );
  }
}

class _LikerRow extends StatelessWidget {
  const _LikerRow({required this.liker, required this.apiBaseUrl});

  final Liker liker;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    final rankColor = RankColors.forRank(liker.rank);
    final personality = PersonalityColors.forType(liker.personalityType);
    return InkWell(
      onTap: () {
        Navigator.of(context).pop(); // close the sheet first
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ProfileScreen(userId: liker.id),
        ));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 40px avatar — personality border, the app's feed/comments
            // convention ("like on feed"; the site modal uses the rank
            // border instead, which would break app consistency).
            EnclavdAvatar(
              size: 40,
              url: resolveMediaUrl(apiBaseUrl,
                  avatarPath: liker.profilePictureUrl),
              borderColor: personality,
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
                          liker.username,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: rankColor,
                            fontWeight: FontWeight.w600, // feed author row
                          ),
                        ),
                      ),
                      if (liker.personalityType != null) ...[
                        const SizedBox(width: 6),
                        PersonalityChip(type: liker.personalityType!),
                      ],
                      const SizedBox(width: 6),
                      // Rank badge — the site's getRankStyles() badge chip
                      // (icon + rank name, rank bg + border, dark text).
                      RankBadge(rank: liker.rank),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    liker.likedAt,
                    style: const TextStyle(
                        color: EnclavdColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LikerRowSkeleton extends StatelessWidget {
  const _LikerRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          ShimmerBox(width: 40, height: 40, shape: BoxShape.circle),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 120, height: 14),
                SizedBox(height: 6),
                ShimmerBox(width: 180, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
