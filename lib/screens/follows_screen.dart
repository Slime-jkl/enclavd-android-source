import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/auth_service.dart';
import '../api/profile_service.dart';
import '../config/app_config.dart';
import '../services/analytics_service.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/enclavd_avatar.dart';
import '../widgets/error_view.dart';
import '../widgets/personality_chip.dart';
import '../widgets/shimmer.dart';
import 'profile_screen.dart';

/// A member's followers/following lists, opened from the profile header
/// count taps. Two tabs with per-list page state; rows carry follow
/// buttons and open the member's profile.
class FollowsScreen extends StatefulWidget {
  const FollowsScreen({
    super.key,
    required this.profile,
    required this.userId,
    required this.username,
    required this.initialTab,
    this.isOwnList = false,
  });

  final ProfileService profile;
  final int userId;
  final String username;

  /// Which list to show first (the tapped count).
  final FollowListKind initialTab;

  /// True when [userId] is the signed-in user (own-profile counts).
  final bool isOwnList;

  @override
  State<FollowsScreen> createState() => _FollowsScreenState();
}

class _FollowsScreenState extends State<FollowsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  int _lastTracked = -1;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab == FollowListKind.followers ? 0 : 1,
    );
    _tab.addListener(_onTabChanged);
    _lastTracked = _tab.index;
    trackScreen(_tab.index == 0 ? '/followers' : '/following');
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tab.index == _lastTracked) return;
    _lastTracked = _tab.index;
    trackScreen(_tab.index == 0 ? '/followers' : '/following');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: AnimatedBuilder(
          animation: _tab,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _tab.index == 0 ? 'Followers' : 'Following',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              Text(
                '@${widget.username}',
                style: const TextStyle(
                    fontSize: 12.5, color: EnclavdColors.textSecondary),
              ),
            ],
          ),
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: EnclavdColors.link,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: EnclavdColors.textPrimary,
          unselectedLabelColor: EnclavdColors.textSecondary,
          tabs: const [
            Tab(text: 'Followers'),
            Tab(text: 'Following'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _RelationList(
            key: PageStorageKey<String>('follows-${widget.userId}-followers'),
            service: widget.profile,
            userId: widget.userId,
            kind: FollowListKind.followers,
            ownerIsViewer: widget.isOwnList,
          ),
          _RelationList(
            key: PageStorageKey<String>('follows-${widget.userId}-following'),
            service: widget.profile,
            userId: widget.userId,
            kind: FollowListKind.following,
            ownerIsViewer: widget.isOwnList,
          ),
        ],
      ),
    );
  }
}

class _RelationList extends StatefulWidget {
  const _RelationList({
    super.key,
    required this.service,
    required this.userId,
    required this.kind,
    required this.ownerIsViewer,
  });

  final ProfileService service;
  final int userId;
  final FollowListKind kind;
  final bool ownerIsViewer;

  @override
  State<_RelationList> createState() => _RelationListState();
}

class _RelationListState extends State<_RelationList>
    with AutomaticKeepAliveClientMixin {
  static const int _pageSize = 20;

  final List<FollowListItem> _users = [];
  final ScrollController _scroll = ScrollController();
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  int? _busyId;

  bool get _isFollowers => widget.kind == FollowListKind.followers;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_initialLoading || _loadingMore || !_hasMore) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadFirst() async {
    // Refresh with rows on screen keeps them; only a bare first load
    // shows the skeleton.
    final bare = _users.isEmpty;
    if (bare) {
      setState(() {
        _initialLoading = true;
        _error = null;
      });
    }
    try {
      final page = await widget.service.listFollows(
        userId: widget.userId,
        kind: widget.kind,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _users
          ..clear()
          ..addAll(page.users);
        _hasMore = page.hasMore;
        _initialLoading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      if (bare) {
        setState(() {
          _initialLoading = false;
          _error = _isFollowers
              ? 'Failed to load followers.'
              : 'Failed to load following.';
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.service.listFollows(
        userId: widget.userId,
        kind: widget.kind,
        limit: _pageSize,
        offset: _users.length,
      );
      if (!mounted) return;
      setState(() {
        _users.addAll(page.users);
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleFollow(FollowListItem user) async {
    if (_busyId != null) return;
    setState(() => _busyId = user.id);
    try {
      final result = await widget.service.toggleFollow(user.id);
      if (!mounted) return;
      setState(() {
        _busyId = null;
        // Unfollow from the viewer's own Following list: the row no
        // longer belongs there. Everywhere else the row stays and the
        // button state flips.
        if (widget.ownerIsViewer && !_isFollowers && !result.following) {
          _users.removeWhere((u) => u.id == user.id);
        } else {
          final i = _users.indexWhere((u) => u.id == user.id);
          if (i >= 0) {
            _users[i] = _users[i].copyWith(isFollowing: result.following);
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('Could not update the follow.')));
    }
  }

  void _openUser(FollowListItem user) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(userId: user.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_initialLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: const [
          _UserRowSkeleton(),
          SizedBox(height: 8),
          _UserRowSkeleton(),
          SizedBox(height: 8),
          _UserRowSkeleton(),
          SizedBox(height: 8),
          _UserRowSkeleton(),
        ],
      );
    }
    if (_error != null && _users.isEmpty) {
      return ErrorView(message: _error!, onRetry: _loadFirst);
    }
    if (_users.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFirst,
        color: EnclavdColors.link,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 120, bottom: 40),
              child: Column(
                children: [
                  const FaIcon(FontAwesomeIcons.userGroup,
                      size: 40, color: EnclavdColors.textSecondary),
                  const SizedBox(height: 12),
                  Text(
                    _emptyText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: EnclavdColors.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFirst,
      color: EnclavdColors.link,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _users.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= _users.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: ShimmerBox(width: 160, height: 22)),
            );
          }
          final user = _users[index];
          return _UserRow(
            user: user,
            busy: _busyId == user.id,
            onTap: user.isOwn ? null : () => _openUser(user),
            onToggle:
                (user.isOwn || user.isBlocked) ? null : () => _toggleFollow(user),
          );
        },
      ),
    );
  }

  String get _emptyText {
    if (_isFollowers) return 'No followers yet.';
    return widget.ownerIsViewer
        ? 'You are not following anyone yet.'
        : 'Not following anyone yet.';
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.busy,
    required this.onTap,
    required this.onToggle,
  });

  final FollowListItem user;
  final bool busy;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final blocked = user.isBlocked;
    final nameColor = blocked
        ? RankColors.forRank('Blocked')
        : RankColors.forRank(user.rank);
    final personality = PersonalityColors.forType(user.personalityType);
    final subtitle =
        user.fullName.isNotEmpty ? user.fullName : user.bio;
    return Material(
      color: EnclavdColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: EnclavdColors.border),
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
                borderColor: personality ?? EnclavdColors.border,
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
                              decoration: blocked
                                  ? TextDecoration.lineThrough
                                  : null,
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
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: EnclavdColors.textSecondary, fontSize: 12.5),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (user.isOwn)
                const Text(
                  'You',
                  style: TextStyle(
                      color: EnclavdColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                )
              else if (onToggle != null)
                _FollowButton(user: user, busy: busy, onPressed: onToggle!),
            ],
          ),
        ),
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({
    required this.user,
    required this.busy,
    required this.onPressed,
  });

  final FollowListItem user;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final following = user.isFollowing;
    final label = following
        ? 'Following'
        : (user.isFollowingYou ? 'Follow Back' : 'Follow');
    // Site follow-button look, sized for a list row.
    return SizedBox(
      height: 30,
      child: TextButton(
        onPressed: busy ? null : onPressed,
        style: TextButton.styleFrom(
          foregroundColor:
              following ? const Color(0xFFD1D5DB) : Colors.white, // gray-300
          backgroundColor:
              following ? const Color(0xFF030712) : EnclavdColors.primaryButton,
          disabledForegroundColor:
              following ? const Color(0xFF6B7280) : Colors.white70,
          disabledBackgroundColor: following
              ? const Color(0xFF030712).withValues(alpha: 0.6)
              : EnclavdColors.primaryButton.withValues(alpha: 0.6),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: following
                ? const BorderSide(color: EnclavdColors.border)
                : BorderSide.none,
          ),
          textStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        child: Text(label),
      ),
    );
  }
}

class _UserRowSkeleton extends StatelessWidget {
  const _UserRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          ShimmerBox(width: 44, height: 44, shape: BoxShape.circle),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 120, height: 14),
                SizedBox(height: 8),
                ShimmerBox(width: 170, height: 12),
              ],
            ),
          ),
          SizedBox(width: 8),
          ShimmerBox(width: 76, height: 30, borderRadius: 8),
        ],
      ),
    );
  }
}
