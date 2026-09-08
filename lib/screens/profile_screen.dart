import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/activity_service.dart';
import '../api/api_client.dart';
import '../api/auth_service.dart';
import '../api/feed_service.dart';
import '../api/profile_service.dart';
import '../config/app_config.dart';
import '../main.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/activity_card.dart';
import '../widgets/enclavd_avatar.dart';
import '../widgets/error_view.dart';
import '../widgets/personality_chip.dart';
import '../widgets/post_card.dart';
import '../widgets/rank_badge.dart';
import '../widgets/shimmer.dart';
import 'chat_screen.dart';
import 'compose_screen.dart';
import 'follows_screen.dart';
import 'personality_screen.dart';
import 'post_detail_screen.dart';
import '../services/analytics_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.userId});

  final int userId;

  static const routeName = '/profile';

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AppServices _services;

  Profile? _profile;
  bool _profileLoading = true;
  String? _profileError;
  bool _followBusy = false;
  bool _messageBusy = false;

  final List<Post> _posts = [];
  FeedPage? _lastPage;
  bool _postsLoading = false;
  bool _postsInitialLoadDone = false;
  String? _postsError;

  // Own-profile Posts | Activity tabs (interaction history). Activity
  // loads lazily on the first visit to its tab.
  late final TabController _tabs;
  int _lastTab = 0;
  bool _activityLoadDone = false;
  final List<ActivityItem> _activity = [];
  bool _activityLoading = false; // first load / refresh in flight
  bool _activityLoadingMore = false;
  bool _activityHasMore = false;
  String? _activityError;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    trackScreen('/profile');
    _scrollController.addListener(_onScroll);
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(_onTabChanged);
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
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
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 400) return;
    if (_tabs.index == 1) {
      if (_activityLoadDone &&
          !_activityLoading &&
          !_activityLoadingMore &&
          _activityHasMore &&
          _activityError == null) {
        _loadNextActivity();
      }
      return;
    }
    if (_postsLoading || !_postsInitialLoadDone) return;
    _loadNextPosts();
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

  /// Loads (or refreshes) the first activity page. The tab is only
  /// reachable on the own profile, so the response is always this user's.
  Future<void> _loadFirstActivity() async {
    if (_activityLoading) return;
    setState(() {
      _activityLoading = true;
      _activityError = null;
    });
    try {
      final page = await _services.activity.fetch(
        limit: AppConfig.feedPageSize,
      );
      if (!mounted) return;
      setState(() {
        _activity
          ..clear()
          ..addAll(page.items);
        _activityHasMore = page.hasMore;
        _activityLoading = false;
        _activityLoadDone = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _activityLoading = false;
        _activityLoadDone = true;
        _activityError = e.status == 401
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
        _activityLoading = false;
        _activityLoadDone = true;
        _activityError = 'Failed to load activity.';
      });
    }
  }

  Future<void> _loadNextActivity() async {
    if (_activityLoadingMore || !_activityHasMore) return;
    setState(() => _activityLoadingMore = true);
    try {
      final page = await _services.activity.fetch(
        limit: AppConfig.feedPageSize,
        offset: _activity.length,
      );
      if (!mounted) return;
      setState(() {
        _activity.addAll(page.items);
        _activityHasMore = page.hasMore;
        _activityLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _activityLoadingMore = false);
    }
  }

  void _onTabChanged() {
    final index = _tabs.index;
    if (index == _lastTab) return;
    _lastTab = index;
    setState(() {}); // repaint the tab colors/underline
    trackScreen(index == 1 ? '/activity' : '/profile');
    // Different content under the header: restart at the top.
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (index == 1 && !_activityLoadDone) {
      _loadFirstActivity();
    }
  }

  void _openActivityItem(ActivityItem item) {
    if (item.type != ActivityType.follow && item.post != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PostDetailScreen(postId: item.post!.id),
        ),
      );
      return;
    }
    final user = item.user;
    if (user != null && !user.isOwn) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProfileScreen(userId: user.id),
        ),
      );
    }
  }

  Future<void> _refresh() async {
    await _loadAll();
    // Keep a loaded activity tab true after pull-to-refresh.
    if (_activityLoadDone) await _loadFirstActivity();
  }

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
          blockReason: profile.blockReason,
          postCount: profile.postCount,
          warningCount: profile.warningCount,
          warnings: profile.warnings,
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
                'Could not update follow. ${friendlyErrorText(e)}')));
    }
  }

  Future<void> _openFollowList(FollowListKind kind) async {
    final profile = _profile;
    if (profile == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => FollowsScreen(
          profile: _services.profile,
          userId: profile.id,
          username: profile.username,
          initialTab: kind,
          isOwnList: profile.isOwn,
        ),
      ),
    );
    // Follows made from the lists (follow-backs, own-list unfollows)
    // change the header counts; re-fetch to stay in sync.
    if (mounted) _loadProfile();
  }

  Future<void> _openConversation() async {
    final profile = _profile;
    if (profile == null || profile.isOwn || profile.isBlocked) return;
    setState(() => _messageBusy = true);
    try {
      final me = await _services.auth.me();
      if (me == null) {
        throw const ApiException('Could not start a conversation.');
      }
      final conversationId = await _services.messages.start(profile.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            myUserId: me.id,
            messages: _services.messages,
            realtime: _services.realtime,
            participantId: profile.id,
            participantName: profile.username,
            participantAvatar: profile.profilePictureUrl,
            participantPersonality: profile.personalityType,
            participantIsOnline: profile.isOnline,
          ),
        ),
      );
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
            const SnackBar(content: Text('Could not start a conversation.')));
    } finally {
      if (mounted) setState(() => _messageBusy = false);
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
      final activitySkeleton = (profile?.isOwn ?? false) && _tabs.index == 1;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          const _ProfileHeaderSkeleton(),
          const SizedBox(height: 16),
          if (activitySkeleton) ...[
            const ActivityCardSkeleton(),
            const SizedBox(height: 8),
            const ActivityCardSkeleton(),
            const SizedBox(height: 8),
            const ActivityCardSkeleton(),
          ] else ...[
            const PostCardSkeleton(),
            const PostCardSkeleton(),
          ],
        ],
      );
    }
    if (_profileError != null && profile == null) {
      return ErrorView(message: _profileError!, onRetry: _loadAll);
    }

    final isOwn = profile?.isOwn ?? false;
    final onActivity = isOwn && _tabs.index == 1;
    final listLength = onActivity ? _activity.length : _posts.length;
    final footer = onActivity ? _activityFooter() : _postsFooter();
    final itemCount = 2 + listLength + (footer != null ? 1 : 0);
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
              followBusy: _followBusy,
              onMessage: _openConversation,
              messageBusy: _messageBusy,
              onFollowersTap: () =>
                  _openFollowList(FollowListKind.followers),
              onFollowingTap: () =>
                  _openFollowList(FollowListKind.following));
        }
        if (index == 1) {
          // The own profile splits its history into two tabs; other
          // members keep the plain posts heading.
          if (isOwn) {
            return Container(
              margin: const EdgeInsets.only(top: 10),
              child: TabBar(
                controller: _tabs,
                dividerColor: EnclavdColors.border,
                indicatorColor: EnclavdColors.link,
                indicatorSize: TabBarIndicatorSize.label,
                indicatorWeight: 3,
                labelColor: EnclavdColors.textPrimary,
                unselectedLabelColor: EnclavdColors.textSecondary,
                labelStyle: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(
                    icon: FaIcon(FontAwesomeIcons.fileLines, size: 15),
                    text: 'Posts',
                  ),
                  Tab(
                    icon: FaIcon(FontAwesomeIcons.clockRotateLeft, size: 15),
                    text: 'Activity',
                  ),
                ],
              ),
            );
          }
          return const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 4),
            child: Text('Posts',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          );
        }
        if (index >= 2 + listLength) {
          return footer!;
        }
        if (onActivity) {
          return _activityRow(_activity[index - 2]);
        }
        return PostCard(
          // Key by post id: prevents stale like-state reuse on refresh.
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

  /// One activity entry: an action strip ("You liked/commented/followed")
  /// above the normal post card (like/comment) or member card (follow).
  Widget _activityRow(ActivityItem item) {
    final Widget body;
    if (item.type == ActivityType.follow) {
      body = ActivityFollowCard(
        user: item.user!,
        onTap: () => _openActivityItem(item),
      );
    } else {
      final post = item.post!;
      body = PostCard(
        key: ValueKey(post.id),
        post: post,
        apiBaseUrl: AppConfig.apiBaseUrl,
        social: _services.social,
        onEditPost: _editPost,
        onDeletePost: _deletePost,
      );
    }
    return Column(
      key: ValueKey('activity-${item.type.wire}-${item.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: ActivityNote(item: item),
        ),
        body,
        // Follow rows have no card margin of their own; keep the rhythm.
        if (item.type == ActivityType.follow) const SizedBox(height: 22),
      ],
    );
  }

  /// Posts-list footer: first-page error, empty state, or the next-page
  /// shimmer. Null when the list is complete on screen.
  Widget? _postsFooter() {
    if (_postsError != null && _posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(_postsError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: EnclavdColors.textSecondary)),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _loadFirstPosts, child: const Text('Retry')),
          ],
        ),
      );
    }
    final showEmptyState =
        !_postsLoading && _postsError == null && _posts.isEmpty;
    if (showEmptyState) {
      final own = _profile?.isOwn ?? false;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(
            own ? 'No posts yet.' : 'This user has no posts.',
            style: const TextStyle(
                color: EnclavdColors.textSecondary, fontSize: 14),
          ),
        ),
      );
    }
    if (_postsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: ShimmerBox(width: 160, height: 22)),
      );
    }
    return null;
  }

  /// Activity-tab footer: first-visit skeleton, first-page error, or the
  /// empty state. Null when the list is complete on screen.
  Widget? _activityFooter() {
    // First visit OR a retry with nothing on screen yet: skeleton cards
    // while the page loads (a bare retry would otherwise flash the empty
    // state - the error is cleared before the request starts).
    if (!_activityLoadDone || (_activityLoading && _activity.isEmpty)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            ActivityCardSkeleton(),
            SizedBox(height: 8),
            ActivityCardSkeleton(),
            SizedBox(height: 8),
            ActivityCardSkeleton(),
          ],
        ),
      );
    }
    if (_activityError != null && _activity.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(_activityError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: EnclavdColors.textSecondary)),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _loadFirstActivity, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_activity.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            FaIcon(FontAwesomeIcons.clockRotateLeft,
                color: EnclavdColors.textSecondary, size: 30),
            SizedBox(height: 12),
            Text(
              'No activity yet',
              style: TextStyle(
                  color: EnclavdColors.textSecondary, fontSize: 15),
            ),
            SizedBox(height: 4),
            Text(
              'Posts you like, comments you leave and people you follow '
              'will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: EnclavdColors.textSecondary, fontSize: 12.5),
            ),
          ],
        ),
      );
    }
    if (_activityLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: ShimmerBox(width: 160, height: 22)),
      );
    }
    return null;
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.onFollow,
    required this.followBusy,
    required this.onMessage,
    required this.messageBusy,
    required this.onFollowersTap,
    required this.onFollowingTap,
  });

  final Profile profile;
  final VoidCallback onFollow;
  final bool followBusy;
  final VoidCallback onMessage;
  final bool messageBusy;

  /// Open the connections screen on the tapped count.
  final VoidCallback onFollowersTap;
  final VoidCallback onFollowingTap;

  @override
  Widget build(BuildContext context) {
    final personality = PersonalityColors.forType(profile.personalityType);
    final borderColor = personality ?? EnclavdColors.border;
    final rankColor = profile.isBlocked
        ? RankColors.forRank('Blocked')
        : RankColors.forRank(profile.rank);

    // Blocked banner sits above the card (server truth on load).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (profile.isBlocked) ...[
          _BlockedBanner(profile: profile),
          const SizedBox(height: 10),
        ],
        Container(
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
                  EnclavdAvatar(
                    size: 64,
                    url: resolveMediaUrl(AppConfig.apiBaseUrl,
                        avatarPath: profile.profilePictureUrl),
                    borderColor: borderColor,
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
                    // Rank badge above the username (same chip as the likers sheet).
                    RankBadge(rank: profile.rank),
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
                        if (profile.personalityType != null) ...[
                          const SizedBox(width: 6),
                          PersonalityChip(type: profile.personalityType!),
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
                    // Follow stats; each count opens the connections
                    // screen (blocked profiles keep a plain read-only row).
                    Row(
                      children: [
                        InkWell(
                          onTap: profile.isBlocked ? null : onFollowersTap,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            child: Row(
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
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('-',
                            style: TextStyle(
                                color: EnclavdColors.textSecondary,
                                fontSize: 14)),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: profile.isBlocked ? null : onFollowingTap,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            child: Row(
                              children: [
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
                          ),
                        ),
                      ],
                    ),
                    if (!profile.isOwn) ...[
                      const SizedBox(height: 12),
                      // Follow + Message in one row; message disables when blocked.
                      Row(
                        children: [
                          Expanded(
                            child: _FollowButton(
                              profile: profile,
                              busy: followBusy,
                              onPressed: onFollow,
                            ),
                          ),
                          if (AppConfig.enableChat) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MessageButton(
                                profile: profile,
                                busy: messageBusy,
                                onPressed: onMessage,
                              ),
                            ),
                          ],
                        ],
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
              Text(formatPrestige(profile.prestige),
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
          // Track: gray-700/50 + always-visible 20% gradient; fill on top,
          // clamped at 100%.
          Container(
            height: 10,
            decoration: BoxDecoration(
              color: const Color(0xFF374151), // gray-700/50
              borderRadius: BorderRadius.circular(999),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Always-visible 20% gradient (the site's animate-pulse).
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0x337C3AED), // violet-600/20
                        Color(0x33C026D3), // fuchsia-600/20
                        Color(0x330891B2), // cyan-600/20
                      ],
                    ),
                  ),
                ),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (profile.prestige / 1000000).clamp(0.0, 1.0),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0xFF7C3AED), // violet-600
                          Color(0xFFC026D3), // fuchsia-600
                          Color(0xFF0891B2), // cyan-600
                        ],
                      ),
                    ),
                  ),
                ),
              ],
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
            // Warnings (site: info-yellow list under the bio).
            if (profile.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final w in profile.warnings) _WarningCard(warning: w),
            ],
            // View personality
            if (profile.personalityType != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PersonalityScreen(userId: profile.id),
                  ),
                ),
                icon: const FaIcon(FontAwesomeIcons.brain,
                    size: 14, color: EnclavdColors.link),
                label: const Text('View personality'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: EnclavdColors.link,
                  side: const BorderSide(color: EnclavdColors.border),
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
  }
}

class _BlockedBanner extends StatelessWidget {
  const _BlockedBanner({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final reason = profile.blockReason.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x667F1D1D), // bg-red-900/40
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x80EF4444)), // border-red-500/50
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FaIcon(FontAwesomeIcons.ban,
              color: Color(0xFFF87171), size: 15), // red-400
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reason.isNotEmpty
                  ? 'This user has been blocked: $reason'
                  : 'This user has been blocked.',
              style: const TextStyle(
                  color: Color(0xFFFECACA), // red-200
                  fontSize: 13,
                  height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.warning});

  final UserWarning warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0x14FACC15), // bg-yellow-400/8
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x4DA16207)), // border-yellow-700/30
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FaIcon(FontAwesomeIcons.triangleExclamation,
              color: EnclavdColors.warning, size: 14),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Warning from ',
                        style: TextStyle(
                            color: EnclavdColors.warning, fontSize: 13)),
                    Flexible(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ProfileScreen(userId: warning.adminId),
                            ),
                          );
                        },
                        child: Text(
                          '@${warning.adminUsername}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: EnclavdColors.link,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
                if (warning.reason.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    warning.reason,
                    style: const TextStyle(
                        color: EnclavdColors.textSecondary, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 2),
                // Site: "({N}d remaining)" (ceil(max(0, seconds)/86400)).
                Text(
                  '${warning.daysLeft}d left',
                  style: const TextStyle(
                      color: Color(0xFF6B7280), fontSize: 12), // gray-500
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
    // Site .follow-button: solid, not outlined; hairline border on the
    // following state so it stays visible on touch.
    return SizedBox(
      height: 32, // h-8
      child: TextButton.icon(
        onPressed: busy ? null : onPressed,
        style: TextButton.styleFrom(
          foregroundColor:
              following ? const Color(0xFFD1D5DB) : Colors.white, // gray-300
          backgroundColor:
              following ? const Color(0xFF030712) : EnclavdColors.primaryButton,
          disabledForegroundColor: following
              ? const Color(0xFF6B7280)
              : Colors.white.withValues(alpha: 0.7),
          disabledBackgroundColor: following
              ? const Color(0xFF030712).withValues(alpha: 0.6)
              : EnclavdColors.primaryButton.withValues(alpha: 0.6),
          padding: const EdgeInsets.symmetric(horizontal: 16), // px-4
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8), // rounded-lg
            side: following
                ? const BorderSide(color: EnclavdColors.border) // gray-800
                : BorderSide.none,
          ),
          textStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        icon: FaIcon(
          following ? FontAwesomeIcons.userCheck : FontAwesomeIcons.userPlus,
          size: 13,
        ),
        label: Text(label),
      ),
    );
  }
}

class _MessageButton extends StatelessWidget {
  const _MessageButton({
    required this.profile,
    required this.busy,
    required this.onPressed,
  });

  final Profile profile;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final blocked = profile.isBlocked;
    return SizedBox(
      height: 32, // h-8 (matches .follow-button)
      child: TextButton.icon(
        onPressed: (blocked || busy) ? null : onPressed,
        style: TextButton.styleFrom(
          foregroundColor: blocked
              ? const Color(0xFF6B7280) // text-gray-500
              : EnclavdColors.link, // text-blue-400
          backgroundColor: blocked
              ? const Color(0xFF1F2937) // bg-gray-800
              : Colors.transparent,
          disabledForegroundColor: const Color(0xFF6B7280),
          disabledBackgroundColor: const Color(0xFF1F2937),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8), // rounded-lg
            side: BorderSide(
              color: blocked
                  ? const Color(0xFF374151) // border-gray-700
                  : const Color(0x805FA5FA), // border-blue-500/50
            ),
          ),
          textStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        icon: FaIcon(
          blocked ? FontAwesomeIcons.ban : FontAwesomeIcons.envelope,
          size: 13,
        ),
        label: Text(blocked ? 'Message' : 'Message'),
      ),
    );
  }
}

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

/// The site's prestige display: dot thousands separators.
String formatPrestige(int value) {
  final s = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write('.');
    out.write(s[i]);
  }
  return out.toString();
}
