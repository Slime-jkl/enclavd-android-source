import 'dart:async';
import 'dart:math' as math;

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/activity_service.dart';
import '../api/api_client.dart';
import '../api/auth_service.dart';
import '../api/feed_service.dart';
import '../api/personality_service.dart';
import '../api/profile_service.dart';
import '../api/site_config_service.dart';
import '../config/app_config.dart';
import '../main.dart';
import '../theme/enclavd_theme.dart';
import '../utils/post_list.dart';
import '../widgets/activity_card.dart';
import '../widgets/enclavd_avatar.dart';
import '../widgets/enclavd_image.dart';
import '../widgets/profile/personality_circuit.dart';
import '../widgets/ui/app_button.dart';
import '../widgets/ui/app_dialog.dart';
import '../widgets/ui/app_loading.dart';
import '../widgets/ui/app_motion.dart';
import '../widgets/ui/app_segmented_tabs.dart';
import '../widgets/ui/app_sheet.dart';
import '../widgets/ui/app_surface.dart';
import '../widgets/error_view.dart';
import '../widgets/invitation_info.dart';
import '../widgets/personality_chip.dart';
import '../widgets/personality_widgets.dart';
import '../widgets/post_card.dart';
import '../widgets/rank_badge.dart';
import '../widgets/shimmer.dart';
import 'chat_screen.dart';
import 'compose_screen.dart';
import 'follows_screen.dart';
import 'hashtag_screen.dart';
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

  // Featured / About / Personality tabs above the feed (web profileTab).
  int _infoTab = 0;

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
    final saved = await ComposeScreen.open(context, post: post);
    if (saved == true && mounted) _loadFirstPosts();
  }

  /// A card reported its own like/comment/ignite state: the list owns the copy
  /// a rebuilt card reads, so take it here or the card reverts on scroll.
  void _postUpdated(Post post) {
    setState(() => replacePost(_posts, post));
  }

  void _activityPostUpdated(Post post) {
    setState(() {
      final i = _activity.indexWhere((a) => a.post?.id == post.id);
      if (i != -1) _activity[i] = _activity[i].copyWith(post: post);
    });
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
            child: Text('Delete',
                style: TextStyle(color: context.enclavd.likeActive)),
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
        _profile = profile.copyWith(
          followerCount: result.followerCount,
          followingCount: result.followingCount,
          isFollowing: result.following,
        );
        _followBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _followBusy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text('Could not update follow. ${friendlyErrorText(e)}')));
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
            participantRank: profile.isBlocked ? 'Blocked' : profile.rank,
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

  void _selectInfoTab(int index) => setState(() => _infoTab = index);

  void _openPost(int postId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PostDetailScreen(postId: postId),
      ),
    );
  }

  void _openProfile(int userId) {
    if (userId == widget.userId) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(userId: userId),
      ),
    );
  }

  /// Own bio editor (site: the Edit link on the header bio card).
  Future<void> _editBio() async {
    final profile = _profile;
    if (profile == null) return;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _BioDialog(initialBio: profile.bio),
    );
    if (text == null || !mounted) return;
    final bio = text.trim();
    if (bio == profile.bio) return;
    try {
      await _services.profile.updateBio(bio);
      if (!mounted) return;
      setState(() => _profile = profile.copyWith(bio: bio));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Could not save bio.')));
    }
  }

  /// Hashtag sheet: own profile can search/follow; others just browse.
  Future<void> _openTags() async {
    final profile = _profile;
    if (profile == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TagsSheet(profile: profile, service: _services.profile),
    );
    // Own follows changed while the sheet was open.
    if (mounted && profile.isOwn) _loadProfile();
  }

  Future<void> _openFeaturedPicker() async {
    final profile = _profile;
    if (profile == null || !profile.isOwn) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeaturedPickerSheet(
        profile: profile,
        service: _services.profile,
      ),
    );
    if (saved == true && mounted) await _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      // The profile header already names the member and carries Follow, so
      // the bar keeps only the shared back chevron.
      appBar: AppBar(),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: context.enclavd.link,
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
    final itemCount = 3 + listLength + (footer != null ? 1 : 0);
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
              onFollowersTap: () => _openFollowList(FollowListKind.followers),
              onFollowingTap: () => _openFollowList(FollowListKind.following),
              onEditBio: _editBio,
              onTagsTap: _openTags);
        }
        if (index == 1) {
          return _ProfileInfoSection(
            profile: profile!,
            tab: _infoTab,
            onTabChanged: _selectInfoTab,
            onAddFeatured: _openFeaturedPicker,
            onOpenPost: _openPost,
            onOpenProfile: _openProfile,
            services: _services,
          );
        }
        if (index == 2) {
          // The own profile splits its history into two tabs; other
          // members keep the plain posts heading.
          if (isOwn) {
            return Container(
              margin: const EdgeInsets.only(top: 10),
              child: TabBar(
                controller: _tabs,
                dividerColor: context.enclavd.border,
                indicatorColor: context.enclavd.link,
                indicatorSize: TabBarIndicatorSize.label,
                indicatorWeight: 3,
                labelColor: context.enclavd.textPrimary,
                unselectedLabelColor: context.enclavd.textSecondary,
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
        if (index >= 3 + listLength) {
          return footer!;
        }
        if (onActivity) {
          return _activityRow(_activity[index - 3]);
        }
        return PostCard(
          // Key by post id: prevents stale like-state reuse on refresh.
          key: ValueKey(_posts[index - 3].id),
          post: _posts[index - 3],
          apiBaseUrl: AppConfig.apiBaseUrl,
          social: _services.social,
          onEditPost: _editPost,
          onDeletePost: _deletePost,
          onPostUpdated: _postUpdated,
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
        onPostUpdated: _activityPostUpdated,
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
                style: TextStyle(color: context.enclavd.textSecondary)),
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
            style:
                TextStyle(color: context.enclavd.textSecondary, fontSize: 14),
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
                style: TextStyle(color: context.enclavd.textSecondary)),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _loadFirstActivity, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_activity.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            FaIcon(FontAwesomeIcons.clockRotateLeft,
                color: context.enclavd.textSecondary, size: 30),
            const SizedBox(height: 12),
            Text(
              'No activity yet',
              style:
                  TextStyle(color: context.enclavd.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Posts you like, comments you leave and people you follow '
              'will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: context.enclavd.textSecondary, fontSize: 12.5),
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
    required this.onEditBio,
    required this.onTagsTap,
  });

  final Profile profile;
  final VoidCallback onFollow;
  final bool followBusy;
  final VoidCallback onMessage;
  final bool messageBusy;

  /// Open the connections screen on the tapped count.
  final VoidCallback onFollowersTap;
  final VoidCallback onFollowingTap;
  final VoidCallback onEditBio;
  final VoidCallback onTagsTap;

  @override
  Widget build(BuildContext context) {
    final rankColor = profile.isBlocked
        ? context.enclavd.rankName('Blocked')
        : context.enclavd.rankName(profile.rank);

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
            color: context.enclavd.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.enclavd.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar with the rank's border + online dot.
                  Stack(
                    children: [
                      EnclavdAvatar(
                        size: 64,
                        url: resolveMediaUrl(AppConfig.apiBaseUrl,
                            avatarPath: profile.profilePictureUrl),
                        rank: profile.isBlocked ? 'Blocked' : profile.rank,
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
                              border: Border.all(
                                  color: context.enclavd.card, width: 2),
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
                              FaIcon(FontAwesomeIcons.triangleExclamation,
                                  color: context.enclavd.warning, size: 14),
                              const SizedBox(width: 3),
                              Text(
                                '${profile.warningCount}',
                                style: TextStyle(
                                    color: context.enclavd.warning,
                                    fontSize: 11),
                              ),
                            ],
                          ],
                        ),
                        if (profile.fullName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(profile.fullName,
                              style: TextStyle(
                                  color: context.enclavd.textSecondary,
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
                                        style: TextStyle(
                                            color: context.enclavd.textPrimary,
                                            fontSize: 14)),
                                    const SizedBox(width: 4),
                                    Text('Followers',
                                        style: TextStyle(
                                            color:
                                                context.enclavd.textSecondary,
                                            fontSize: 14)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('-',
                                style: TextStyle(
                                    color: context.enclavd.textSecondary,
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
                                        style: TextStyle(
                                            color: context.enclavd.textPrimary,
                                            fontSize: 14)),
                                    const SizedBox(width: 4),
                                    Text('Following',
                                        style: TextStyle(
                                            color:
                                                context.enclavd.textSecondary,
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
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _FollowButton(
                                profile: profile,
                                busy: followBusy,
                                onPressed: onFollow,
                              ),
                              if (AppConfig.enableChat) ...[
                                const SizedBox(width: 8),
                                _MessageButton(
                                  profile: profile,
                                  busy: messageBusy,
                                  onPressed: onMessage,
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
              const SizedBox(height: 10),
              // Followed hashtags summary (site: hashtag link above prestige).
              InkWell(
                onTap: onTagsTap,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FaIcon(FontAwesomeIcons.hashtag,
                          size: 12, color: context.enclavd.link),
                      const SizedBox(width: 6),
                      Text(
                        followedTagsLabel(profile),
                        style: TextStyle(
                            color: context.enclavd.link, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
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
                  Text('Prestige',
                      style: TextStyle(
                          color: context.enclavd.textSecondary, fontSize: 12)),
                  const Spacer(),
                  Text(formatPrestige(profile.prestige),
                      style: TextStyle(
                          color: context.enclavd.textSecondary, fontSize: 12)),
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
              // Bio card (site: inset bio box with an Edit action for the owner).
              if (profile.bio.isNotEmpty || profile.isOwn) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.enclavd.cardSecondary,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.enclavd.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Bio',
                              style: TextStyle(
                                  color: context.enclavd.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          if (profile.isOwn) ...[
                            const Spacer(),
                            InkWell(
                              onTap: onEditBio,
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                child: Row(
                                  children: [
                                    FaIcon(FontAwesomeIcons.penToSquare,
                                        size: 11, color: context.enclavd.link),
                                    const SizedBox(width: 4),
                                    Text('Edit',
                                        style: TextStyle(
                                            color: context.enclavd.link,
                                            fontSize: 12.5)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        profile.bio.isEmpty ? 'No bio yet.' : profile.bio,
                        style: TextStyle(
                            color: profile.bio.isEmpty
                                ? context.enclavd.textSecondary
                                : context.enclavd.textPrimary,
                            fontSize: 14,
                            height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
              // Warnings (site: info-yellow list under the bio).
              if (profile.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final w in profile.warnings) _WarningCard(warning: w),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Footer text for the header hashtag link (web wording).
String followedTagsLabel(Profile profile) {
  final count = profile.followedTags.length;
  final plural = count == 1 ? 'hashtag' : 'hashtags';
  if (profile.isOwn) {
    return count == 0
        ? 'Discover hashtags to follow'
        : 'Following $count $plural';
  }
  return 'Follows $count $plural';
}

/// Featured | About | Personality panel sitting between the header and the
/// feed (web profile.php's Alpine tab bar).
class _ProfileInfoSection extends StatelessWidget {
  const _ProfileInfoSection({
    required this.profile,
    required this.tab,
    required this.onTabChanged,
    required this.onAddFeatured,
    required this.onOpenPost,
    required this.onOpenProfile,
    required this.services,
  });

  final Profile profile;
  final int tab;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onAddFeatured;
  final ValueChanged<int> onOpenPost;
  final ValueChanged<int> onOpenProfile;
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final labels = <String>[
      'Featured',
      'About',
      if (profile.personalityType != null) 'Personality',
    ];
    final icons = <FaIconData>[
      FontAwesomeIcons.image,
      FontAwesomeIcons.user,
      if (profile.personalityType != null) FontAwesomeIcons.brain,
    ];
    final index = tab.clamp(0, labels.length - 1);
    final Widget panel;
    if (index == 0) {
      panel = _FeaturedPanel(
        key: const ValueKey('profile-featured'),
        profile: profile,
        onAdd: onAddFeatured,
        onOpenPost: onOpenPost,
      );
    } else if (index == 1) {
      panel = _AboutPanel(
        key: const ValueKey('profile-about'),
        profile: profile,
        onOpenProfile: onOpenProfile,
      );
    } else {
      panel = _PersonalityPanel(
        key: const ValueKey('profile-personality'),
        profile: profile,
        services: services,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        AppSegmentedTabs(
          items: [
            for (var i = 0; i < labels.length; i++)
              AppTabItem(label: labels[i], icon: icons[i]),
          ],
          index: index,
          onChanged: onTabChanged,
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: AppMotion.normal,
          switchInCurve: AppMotion.enter,
          switchOutCurve: AppMotion.exit,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: panel,
        ),
      ],
    );
  }
}

class _FeaturedPanel extends StatelessWidget {
  const _FeaturedPanel({
    super.key,
    required this.profile,
    required this.onAdd,
    required this.onOpenPost,
  });

  final Profile profile;
  final VoidCallback onAdd;
  final ValueChanged<int> onOpenPost;

  @override
  Widget build(BuildContext context) {
    final images = profile.featuredImages.take(6).toList();
    return AppSurface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Featured',
                  style: TextStyle(
                      color: context.enclavd.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              if (profile.isOwn)
                AppButton(
                  label: images.isEmpty ? 'Add featured' : 'Edit featured',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.small,
                  icon: FontAwesomeIcons.plus,
                  onPressed: onAdd,
                ),
            ],
          ),
          if (images.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Column(
                  children: [
                    FaIcon(FontAwesomeIcons.star,
                        size: 28, color: context.enclavd.textSecondary),
                    const SizedBox(height: 8),
                    Text('No featured posts',
                        style: TextStyle(
                            color: context.enclavd.textSecondary,
                            fontSize: 13)),
                  ],
                ),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 6.0;
                final width = (constraints.maxWidth - spacing * 2) / 3;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final image in images)
                      SizedBox(
                        width: width,
                        child: _FeaturedImageCell(
                          image: image,
                          onTap: () => onOpenPost(image.postId),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _FeaturedImageCell extends StatelessWidget {
  const _FeaturedImageCell({required this.image, required this.onTap});

  final FeaturedImage image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: const Color(0xFF374151)),
              EnclavdImage(
                resolveMediaUrl(AppConfig.apiBaseUrl, galleryName: image.image),
                fit: BoxFit.cover,
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x99000000)],
                    ),
                  ),
                  child: Row(
                    children: [
                      const FaIcon(FontAwesomeIcons.solidHeart,
                          size: 9, color: Colors.white),
                      const SizedBox(width: 3),
                      Text('${image.likeCount}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10)),
                      const SizedBox(width: 8),
                      const FaIcon(FontAwesomeIcons.solidCommentDots,
                          size: 9, color: Colors.white),
                      const SizedBox(width: 3),
                      Text('${image.commentCount}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutPanel extends StatelessWidget {
  const _AboutPanel({
    super.key,
    required this.profile,
    required this.onOpenProfile,
  });

  final Profile profile;
  final ValueChanged<int> onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final location = profile.location;
    final flag = location == null ? null : _flagEmoji(location.countryCode);
    final locationPlace = location?.displayText ?? '';
    final locationVisible = profile.privacyLocation && locationPlace.isNotEmpty;
    final genderVisible = profile.privacyGender &&
        (profile.gender == 'MALE' || profile.gender == 'FEMALE');
    final birthdayVisible =
        profile.privacyBirthday && (profile.birthdate ?? '').isNotEmpty;

    return AppSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AboutItem(
                      icon: FontAwesomeIcons.calendarDay,
                      label: 'Member since',
                      child: Text(_memberSinceText(profile.dateCreated)),
                    ),
                    const SizedBox(height: 14),
                    _AboutItem(
                      icon: FontAwesomeIcons.locationDot,
                      label: 'Location',
                      child: profile.privacyLocation
                          ? (locationVisible
                              ? Text(flag == null
                                  ? locationPlace
                                  : '$flag $locationPlace')
                              : const Text('Not set'))
                          : const _RedactedBadge(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AboutItem(
                      icon: FontAwesomeIcons.venusMars,
                      label: 'Gender',
                      child: genderVisible
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FaIcon(
                                  profile.gender == 'MALE'
                                      ? FontAwesomeIcons.mars
                                      : FontAwesomeIcons.venus,
                                  size: 12,
                                  color: profile.gender == 'MALE'
                                      ? const Color(0xFF60A5FA) // blue-400
                                      : const Color(0xFFF472B6), // pink-400
                                ),
                                const SizedBox(width: 5),
                                Text(profile.gender == 'MALE'
                                    ? 'Male'
                                    : 'Female'),
                              ],
                            )
                          : const _RedactedBadge(),
                    ),
                    const SizedBox(height: 14),
                    _AboutItem(
                      icon: FontAwesomeIcons.cakeCandles,
                      label: 'Birthday',
                      child: birthdayVisible
                          ? Text(profile.birthdayText)
                          : const _RedactedBadge(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Invitations get their own full-width row: inside a half-width
          // column the inviter line used to clip.
          const SizedBox(height: 16),
          const AppDivider(),
          const SizedBox(height: 14),
          if (profile.hasInviteInfo)
            InvitationInfo(
              invitedById: profile.invitedById,
              invitedByUsername: profile.invitedByUsername,
              invitedByRank: profile.invitedByRank,
              members: profile.invitedMembers,
              onOpenProfile: onOpenProfile,
            )
          else
            _AboutItem(
              icon: FontAwesomeIcons.envelopeOpenText,
              label: 'Invited by',
              child: Text('Not set',
                  style: TextStyle(color: context.enclavd.textSecondary)),
            ),
        ],
      ),
    );
  }
}

class _AboutItem extends StatelessWidget {
  const _AboutItem({
    required this.icon,
    required this.label,
    required this.child,
  });

  final FaIconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FaIcon(icon, size: 11, color: context.enclavd.textSecondary),
            const SizedBox(width: 5),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                  color: context.enclavd.textSecondary,
                  fontSize: 10,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 3),
        DefaultTextStyle.merge(
          style: TextStyle(color: context.enclavd.textPrimary, fontSize: 13.5),
          child: child,
        ),
      ],
    );
  }
}

class _RedactedBadge extends StatelessWidget {
  const _RedactedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Text(
        '[REDACTED]',
        style: TextStyle(
            color: Colors.black,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4),
      ),
    );
  }
}

String _memberSinceText(String raw) {
  final parsed = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  if (parsed == null) return 'Not set';
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
}

/// ISO-2 country code -> regional-indicator emoji (no flag assets in the app).
String? _flagEmoji(String code) {
  if (code.length != 2) return null;
  final upper = code.toUpperCase();
  final buffer = StringBuffer();
  for (final rune in upper.runes) {
    if (rune < 0x41 || rune > 0x5A) return null;
    buffer.write(String.fromCharCode(0x1F1E6 + rune - 0x41));
  }
  return buffer.toString();
}

class _PersonalityPanel extends StatefulWidget {
  const _PersonalityPanel({
    super.key,
    required this.profile,
    required this.services,
  });

  final Profile profile;
  final AppServices services;

  @override
  State<_PersonalityPanel> createState() => _PersonalityPanelState();
}

class _PersonalityPanelState extends State<_PersonalityPanel> {
  MemberPersonality? _data;
  bool _loading = true;
  String? _error;
  bool _showCompatibility = false;

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
      final personalityFuture =
          widget.services.personality.fetchPersonality(widget.profile.id);
      final configFuture = widget.services.siteConfig
          .fetch()
          .then<SiteConfig?>((c) => c)
          .catchError((Object _) => null);
      final data = await personalityFuture;
      final config = await configFuture;
      var show = true;
      if (config != null) {
        var isAdmin = false;
        if (config.feature('synergy_bar') == 'debug') {
          try {
            isAdmin = (await widget.services.auth.me())?.isAdmin ?? false;
          } catch (_) {
            isAdmin = false;
          }
        }
        show = config.featureEnabled('synergy_bar', isAdmin: isAdmin);
      }
      if (!mounted) return;
      setState(() {
        _data = data;
        _showCompatibility = show;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.status == 404 ? null : e.message;
        _data = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load personality.';
        _loading = false;
      });
    }
  }

  Widget _card(BuildContext context, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.enclavd.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.enclavd.border),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _card(
        context,
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerBox(width: 140, height: 22, borderRadius: 999),
            SizedBox(height: 12),
            ShimmerBox(width: double.infinity, height: 90),
          ],
        ),
      );
    }
    if (_error != null) {
      return _card(
        context,
        Column(
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.enclavd.textSecondary),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final data = _data;
    if (data == null) {
      return _card(
        context,
        Text(
          'No personality result yet.',
          style: TextStyle(color: context.enclavd.textSecondary, fontSize: 13),
        ),
      );
    }

    final compat = data.compatibility;
    final viewer = data.viewer;
    // The whole comparison renders whenever the API returns a pairing; the
    // synergy_bar site flag only hides the score + bar (profile.php gates
    // just that block with $show_synergy).
    final showComparison = compat != null && viewer != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showComparison) ...[
          _PersonalityCompareCard(
            viewer: viewer,
            member: data.profile,
            compat: compat,
            memberType: data.personalityType,
            showSynergy: _showCompatibility,
          ),
          const SizedBox(height: 12),
        ],
        _PersonalityTypeInfoCard(
          type: data.personalityType,
          info: data.info,
        ),
        if (data.traits != null) ...[
          const SizedBox(height: 12),
          _TraitBalanceCard(traits: data.traits!),
        ],
      ],
    );
  }
}

/// The site's "between us" hero: both identities, the type pairing, the
/// synergy band and the two takes on strengths / challenges.
class _PersonalityCompareCard extends StatefulWidget {
  const _PersonalityCompareCard({
    required this.viewer,
    required this.member,
    required this.compat,
    required this.memberType,
    required this.showSynergy,
  });

  final PersonalityIdentity viewer;
  final PersonalityIdentity? member;
  final PersonalityCompatibility compat;
  final String memberType;
  final bool showSynergy;

  @override
  State<_PersonalityCompareCard> createState() =>
      _PersonalityCompareCardState();
}

class _PersonalityCompareCardState extends State<_PersonalityCompareCard>
    with TickerProviderStateMixin {
  /// Slow drift for the two colour "smoke" blobs and the sweep gradient.
  late final AnimationController _drift;
  late final AnimationController _entry;

  /// Gentle pulse for the "×" between the two types.
  late final AnimationController _pulse;

  /// Trace progress for the blurred circuit artwork (web: 5.2s).
  late final AnimationController _trace;

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _drift =
        AnimationController(vsync: this, duration: const Duration(seconds: 9));
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _trace = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 5200));
    _entry = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 520));
    _drift.repeat(reverse: true);
    _pulse.repeat(reverse: true);
    _trace.repeat();
    _entry.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce == _reduceMotion) return;
    _reduceMotion = reduce;
    if (reduce) {
      _drift.stop();
      _pulse.stop();
      _trace.stop();
      _drift.value = 0.35;
      _pulse.value = 0;
      _trace.value = 0.55;
      _entry.value = 1;
    } else {
      _drift.repeat(reverse: true);
      _pulse.repeat(reverse: true);
      _trace.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    _pulse.dispose();
    _trace.dispose();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewerType = widget.compat.myType;
    final theirType = widget.memberType.isNotEmpty
        ? widget.memberType
        : widget.compat.theirType;
    final viewerColor = context.enclavd.personalityColor(viewerType) ??
        context.enclavd.textSecondary;
    final memberColor = context.enclavd.personalityColor(theirType) ??
        context.enclavd.textSecondary;
    final percentage = widget.compat.percentage;
    final bandColor = percentage == null
        ? context.enclavd.textSecondary
        : percentage >= 70
            ? const Color(0xFF22C55E)
            : percentage >= 40
                ? const Color(0xFFEAB308)
                : const Color(0xFFEF4444);
    final differentTypes = viewerType != theirType;

    final strengths = <String>[
      if (widget.compat.proReason.trim().isNotEmpty)
        widget.compat.proReason.trim(),
      if (differentTypes && widget.compat.theirProReason.trim().isNotEmpty)
        widget.compat.theirProReason.trim(),
    ];
    final challenges = <String>[
      if (widget.compat.consReason.trim().isNotEmpty)
        widget.compat.consReason.trim(),
      if (differentTypes && widget.compat.theirConsReason.trim().isNotEmpty)
        widget.compat.theirConsReason.trim(),
    ];

    final slide = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entry, curve: Curves.easeOutCubic));
    final fade = CurvedAnimation(parent: _entry, curve: Curves.easeOut);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.enclavd.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.enclavd.border),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _drift,
                builder: (context, _) => _ComparisonGlow(
                  t: _drift.value,
                  viewerColor: viewerColor,
                  memberColor: memberColor,
                ),
              ),
            ),
          ),
          // The web hero's circuit board, blurred into the background.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _trace,
              builder: (context, _) => PersonalityCircuit(
                viewerColor: viewerColor,
                memberColor: memberColor,
                progress: _trace.value,
                blurSigma: 1.7,
                opacity: 0.8,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
            child: FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: slide,
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _CompareIdentity(identity: widget.viewer),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 22),
                            child: ScaleTransition(
                              scale: Tween<double>(begin: 1, end: 1.1).animate(
                                  CurvedAnimation(
                                      parent: _pulse, curve: Curves.easeInOut)),
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: viewerType,
                                      style: TextStyle(
                                          color: viewerColor,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800),
                                    ),
                                    TextSpan(
                                      text: ' × ',
                                      style: TextStyle(
                                          color: context.enclavd.textSecondary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    TextSpan(
                                      text: theirType,
                                      style: TextStyle(
                                          color: memberColor,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: _CompareIdentity(identity: widget.member),
                        ),
                      ],
                    ),
                    if (widget.showSynergy && percentage != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            'Synergy',
                            style: TextStyle(
                                color: context.enclavd.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          Text(
                            '$percentage%',
                            style: TextStyle(
                                color: bandColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: SizedBox(
                          height: 8,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ColoredBox(color: context.enclavd.cardSecondary),
                              FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: (percentage / 100).clamp(0.0, 1.0),
                                child: ColoredBox(color: bandColor),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _ReasonCard(
                            title: 'Strengths',
                            icon: FontAwesomeIcons.circlePlus,
                            color: const Color(0xFF4ADE80),
                            items: [
                              for (final reason in strengths)
                                _highlightTypes(
                                  context,
                                  reason,
                                  viewerType: viewerType,
                                  memberType: theirType,
                                  viewerColor: viewerColor,
                                  memberColor: memberColor,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ReasonCard(
                            title: 'Challenges',
                            icon: FontAwesomeIcons.circleExclamation,
                            color: const Color(0xFFF87171),
                            items: [
                              for (final reason in challenges)
                                _highlightTypes(
                                  context,
                                  reason,
                                  viewerType: viewerType,
                                  memberType: theirType,
                                  viewerColor: viewerColor,
                                  memberColor: memberColor,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Drifting two-colour smoke + a slow diagonal sweep, mirroring the site's
/// animated `personality-compare-glow`.
class _ComparisonGlow extends StatelessWidget {
  const _ComparisonGlow({
    required this.t,
    required this.viewerColor,
    required this.memberColor,
  });

  /// 0..1 animation value (eased by the sine drift below).
  final double t;
  final Color viewerColor;
  final Color memberColor;

  @override
  Widget build(BuildContext context) {
    final angle = t * 2 * 3.141592653589793;
    final glow = 0.5 + 0.5 * math.sin(angle);
    final viewerAlign = Alignment(
      -0.9 + 0.30 * math.sin(angle),
      -0.7 + 0.25 * math.sin(angle * 1.3 + 0.4),
    );
    final memberAlign = Alignment(
      0.9 - 0.30 * math.sin(angle + 0.9),
      0.7 - 0.25 * math.sin(angle * 1.1),
    );
    final sweep = (t - 0.5) * 1.6;
    // A soft light band crossing the card, so the motion reads even when
    // the two glows happen to sit still.
    final sheen = -2.6 + 5.2 * t;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: context.enclavd.card),
        Align(
          alignment: viewerAlign,
          child: _GlowBlob(color: viewerColor, pulse: glow),
        ),
        Align(
          alignment: memberAlign,
          child: _GlowBlob(color: memberColor, pulse: 1 - glow),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.1 + sweep, -1),
              end: Alignment(1.1 + sweep, 1),
              colors: [
                viewerColor.withValues(alpha: 0.10 + 0.08 * glow),
                Colors.transparent,
                memberColor.withValues(alpha: 0.18 - 0.08 * glow),
              ],
              stops: const [0, 0.5, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(sheen - 0.6, -1),
              end: Alignment(sheen + 0.6, 1),
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.06),
                Colors.transparent,
              ],
              stops: const [0, 0.5, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.pulse});

  final Color color;

  /// 0..1 breathing value so the blob swells and fades as it drifts.
  final double pulse;

  @override
  Widget build(BuildContext context) {
    final size = 320.0 + 40.0 * pulse;
    return Transform.scale(
      scale: 0.85 + 0.3 * pulse,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.30),
              color.withValues(alpha: 0.0),
            ],
            stops: const [0, 1],
          ),
        ),
      ),
    );
  }
}

/// One participant of the comparison: rank badge, avatar and name in the
/// rank's colour. The pairing is shown once, centred above the reasons.
class _CompareIdentity extends StatelessWidget {
  const _CompareIdentity({required this.identity});

  final PersonalityIdentity? identity;

  @override
  Widget build(BuildContext context) {
    final user = identity;
    final rank = user?.rank ?? 'Member';
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: RankBadge(rank: rank),
        ),
        const SizedBox(height: 6),
        EnclavdAvatar(
          size: 44,
          url: resolveMediaUrl(
            AppConfig.apiBaseUrl,
            avatarPath: user?.profilePictureUrl,
          ),
          rank: rank,
        ),
        const SizedBox(height: 6),
        if (user != null)
          Text(
            user.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.enclavd.rankName(user.rank),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

/// Strength / challenge bullets, tinted like the site's two cards.
class _ReasonCard extends StatelessWidget {
  const _ReasonCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

  final String title;
  final FaIconData icon;
  final Color color;
  final List<InlineSpan> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.enclavd.cardSecondary.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: context.enclavd.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FaIcon(icon, size: 11, color: color),
              const SizedBox(width: 5),
              Text(
                title,
                style: TextStyle(
                    color: context.enclavd.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 7),
          if (items.isEmpty)
            Text('—',
                style: TextStyle(
                    color: context.enclavd.textSecondary, fontSize: 12))
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text.rich(item),
              ),
        ],
      ),
    );
  }
}

/// The site's type card: tinted pill + headline, description and the
/// strengths / growth areas lists.
class _PersonalityTypeInfoCard extends StatelessWidget {
  const _PersonalityTypeInfoCard({required this.type, required this.info});

  final String type;
  final PersonalityInfo info;

  @override
  Widget build(BuildContext context) {
    final color =
        context.enclavd.personalityColor(type) ?? context.enclavd.textSecondary;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.enclavd.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.enclavd.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 3, color: color),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: color.withValues(alpha: 0.40)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FaIcon(FontAwesomeIcons.brain,
                                  size: 11, color: color),
                              const SizedBox(width: 6),
                              Text(
                                type,
                                style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const WidgetSpan(child: SizedBox(width: 10, height: 0)),
                      TextSpan(
                        text: 'The ${info.title}',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  info.description,
                  style: TextStyle(
                      color: context.enclavd.textSecondary,
                      fontSize: 13.5,
                      height: 1.5),
                ),
                const SizedBox(height: 14),
                Container(
                  height: 1,
                  color: context.enclavd.border.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'Strengths',
                  style: TextStyle(
                      color: context.enclavd.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                BulletList(
                  icon: FontAwesomeIcons.solidCircleCheck,
                  color: const Color(0xFF22C55E),
                  items: info.strengths,
                ),
                const SizedBox(height: 12),
                Text(
                  'Growth areas',
                  style: TextStyle(
                      color: context.enclavd.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                BulletList(
                  icon: FontAwesomeIcons.circleExclamation,
                  color: const Color(0xFFEF4444),
                  items: info.weaknesses,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The member's latest valid test as a two-column balance grid.
class _TraitBalanceCard extends StatelessWidget {
  const _TraitBalanceCard({required this.traits});

  final PersonalityTraits traits;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _TraitRow(
        left: 'Introversion',
        right: 'Extraversion',
        percent: traits.iePercentage,
        leftColor: const Color(0xFF3B82F6),
        rightColor: const Color(0xFFEF4444),
      ),
      _TraitRow(
        left: 'Sensing',
        right: 'Intuition',
        percent: traits.snPercentage,
        leftColor: const Color(0xFF22C55E),
        rightColor: const Color(0xFFA855F7),
      ),
      _TraitRow(
        left: 'Thinking',
        right: 'Feeling',
        percent: traits.tfPercentage,
        leftColor: const Color(0xFFEAB308),
        rightColor: const Color(0xFFEC4899),
      ),
      _TraitRow(
        left: 'Judging',
        right: 'Perceiving',
        percent: traits.jpPercentage,
        leftColor: const Color(0xFFF97316),
        rightColor: const Color(0xFF6366F1),
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.enclavd.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.enclavd.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trait balance',
            style: TextStyle(
                color: context.enclavd.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 520) {
                return Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) const SizedBox(height: 14),
                      rows[i],
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: rows[0]),
                      const SizedBox(width: 24),
                      Expanded(child: rows[1]),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: rows[2]),
                      const SizedBox(width: 24),
                      Expanded(child: rows[3]),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TraitRow extends StatelessWidget {
  const _TraitRow({
    required this.left,
    required this.right,
    required this.percent,
    required this.leftColor,
    required this.rightColor,
  });

  final String left;
  final String right;
  final int percent;
  final Color leftColor;
  final Color rightColor;

  @override
  Widget build(BuildContext context) {
    final clamped = percent.clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$clamped%',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: ' $left',
                    style: TextStyle(color: context.enclavd.textSecondary),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 12),
            ),
            const Spacer(),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${100 - clamped}%',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: ' $right',
                    style: TextStyle(color: context.enclavd.textSecondary),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 7,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: clamped > 0 ? clamped : 1,
                  child: ColoredBox(color: leftColor),
                ),
                Expanded(
                  flex: clamped < 100 ? 100 - clamped : 1,
                  child: ColoredBox(color: rightColor),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Renders a compatibility reason, tinting embedded 4-letter type codes
/// the way the site's personality-compare block does.
InlineSpan _highlightTypes(
  BuildContext context,
  String text, {
  required String viewerType,
  required String memberType,
  required Color viewerColor,
  required Color memberColor,
}) {
  final base = TextStyle(
    color: context.enclavd.textSecondary,
    fontSize: 12,
    height: 1.45,
  );
  final pattern = RegExp(r'\b[EI][NS][TF][JP]\b');
  final spans = <InlineSpan>[];
  var start = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > start) {
      spans.add(TextSpan(text: text.substring(start, match.start)));
    }
    final code = match.group(0)!;
    final color = code == viewerType
        ? viewerColor
        : code == memberType
            ? memberColor
            : null;
    spans.add(TextSpan(
      text: code,
      style: color == null
          ? null
          : TextStyle(color: color, fontWeight: FontWeight.w700),
    ));
    start = match.end;
  }
  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start)));
  }
  return TextSpan(style: base, children: spans);
}

/// Modal sheet listing followed hashtags; own profile can search/toggle.
class _TagsSheet extends StatefulWidget {
  const _TagsSheet({required this.profile, required this.service});

  final Profile profile;
  final ProfileService service;

  @override
  State<_TagsSheet> createState() => _TagsSheetState();
}

class _TagsSheetState extends State<_TagsSheet> {
  final Map<int, String> _followed = {};
  final Set<int> _busy = {};
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<TagSearchResult> _results = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    for (final tag in widget.profile.followedTags) {
      _followed[tag.id] = tag.tagName;
    }
    _search.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final query = _search.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    _debounce =
        Timer(const Duration(milliseconds: 350), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    setState(() => _searching = true);
    try {
      final results = await widget.service.searchTags(query);
      if (!mounted || _search.text.trim() != query) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searching = false;
      });
    }
  }

  Future<void> _toggle(int id, String name) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      final following = await widget.service.followTag(id);
      if (!mounted) return;
      setState(() {
        if (following) {
          _followed[id] = name;
        } else {
          _followed.remove(id);
        }
        _busy.remove(id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(id));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(friendlyErrorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwn = widget.profile.isOwn;
    final searching = _search.text.trim().isNotEmpty;
    final names = _followed.keys.toList()
      ..sort((a, b) => (_followed[a] ?? '')
          .toLowerCase()
          .compareTo((_followed[b] ?? '').toLowerCase()));
    return AppSheet(
      heightFactor: 0.78,
      title: isOwn
          ? 'Your followed hashtags'
          : 'Hashtags followed by ${widget.profile.username}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isOwn) ...[
            TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search hashtags',
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 12, right: 8),
                  child: FaIcon(FontAwesomeIcons.magnifyingGlass, size: 13),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 0, minHeight: 0),
                isDense: true,
                filled: true,
                fillColor: context.enclavd.cardSecondary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (_searching)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          Flexible(
            child: searching
                ? (_results.isEmpty && !_searching
                    ? Text('No hashtags found.',
                        style: TextStyle(
                            color: context.enclavd.textSecondary, fontSize: 13))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final tag = _results[index];
                          final following = _followed.containsKey(tag.id);
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('#${tag.tagName}'),
                            trailing: _busy.contains(tag.id)
                                ? const AppSpinner(size: 16)
                                : Text(
                                    following ? 'Following' : 'Follow',
                                    style: TextStyle(
                                        color: following
                                            ? context.enclavd.textSecondary
                                            : context.enclavd.link,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600),
                                  ),
                            onTap: () => _toggle(tag.id, tag.tagName),
                          );
                        },
                      ))
                : (names.isEmpty
                    ? Center(
                        child: Text(
                          isOwn
                              ? 'You are not following any hashtags yet.'
                              : 'This user is not following any hashtags yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: context.enclavd.textSecondary,
                              fontSize: 13),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final id in names)
                              _TagChip(
                                label: '#${_followed[id]}',
                                busy: _busy.contains(id),
                                onTap: isOwn
                                    ? () => _toggle(id, _followed[id]!)
                                    : () {
                                        Navigator.of(context).pop();
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => HashtagScreen(
                                                tag: _followed[id]!),
                                          ),
                                        );
                                      },
                                trailing: isOwn
                                    ? FontAwesomeIcons.xmark
                                    : FontAwesomeIcons.chevronRight,
                              ),
                          ],
                        ),
                      )),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.onTap,
    this.busy = false,
    this.trailing,
  });

  final String label;
  final VoidCallback onTap;
  final bool busy;
  final FaIconData? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.enclavd.cardSecondary,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.enclavd.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: context.enclavd.textPrimary, fontSize: 12.5)),
            if (trailing != null) ...[
              const SizedBox(width: 6),
              FaIcon(trailing!, size: 10, color: context.enclavd.textSecondary),
            ],
          ],
        ),
      ),
    );
  }
}

/// Own-profile picker: choose up to 6 gallery posts as featured.
class _FeaturedPickerSheet extends StatefulWidget {
  const _FeaturedPickerSheet({required this.profile, required this.service});

  final Profile profile;
  final ProfileService service;

  @override
  State<_FeaturedPickerSheet> createState() => _FeaturedPickerSheetState();
}

class _FeaturedPickerSheetState extends State<_FeaturedPickerSheet> {
  late final List<FeaturedImage> _images;
  late final Set<int> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final seen = <int>{};
    _images = [
      for (final image in widget.profile.galleryImages)
        if (seen.add(image.postId)) image,
    ];
    _selected = {
      for (final image in widget.profile.featuredImages) image.postId,
    };
  }

  void _toggle(int postId) {
    setState(() {
      if (_selected.contains(postId)) {
        _selected.remove(postId);
      } else if (_selected.length < 6) {
        _selected.add(postId);
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.service.setFeaturedImages(_selected.toList());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(friendlyErrorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      heightFactor: 0.86,
      title: 'Add featured',
      subtitle: 'Choose up to 6 images',
      footer: Row(
        children: [
          Text('${_selected.length} / 6 selected',
              style: TextStyle(
                  color: context.enclavd.textSecondary, fontSize: 12.5)),
          const Spacer(),
          AppButton(
            label: 'Save',
            size: AppButtonSize.small,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      child: _images.isEmpty
          ? Center(
              child: Text(
                'No gallery images yet. Post a photo first.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: context.enclavd.textSecondary, fontSize: 13),
              ),
            )
          : GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 4 / 5,
              ),
              itemCount: _images.length,
              itemBuilder: (context, index) {
                final image = _images[index];
                final selected = _selected.contains(image.postId);
                return GestureDetector(
                  onTap: () => _toggle(image.postId),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        EnclavdImage(
                          resolveMediaUrl(AppConfig.apiBaseUrl,
                              galleryName: image.image),
                          fit: BoxFit.cover,
                        ),
                        if (selected)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.25),
                              border: Border.all(
                                  color: context.enclavd.link, width: 2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        Positioned(
                          top: 5,
                          right: 5,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected
                                  ? context.enclavd.link
                                  : Colors.black.withValues(alpha: 0.35),
                              border:
                                  Border.all(color: Colors.white70, width: 1),
                            ),
                            alignment: Alignment.center,
                            child: selected
                                ? const FaIcon(
                                    FontAwesomeIcons.check,
                                    size: 9,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Own bio editor. Owns its TextEditingController so the field is not
/// disposed while the dialog route is still animating out.
class _BioDialog extends StatefulWidget {
  const _BioDialog({required this.initialBio});

  final String initialBio;

  @override
  State<_BioDialog> createState() => _BioDialogState();
}

class _BioDialogState extends State<_BioDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialBio);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit bio',
                style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            AppTextField(
              controller: _controller,
              hintText: 'Say something about yourself',
              maxLength: kMaxBioChars,
              maxLines: 4,
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.small,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Save',
                  size: AppButtonSize.small,
                  onPressed: () => Navigator.of(context).pop(_controller.text),
                ),
              ],
            ),
          ],
        ),
      ),
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
        border:
            Border.all(color: const Color(0x4DA16207)), // border-yellow-700/30
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FaIcon(FontAwesomeIcons.triangleExclamation,
              color: context.enclavd.warning, size: 14),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Warning from ',
                        style: TextStyle(
                            color: context.enclavd.warning, fontSize: 13)),
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
                          style: TextStyle(
                              color: context.enclavd.link,
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
                    style: TextStyle(
                        color: context.enclavd.textSecondary, fontSize: 13),
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
    return AppButton(
      label: label,
      icon: following ? FontAwesomeIcons.userCheck : FontAwesomeIcons.userPlus,
      variant:
          following ? AppButtonVariant.secondary : AppButtonVariant.primary,
      loading: busy,
      onPressed: busy ? null : onPressed,
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
    return AppButton(
      label: 'Message',
      icon: blocked ? FontAwesomeIcons.ban : FontAwesomeIcons.envelope,
      variant: AppButtonVariant.secondary,
      loading: busy,
      onPressed: (blocked || busy) ? null : onPressed,
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
        color: context.enclavd.card,
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
