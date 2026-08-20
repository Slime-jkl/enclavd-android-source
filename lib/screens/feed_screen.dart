import 'dart:async';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/auth_service.dart';
import '../api/feed_service.dart';
import '../config/app_config.dart';
import '../main.dart';
import '../services/message_notifications.dart';
import '../services/realtime_service.dart';
import '../services/sound_service.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/enclavd_avatar.dart';
import '../widgets/post_card.dart';
import '../widgets/shimmer.dart';
import '../widgets/user_menu_drawer.dart';
import 'compose_screen.dart';
import 'login_screen.dart';
import 'messages_screen.dart';

/// Feed screen — the ranked feed via GET /api/v1/posts.
///
/// - First load: skeleton cards (shimmer) instead of a bare spinner.
/// - Infinite scroll: keyset cursor (last_score + last_id) from the previous
///   page; stop when has_more is false.
/// - Pull-to-refresh: refetch page one.
/// - Logout: top-right, via api/v1 auth logout → back to the login screen.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  static const routeName = '/feed';

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  AppServices? _services;
  CurrentUser? _me;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scrollController = ScrollController();
  final List<Post> _posts = [];
  FeedPage? _lastPage;
  bool _loading = false;
  bool _initialLoadDone = false;
  String? _error;

  // Unread messages badge (site header: paper-plane icon + red count).
  int _unreadMessages = 0;
  Timer? _unreadTimer;
  StreamSubscription<RealtimeEvent>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _init();
  }

  Future<void> _init() async {
    _services = await AppServices.create();
    if (!mounted) return;
    _loadMe();
    _loadFirst();
    _loadUnread();
    // The site's header badge is SSE-driven with a 30s poll fallback —
    // the app runs the same pairing: SSE events update it instantly,
    // the poll covers a dead stream.
    _unreadTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _loadUnread());
    final realtime = _services!.realtime;
    _realtimeSub = realtime.events.listen((event) {
      if (event.type == 'message_unread') {
        // Badge ping = a new message somewhere: surface it as a device
        // notification with a drawer reply (skipped while the messages
        // screen is open and the app is foregrounded).
        MessageNotifications.instance?.handleUnreadPing();
        if (event.unreadCount != null &&
            mounted &&
            event.unreadCount != _unreadMessages) {
          setState(() => _unreadMessages = event.unreadCount!);
        }
      }
    });
    realtime.connectSse();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unreadTimer?.cancel();
    _realtimeSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Site parity (visibilitychange): returning to the app reconciles —
  /// Android drops idle SSE sockets, so resume reconnects the stream (the
  /// service's own retry also covers it, but this makes it instant) and
  /// refreshes the badge + notification state right away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _services?.realtime.connectSse();
    _loadUnread();
  }

  /// The header avatar + drawer header need the current user (api/v1/me).
  Future<void> _loadMe() async {
    try {
      final me = await _services!.auth.me();
      if (!mounted) return;
      setState(() => _me = me);
    } catch (_) {
      // Non-fatal: the header falls back to a placeholder avatar.
    }
  }

  /// Header badge count (single COUNT query — cheap enough to poll).
  Future<void> _loadUnread() async {
    final services = _services;
    if (services == null) return;
    try {
      final count = await services.messages.unreadCount();
      if (mounted && count != _unreadMessages) {
        setState(() => _unreadMessages = count);
      }
      // Every poll also evaluates the notification path. The SSE stream is
      // the instant trigger; the poll is the guaranteed fallback (a dead
      // socket must not mean "no device notification ever"). The service
      // dedupes by newest message id, so this never double-notifies when
      // SSE is alive.
      MessageNotifications.instance?.handleUnreadPing();
    } catch (_) {
      // Non-fatal: the badge keeps its last known value.
    }
  }

  /// Opens the inbox (site: paper-plane header link). Refresh the badge
  /// on return — the thread marked things read while we were away.
  Future<void> _openMessages() async {
    final services = _services;
    if (services == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MessagesScreen(
          messages: services.messages,
          auth: services.auth,
          myUserId: _me?.id,
          realtime: services.realtime,
        ),
      ),
    );
    if (mounted) _loadUnread();
  }

  Future<void> _loadFirst() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page =
          await _services!.feed.firstPage(limit: AppConfig.feedPageSize);
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(page.posts);
        _lastPage = page;
        _loading = false;
        _initialLoadDone = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialLoadDone = true;
        _error = e.status == 401
            ? 'Session expired. Please log in again.'
            : e.message;
      });
      if (e.status == 401) {
        await _services!.apiClient.clearSession();
        if (mounted) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil(LoginScreen.routeName, (_) => false);
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialLoadDone = true;
        _error = 'Failed to load the feed.';
      });
    }
  }

  void _onScroll() {
    if (_loading || !_initialLoadDone) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadNext();
    }
  }

  Future<void> _loadNext() async {
    if (_lastPage == null || !_lastPage!.hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await _services!.feed
          .nextPage(_lastPage!, limit: AppConfig.feedPageSize);
      if (!mounted) return;
      setState(() {
        _posts.addAll(page.posts);
        _lastPage = page;
        _loading = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    final services = _services;
    if (services == null) {
      await _loadFirst();
      SoundService.instance.action();
      return;
    }
    // 1) Delta of posts newer than anything we have — surfaces new posts
    //    the ranked first page may have buried (the site's "new posts"
    //    check, posts.php ?after_id).
    final maxId = _posts.fold<int>(0, (m, p) => p.id > m ? p.id : m);
    FeedPage? delta;
    if (maxId > 0) {
      try {
        delta =
            await services.feed.newerThan(maxId, limit: AppConfig.feedPageSize);
      } catch (_) {
        delta = null; // best-effort; the full reload below still runs
      }
    }
    // 2) Full ranked first page (fresh scores/counts), merged with the
    //    delta by post id — new posts first, then the ranked list.
    try {
      final page = await services.feed.firstPage(limit: AppConfig.feedPageSize);
      if (!mounted) return;
      final seen = <int>{};
      final merged = <Post>[
        for (final p in [...?delta?.posts, ...page.posts])
          if (seen.add(p.id)) p,
      ];
      setState(() {
        _posts
          ..clear()
          ..addAll(merged);
        _lastPage = page;
        _loading = false;
        _error = null;
        _initialLoadDone = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialLoadDone = true;
        if (_posts.isEmpty) _error = e.message;
      });
      if (e.status == 401) {
        await services.apiClient.clearSession();
        if (mounted) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil(LoginScreen.routeName, (_) => false);
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialLoadDone = true;
        if (_posts.isEmpty) _error = 'Failed to load the feed.';
      });
    }
    // Site's action_sound on an explicit refresh.
    SoundService.instance.action();
  }

  Future<void> _openComposer() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ComposeScreen()),
    );
    if (created == true && mounted) {
      // The new post is score-ranked with the author boost — a first-page
      // refetch surfaces it (mirrors the site prepending the rendered card).
      _loadFirst();
    }
  }

  Future<void> _editPost(Post post) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ComposeScreen(post: post)),
    );
    if (saved == true && mounted) _loadFirst();
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
      await _services!.posts.deletePost(postId: post.id, content: post.content);
      if (!mounted) return;
      setState(() => _posts.removeWhere((p) => p.id == post.id));
      _toast('Post deleted');
    } on ApiException catch (e) {
      if (!mounted) return;
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      _toast('Could not delete the post.');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _logout() async {
    // The realtime token dies with the session — close the streams first.
    _services?.realtime.dispose();
    final services = await AppServices.create();
    await services.auth.logout();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(LoginScreen.routeName, (_) => false);
  }

  void _openSite(String path) {
    launchUrl(
      Uri.parse('${AppConfig.apiBaseUrl}$path'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        // Site header (header.php): the text-only wordmark on the left,
        // the user menu trigger (avatar + chevron) opposite it.
        titleSpacing: 16,
        title: Image.asset('assets/images/enclavd-logo-white.png', height: 22),
        actions: [
          // Site header: the paper-plane messages link (red unread badge,
          // 99+ capped) sits before the user menu trigger.
          if (AppConfig.enableChat) ...[
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const FaIcon(FontAwesomeIcons.paperPlane,
                      size: 22, color: EnclavdColors.textSecondary),
                  tooltip: 'Messages',
                  onPressed: _openMessages,
                ),
                if (_unreadMessages > 0)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      height: 16, // h-4 w-4
                      constraints: const BoxConstraints(minWidth: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444), // bg-red-500
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _unreadMessages > 99 ? '99+' : '$_unreadMessages',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10, // text-[11px] at h-4
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
              borderRadius: BorderRadius.circular(20),
              child: Row(
                children: [
                  if (me != null)
                    EnclavdAvatar(
                      size: 32,
                      url: me.avatarUrl(AppConfig.apiBaseUrl),
                      borderColor: PersonalityColors.forType(me.personalityType),
                    )
                  else
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: EnclavdColors.cardSecondary,
                      ),
                      child: const FaIcon(FontAwesomeIcons.user,
                          size: 15, color: EnclavdColors.textSecondary),
                    ),
                  const SizedBox(width: 6),
                  const FaIcon(FontAwesomeIcons.chevronDown,
                      size: 12, color: EnclavdColors.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
      // The side menu opposite the logo (site's user-menu dropdown).
      endDrawer: _services == null
          ? null
          : UserMenuDrawer(auth: _services!.auth, onSignOut: _logout),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: EnclavdColors.link,
        child: _buildBody(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openComposer,
        backgroundColor: EnclavdColors.primaryButton,
        foregroundColor: Colors.white,
        tooltip: 'Create post',
        child: const FaIcon(FontAwesomeIcons.pen, size: 20),
      ),
      // Main navigation like the site's bottom bar: Home/Updates/Domains.
      bottomNavigationBar: NavigationBar(
        backgroundColor: EnclavdColors.card,
        indicatorColor: EnclavdColors.primaryButton.withValues(alpha: 0.35),
        selectedIndex: 0, // the feed is the app's home — always selected
        onDestinationSelected: (index) {
          if (index == 1) _openSite('/articles');
          if (index == 2) _openSite('/domain');
        },
        destinations: const [
          NavigationDestination(
            icon: FaIcon(FontAwesomeIcons.barsStaggered,
                color: EnclavdColors.textSecondary),
            selectedIcon:
                FaIcon(FontAwesomeIcons.barsStaggered, color: EnclavdColors.link),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: FaIcon(FontAwesomeIcons.newspaper,
                color: EnclavdColors.textSecondary),
            selectedIcon:
                FaIcon(FontAwesomeIcons.newspaper, color: EnclavdColors.link),
            label: 'Updates',
          ),
          NavigationDestination(
            icon: FaIcon(FontAwesomeIcons.globe,
                color: EnclavdColors.textSecondary),
            selectedIcon:
                FaIcon(FontAwesomeIcons.globe, color: EnclavdColors.link),
            label: 'Domains',
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_initialLoadDone && _loading) {
      // Skeleton cards while the first page loads — never a bare spinner.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: const [
          PostCardSkeleton(),
          PostCardSkeleton(),
          PostCardSkeleton(),
        ],
      );
    }
    if (_error != null && _posts.isEmpty) {
      return _ErrorView(
        message: _error!,
        onRetry: _loadFirst,
      );
    }
    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _posts.length + (_loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _posts.length) {
          // Small inline shimmer for the next page instead of a spinner.
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: ShimmerBox(width: 160, height: 22)),
          );
        }
        return PostCard(
          // Key by post id so ListView.builder never reuses a card's State
          // (like count/liked flags) for a different post after a refresh —
          // that reuse made brand-new posts show a stale "1 like".
          key: ValueKey(_posts[index].id),
          post: _posts[index],
          apiBaseUrl: AppConfig.apiBaseUrl,
          social: _services!.social,
          onEditPost: _editPost,
          onDeletePost: _deletePost,
        );
      },
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
        FaIcon(FontAwesomeIcons.cloudArrowDown,
            color: EnclavdColors.textSecondary.withValues(alpha: 0.6),
            size: 56),
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
