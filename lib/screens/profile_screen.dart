import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/auth_service.dart';
import '../api/feed_service.dart';
import '../api/profile_service.dart';
import '../config/app_config.dart';
import '../main.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/enclavd_image.dart';
import '../widgets/post_card.dart';
import '../widgets/shimmer.dart';
import 'compose_screen.dart';

/// Profile screen — the "top part" of the site's profile page (profile.php)
/// + that member's posts via GET /api/v1/posts?user_id=N.
///
/// Header (ported 1:1 from profile.php's User Info card):
///   avatar (personality border) + online dot · rank chip · username (rank
///   color) · online status · warning count · full name · followers /
///   following stats · follow button (Follow / Follow Back / Following) ·
///   prestige number + gradient bar · joined date · bio.
/// Then "Posts": the author's posts, newest first, keyset-paginated.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.userId});

  final int userId;

  static const routeName = '/profile';

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final AppServices _services;

  Profile? _profile;
  bool _profileLoading = true;
  String? _profileError;
  bool _followBusy = false;

  final List<Post> _posts = [];
  FeedPage? _lastPage;
  bool _postsLoading = false;
  bool _postsInitialLoadDone = false;
  String? _postsError;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadAll();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    _services = await AppServices.create();
    if (!mounted) return;
    setState(() {
      _profileLoading = true;
      _postsLoading = true;
      _postsInitialLoadDone = false;
      _profileError = null;
      _postsError = null;
    });
    // Profile header + first posts page in parallel.
    await Future.wait([_loadProfile(), _loadFirstPosts()]);
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _services.profile.fetchProfile(widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _profileLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _profileLoading = false;
        _profileError =
            e.status == 404 ? 'This member does not exist.' : e.message;
      });
      if (e.status == 401) {
        await _services.apiClient.clearSession();
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profileLoading = false;
        _profileError = 'Failed to load this profile.';
      });
    }
  }

  Future<void> _loadFirstPosts() async {
    try {
      final page = await _services.feed.userPosts(
        widget.userId,
        limit: AppConfig.feedPageSize,
      );
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(page.posts);
        _lastPage = page;
        _postsLoading = false;
        _postsInitialLoadDone = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _postsLoading = false;
        _postsInitialLoadDone = true;
        _postsError = e.status == 401
            ? 'Session expired. Please log in again.'
            : e.message;
      });
      if (e.status == 401) {
        await _services.apiClient.clearSession();
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _postsLoading = false;
        _postsInitialLoadDone = true;
        _postsError = 'Failed to load posts.';
      });
    }
  }

  void _onScroll() {
    if (_postsLoading || !_postsInitialLoadDone) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadNextPosts();
    }
  }

  Future<void> _loadNextPosts() async {
    final page = _lastPage;
    if (page == null || !page.hasMore || page.lastCreatedAt == null) return;
    setState(() => _postsLoading = true);
    try {
      final next = await _services.feed.userPosts(
        widget.userId,
        limit: AppConfig.feedPageSize,
        lastCreatedAt: page.lastCreatedAt,
        lastId: page.lastId,
      );
      if (!mounted) return;
      setState(() {
        _posts.addAll(next.posts);
        _lastPage = next;
        _postsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _postsLoading = false);
    }
  }

  Future<void> _refresh() => _loadAll();

  Future<void> _editPost(Post post) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ComposeScreen(post: post)),
    );
    if (saved == true && mounted) _loadFirstPosts();
  }

  Future<void> _deletePost(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this post?'),
        content: const Text('This cannot be undone. The post and its image '
            '(if any) will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete',
                style: TextStyle(color: EnclavdColors.likeActive)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _services.posts.deletePost(postId: post.id, content: post.content);
      if (!mounted) return;
      setState(() => _posts.removeWhere((p) => p.id == post.id));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Post deleted')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('Could not delete the post.')));
    }
  }

  Future<void> _toggleFollow() async {
    final profile = _profile;
    if (profile == null || profile.isOwn || _followBusy) return;
    setState(() => _followBusy = true);
    try {
      final result = await _services.profile.toggleFollow(profile.id);
      if (!mounted) return;
      setState(() {
        _profile = Profile(
          id: profile.id,
          username: profile.username,
          fullName: profile.fullName,
          profilePictureUrl: profile.profilePictureUrl,
          personalityType: profile.personalityType,
          rank: profile.rank,
          bio: profile.bio,
          prestige: profile.prestige,
          dateCreated: profile.dateCreated,
          isOnline: profile.isOnline,
          isActive: profile.isActive,
          postCount: profile.postCount,
          warningCount: profile.warningCount,
          followerCount: result.followerCount,
          followingCount: result.followingCount,
          isFollowing: result.following,
          isFollowingYou: profile.isFollowingYou,
          isOwn: profile.isOwn,
        );
        _followBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _followBusy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(
                'Could not update follow. ${e.toString().replaceFirst('ApiException', '')}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(
        title: Text(profile?.username ?? 'Profile'),
        actions: [
          if (profile != null && !profile.isOwn)
            IconButton(
              icon: const FaIcon(FontAwesomeIcons.userPlus,
                  color: EnclavdColors.link, size: 20),
              tooltip: 'Follow',
              onPressed: _toggleFollow,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: EnclavdColors.link,
        child: _buildBody(profile),
      ),
    );
  }

  Widget _buildBody(Profile? profile) {
    if (_profileLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: const [
          _ProfileHeaderSkeleton(),
          SizedBox(height: 16),
          PostCardSkeleton(),
          PostCardSkeleton(),
        ],
      );
    }
    if (_profileError != null && profile == null) {
      return _ErrorView(message: _profileError!, onRetry: _loadAll);
    }

    final itemCount = 2 + _posts.length + (_postsLoading ? 1 : 0);
    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _ProfileHeader(
              profile: profile!,
              onFollow: _toggleFollow,
              followBusy: _followBusy);
        }
        if (index == 1) {
          return const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 4),
            child: Text('Posts',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          );
        }
        if (index >= 2 + _posts.length) {
          // Footer: inline shimmer on the next page, or the posts error.
          if (_postsError != null && _posts.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Text(_postsError!,
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: EnclavdColors.textSecondary)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                      onPressed: _loadFirstPosts, child: const Text('Retry')),
                ],
              ),
            );
          }
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: ShimmerBox(width: 160, height: 22)),
          );
        }
        return PostCard(
          // Key by post id (see feed_screen: prevents stale like-state
          // reuse when the list refreshes).
          key: ValueKey(_posts[index - 2].id),
          post: _posts[index - 2],
          apiBaseUrl: AppConfig.apiBaseUrl,
          social: _services.social,
          onEditPost: _editPost,
          onDeletePost: _deletePost,
        );
      },
    );
  }
}

/// The header card — port of profile.php's User Info card.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.onFollow,
    required this.followBusy,
  });

  final Profile profile;
  final VoidCallback onFollow;
  final bool followBusy;

  @override
  Widget build(BuildContext context) {
    final personality = PersonalityColors.forType(profile.personalityType);
    final borderColor = personality ?? EnclavdColors.border;
    final rankColor = profile.isBlocked
        ? RankColors.forRank('Blocked')
        : RankColors.forRank(profile.rank);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar with personality border + online dot.
              Stack(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: EnclavdColors.cardSecondary,
                      border: Border.all(color: borderColor, width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: EnclavdImage(
                      resolveMediaUrl(AppConfig.apiBaseUrl,
                          avatarPath: profile.profilePictureUrl),
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (!profile.isOwn)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: profile.isOnline
                              ? const Color(0xFF22C55E) // green-500
                              : const Color(0xFF6B7280), // gray-500
                          border:
                              Border.all(color: EnclavdColors.card, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Rank chip (site: rank badge above the username).
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: rankColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        profile.rank,
                        style: TextStyle(
                          color: rankColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.username,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: rankColor,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              decoration: profile.isBlocked
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: rankColor,
                            ),
                          ),
                        ),
                        if (!profile.isOwn) ...[
                          const SizedBox(width: 6),
                          Text(
                            '• ${profile.isOnline ? 'online' : 'offline'}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.normal,
                              color: profile.isOnline
                                  ? const Color(0xFF4ADE80) // green-400
                                  : const Color(0xFF6B7280), // gray-500
                            ),
                          ),
                        ],
                        if (profile.warningCount > 0) ...[
                          const SizedBox(width: 6),
                          const FaIcon(FontAwesomeIcons.triangleExclamation,
                              color: EnclavdColors.warning, size: 14),
                          Text(
                            '${profile.warningCount}',
                            style: const TextStyle(
                                color: EnclavdColors.warning, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                    if (profile.fullName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(profile.fullName,
                          style: const TextStyle(
                              color: EnclavdColors.textSecondary,
                              fontSize: 13)),
                    ],
                    const SizedBox(height: 10),
                    // Follow stats (site: "N Followers • N Following").
                    Row(
                      children: [
                        Text('${profile.followerCount}',
                            style: const TextStyle(
                                color: EnclavdColors.textPrimary,
                                fontSize: 14)),
                        const SizedBox(width: 4),
                        const Text('Followers',
                            style: TextStyle(
                                color: EnclavdColors.textSecondary,
                                fontSize: 14)),
                        const SizedBox(width: 12),
                        const Text('•',
                            style: TextStyle(
                                color: EnclavdColors.textSecondary,
                                fontSize: 14)),
                        const SizedBox(width: 12),
                        Text('${profile.followingCount}',
                            style: const TextStyle(
                                color: EnclavdColors.textPrimary,
                                fontSize: 14)),
                        const SizedBox(width: 4),
                        const Text('Following',
                            style: TextStyle(
                                color: EnclavdColors.textSecondary,
                                fontSize: 14)),
                      ],
                    ),
                    if (!profile.isOwn) ...[
                      const SizedBox(height: 12),
                      _FollowButton(
                        profile: profile,
                        busy: followBusy,
                        onPressed: onFollow,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Prestige (site: number + violet/cyan pulse dots + gradient bar).
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF8B5CF6), // violet-500
                ),
              ),
              const SizedBox(width: 6),
              const Text('Prestige',
                  style: TextStyle(
                      color: EnclavdColors.textSecondary, fontSize: 12)),
              const Spacer(),
              Text('${profile.prestige}',
                  style: const TextStyle(
                      color: EnclavdColors.textSecondary, fontSize: 12)),
              const SizedBox(width: 6),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF06B6D4), // cyan-500
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Prestige bar: /1,000,000 like prestige-bar.php, clamped at 100%.
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: const Color(0xFF374151), // gray-700/50
              borderRadius: BorderRadius.circular(999),
            ),
            clipBehavior: Clip.antiAlias,
            child: FractionallySizedBox(
              widthFactor: (profile.prestige / 1000000).clamp(0.0, 1.0),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF7C3AED), // violet-600
                      Color(0xFFC026D3), // fuchsia-600
                      Color(0xFF0891B2), // cyan-600
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Joined date (site: fa-clock + "Joined M j, Y").
          Row(
            children: [
              const FaIcon(FontAwesomeIcons.clock,
                  size: 13, color: EnclavdColors.textSecondary),
              const SizedBox(width: 6),
              Text('Joined ${formatJoinedDate(profile.dateCreated)}',
                  style: const TextStyle(
                      color: EnclavdColors.textSecondary, fontSize: 13)),
            ],
          ),
          // Bio (site: bold "Bio" label + pre-line text).
          if (profile.bio.isNotEmpty || profile.isOwn) ...[
            const SizedBox(height: 12),
            const Text('Bio',
                style: TextStyle(
                    color: Color(0xFFD1D5DB), // gray-300
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
            const SizedBox(height: 2),
            Text(
              profile.bio,
              style: const TextStyle(
                  color: Color(0xFFD1D5DB), // gray-300
                  fontSize: 14,
                  height: 1.3),
            ),
          ],
        ],
      ),
    );
  }
}

/// Follow / Follow Back / Following toggle — mirrors the site's follow
/// button (fa-user-plus / fa-user-check, label flips with state).
class _FollowButton extends StatelessWidget {
  const _FollowButton({
    required this.profile,
    required this.busy,
    required this.onPressed,
  });

  final Profile profile;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final following = profile.isFollowing;
    final label = following
        ? 'Following'
        : (profile.isFollowingYou ? 'Follow Back' : 'Follow');
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor:
            following ? EnclavdColors.textPrimary : EnclavdColors.link,
        backgroundColor: following
            ? EnclavdColors.link.withValues(alpha: 0.15)
            : Colors.transparent,
        side: BorderSide(
            color: following
                ? EnclavdColors.link.withValues(alpha: 0.4)
                : EnclavdColors.link.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      icon: FaIcon(
        following ? FontAwesomeIcons.userCheck : FontAwesomeIcons.userPlus,
        size: 13,
      ),
      label: Text(label),
    );
  }
}

/// Skeleton of the header card while the profile loads.
class _ProfileHeaderSkeleton extends StatelessWidget {
  const _ProfileHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShimmerBox(width: 64, height: 64, shape: BoxShape.circle),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 90, height: 14),
                    SizedBox(height: 8),
                    ShimmerBox(width: 150, height: 20),
                    SizedBox(height: 8),
                    ShimmerBox(width: 180, height: 13),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          ShimmerBox(width: double.infinity, height: 10, borderRadius: 999),
          SizedBox(height: 14),
          ShimmerBox(width: 200, height: 13),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        const FaIcon(FontAwesomeIcons.userSlash,
            color: EnclavdColors.textSecondary, size: 56),
        const SizedBox(height: 16),
        Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: EnclavdColors.textSecondary),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      ],
    );
  }
}
