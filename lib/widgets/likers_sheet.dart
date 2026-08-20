import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/auth_service.dart';
import '../api/social_service.dart';
import '../screens/profile_screen.dart';
import '../theme/enclavd_theme.dart';
import 'enclavd_image.dart';
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
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_error!,
              style: const TextStyle(color: EnclavdColors.textSecondary)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ],
      );
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
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: EnclavdColors.cardSecondary,
                border: Border.all(
                  color: personality ?? EnclavdColors.border,
                  width: 2,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: EnclavdImage(
                resolveMediaUrl(apiBaseUrl,
                    avatarPath: liker.profilePictureUrl),
                fit: BoxFit.cover,
              ),
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
                        // Same pill as the feed author row (fontSize 10,
                        // w600, cardSecondary bg).
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: EnclavdColors.cardSecondary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            liker.personalityType!.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color:
                                  personality ?? EnclavdColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      // Rank badge — the site's getRankStyles() badge chip
                      // (icon + rank name, rank bg + border, dark text).
                      _RankBadge(rank: liker.rank),
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

/// The site's rank badge (getRankStyles()['badge'] from config/ranks.php):
/// a tiny pill with the rank's FA icon + name, rank-colored background and
/// border, dark text. The site renders it at text-xs * scale(0.75); here
/// ~10px reads cleanly on a phone without the web's transform hack.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final String rank;

  static const Map<String, _RankBadgeStyle> _styles = {
    // badge_bg / badge_border / badge_text / icon (config/ranks.php).
    'SysOp': _RankBadgeStyle(
      bg: Color(0xFF7E22CE), // bg-purple-700
      border: Color(0xFFA855F7), // border-purple-500
      text: Color(0xFF030712), // text-gray-950
      icon: FontAwesomeIcons.code, // fa-code
    ),
    'Admin': _RankBadgeStyle(
      bg: Color(0xFFDC2626), // bg-red-600
      border: Color(0xFFEF4444), // border-red-500
      text: Color(0xFF030712),
      icon: FontAwesomeIcons.shieldHalved, // fa-shield-alt (FA6 name)
    ),
    'Officer': _RankBadgeStyle(
      bg: Color(0xFF2563EB), // bg-blue-600
      border: Color(0xFF3B82F6), // border-blue-500
      text: Color(0xFF030712),
      icon: FontAwesomeIcons.gavel, // fa-gavel
    ),
    'Founding Member': _RankBadgeStyle(
      bg: Color(0xFFCA8A04), // bg-yellow-600
      border: Color(0xFFEAB308), // border-yellow-500
      text: Color(0xFF030712),
      icon: FontAwesomeIcons.crown, // fa-crown
    ),
    'Labcoat': _RankBadgeStyle(
      bg: Color(0x4DD1D5DB), // bg-gray-300/30
      border: Color(0x66D1D5DB), // border-gray-300/40
      text: Color(0xFF030712),
      icon: FontAwesomeIcons.flask, // fa-flask
    ),
    'Member': _RankBadgeStyle(
      bg: Color(0xFF030712), // bg-gray-950
      border: Color(0xFF1F2937), // border-gray-800
      text: Color(0xFF6B7280), // text-gray-500
      icon: FontAwesomeIcons.user, // fa-user
    ),
    'Blocked': _RankBadgeStyle(
      bg: Color(0xFF0A0A0A), // bg-neutral-950
      border: Color(0xFF262626), // border-neutral-800
      text: Color(0xFF737373), // text-neutral-500
      icon: FontAwesomeIcons.ban, // fa-ban
    ),
  };

  @override
  Widget build(BuildContext context) {
    final style = _styles[rank] ?? _styles['Member']!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(4), // rounded
        border: Border.all(color: style.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(style.icon, size: 9, color: style.text),
          const SizedBox(width: 3),
          Text(
            rank,
            style: TextStyle(
              fontSize: 10,
              height: 1.1,
              fontWeight: FontWeight.w600, // font-medium
              color: style.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankBadgeStyle {
  const _RankBadgeStyle({
    required this.bg,
    required this.border,
    required this.text,
    required this.icon,
  });

  final Color bg;
  final Color border;
  final Color text;
  final FaIconData icon;
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
