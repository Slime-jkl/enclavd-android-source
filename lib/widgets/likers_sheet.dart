import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/auth_service.dart';
import '../api/social_service.dart';
import '../screens/profile_screen.dart';
import '../theme/enclavd_theme.dart';
import 'error_view.dart';
import 'enclavd_avatar.dart';
import 'ignite_flame_overlay.dart';
import 'personality_chip.dart';
import 'rank_badge.dart';
import 'shimmer.dart';

/// "Liked by" list: the site's showLikers modal inside our reusable sheet.
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
  Widget build(BuildContext context) => _buildBody();

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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: ErrorView(message: _error!, onRetry: _load),
      );
    }
    final likers = _likers ?? const [];
    if (likers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(FontAwesomeIcons.heart,
                size: 40, color: context.enclavd.textSecondary),
            const SizedBox(height: 12),
            Text('No likes yet',
                style: TextStyle(color: context.enclavd.textSecondary)),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: likers.length,
      separatorBuilder: (_, index) =>
          Divider(height: 1, color: context.enclavd.divider),
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
    final rankColor = context.enclavd.rankName(liker.rank);
    return InkWell(
      onTap: () {
        Navigator.of(context).pop(); // close the sheet first
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ProfileScreen(userId: liker.id),
        ));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Rank border, matching the website's likers modal.
            EnclavdAvatar(
              size: 40,
              url: resolveMediaUrl(apiBaseUrl,
                  avatarPath: liker.profilePictureUrl),
              rank: liker.rank,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Rank on top, then the name with its personality right
                  // after it; a long name truncates, never pushes the chip out.
                  RankBadge(rank: liker.rank),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          liker.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: rankColor,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (liker.personalityType != null) ...[
                        const SizedBox(width: 6),
                        PersonalityChip(type: liker.personalityType!),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Igniters carry the fire on the trailing edge.
            if (liker.ignited) ...[
              const SizedBox(width: 8),
              const Tooltip(
                message: 'Ignited this post',
                child: IgniteFlameIcon(size: 20),
              ),
            ],
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
                ShimmerBox(width: 52, height: 15),
                SizedBox(height: 5),
                ShimmerBox(width: 120, height: 13),
                SizedBox(height: 5),
                ShimmerBox(width: 44, height: 13),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
