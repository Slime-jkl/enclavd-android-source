import 'dart:async';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/articles_service.dart';
import '../api/auth_service.dart';
import '../api/feed_service.dart';
import '../api/site_config_service.dart';
import '../config/app_config.dart';
import '../main.dart';
import '../services/analytics_service.dart';
import '../services/message_notifications.dart';
import '../services/realtime_service.dart';
import '../services/social_notifications.dart';
import '../services/sound_service.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/enclavd_avatar.dart';
import '../widgets/error_view.dart';
import '../widgets/post_card.dart';
import '../widgets/shimmer.dart';
import '../widgets/user_menu_drawer.dart';
import 'compose_screen.dart';
import 'articles_screen.dart';
import 'ban_screen.dart';
import 'domains_screen.dart';
import 'login_screen.dart';
import 'maintenance_screen.dart';
import 'messages_screen.dart';
import 'notifications_screen.dart';
import 'search_results_screen.dart';
import 'test_screen.dart';
import 'votes_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  static const routeName = '/feed';

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  AppServices? _services;
  CurrentUser? _me;
  bool _banGateHandled = false;

  // Maintenance mode: banner for allowed ranks, lockout screen otherwise.
  MaintenanceConfig? _maintenance;
  bool _maintenanceGateHandled = false;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scrollController = ScrollController();
  final List<Post> _posts = [];
  FeedPage? _lastPage;
  bool _loading = false;
  bool _initialLoadDone = false;
  String? _error;

  // New-posts pill: a refresh offers newer posts, never auto-inserts them.
  int _seenMaxId = 0;
  bool _showNewPostsPill = false;
  int _newPostCount = 0;

  // One comment section open at a time; opening another closes this one.
  int? _openCommentsPostId;

  // Unread messages badge (site header: paper-plane icon + red count).
  int _unreadMessages = 0;
  Timer? _unreadTimer;

  // Unread NOTIFICATIONS badge (site header: bell icon + red count).
  int _notifUnread = 0;
  StreamSubscription<RealtimeEvent>? _realtimeSub;
  StreamSubscription<bool>? _sseStatusSub;

  // Header search: expands into an inline field, Enter -> results screen.
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // New-articles dot on the Updates bottom-nav tab: true while the newest
  // article id is ahead of the id stored at the last visit (launch check
  // + resume; cleared when the Updates tab is opened).
  bool _hasNewArticles = false;

  // Nav pages switch in place under one header + bottom nav; bodies build
  // lazily on first tab visit.
  int _navIndex = 0;
  bool _articlesTabBuilt = false;
  bool _domainsTabBuilt = false;
  bool _votesTabBuilt = false;

  // Server-driven bottom nav; defaults until the fetch lands.
  List<NavLink> _nav = const [];

  static const _defaultNav = [
    NavLink(url: '', text: 'Feed', public: true),
    NavLink(url: 'articles', text: 'Updates', public: true),
    NavLink(url: 'domain', text: 'Domains', public: false),
  ];

  static const _knownNavUrls = {'', 'articles', 'domain', 'vote'};

  List<NavLink> get _effectiveNav => _nav.isNotEmpty ? _nav : _defaultNav;

  List<NavLink> get _tabs {
    final loggedIn = _services?.apiClient.hasSession ?? true;
    final seen = <String>{};
    return [
      for (final link in _effectiveNav)
        if (_knownNavUrls.contains(link.url) &&
            seen.add(link.url) &&
            (link.public || loggedIn))
          link,
    ];
  }

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
    _loadNotifUnread();
    _loadNav();
    _checkNewArticles();
    // SSE updates badges instantly; the 30s poll covers a dead stream.
    _unreadTimer =
        Timer.periodic(const Duration(seconds: 30), (_) {
      if (_services?.realtime.isSseConnected ?? false) {
        // DIAGNOSTIC: poll must not run while the stream is live (zombie tell).
        debugPrint('FS: poll skipped (sse connected)');
        return;
      }
      _loadUnread();
      _loadNotifUnread();
    });
    final realtime = _services!.realtime;
    // Fresh stream: anything missed while the old one was down gets
    // reconciled from REST.
    _sseStatusSub = realtime.sseStatus.listen((connected) {
      if (!connected) return;
      debugPrint('FS: sse reconnected - reconciling badges');
      _loadUnread();
      _loadNotifUnread();
    });
    _realtimeSub = realtime.events.listen((event) {
      debugPrint('FS: event ${event.type} unread=${event.unreadCount}');
      if (event.type == 'message_unread') {
        // Badge ping = a new message: surface it as a device notification.
        MessageNotifications.instance?.handleUnreadPing();
        if (event.unreadCount != null &&
            mounted &&
            event.unreadCount != _unreadMessages) {
          setState(() => _unreadMessages = event.unreadCount!);
        }
      } else if (event.type == 'notification') {
        // Badge ping = a like/comment/mention: surface it as a device
        // notification (the drawer's own listener refreshes the drawer).
        SocialNotifications.instance?.handleNotificationPing();
        if (event.unreadCount != null &&
            mounted &&
            event.unreadCount != _notifUnread) {
          setState(() => _notifUnread = event.unreadCount!);
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
    _sseStatusSub?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searching = true);
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    if (!_searching) return;
    setState(() {
      _searching = false;
      _searchController.clear();
    });
  }

  void _submitSearch(String raw) {
    final query = raw.trim();
    if (query.isEmpty) return;
    final services = _services;
    if (services == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SearchResultsScreen(
          search: services.search, query: query),
    ));
  }

  /// Android drops idle SSE sockets, so resume reconnects and re-syncs badges.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Foreground: probe the WS, force a fresh SSE stream, re-sync badges.
    debugPrint('FS: resumed - reconnecting realtime, re-syncing badges');
    _services?.realtime.onForeground();
    _loadUnread();
    _loadNotifUnread();
    _checkNewArticles();
    // Mid-session ban gate (web parity).
    _loadMe();
  }

  Future<void> _loadMe() async {
    try {
      final me = await _services!.auth.me();
      if (!mounted) return;
      if (me != null && me.banned) {
        if (_banGateHandled) return;
        _banGateHandled = true;
        Navigator.of(context)
            .pushNamedAndRemoveUntil(BanScreen.routeName, (_) => false);
        return;
      }
      // Mid-session maintenance gate (web parity).
      if (me != null) {
        try {
          final cfg = await _services!.siteConfig.fetch();
          if (!mounted) return;
          if (cfg.maintenance.enabled) {
            if (!cfg.maintenance.allowedRanks.contains(me.rank)) {
              if (_maintenanceGateHandled) return;
              _maintenanceGateHandled = true;
              Navigator.of(context)
                  .pushNamedAndRemoveUntil(
                      MaintenanceScreen.routeName, (_) => false);
              return;
            }
            setState(() => _maintenance = cfg.maintenance);
          } else {
            setState(() => _maintenance = null);
          }
        } catch (_) {
          // Non-fatal: keep whatever banner state we had.
        }
      }
      setState(() => _me = me);
    } catch (_) {
      // Non-fatal: the header falls back to a placeholder avatar.
    }
  }

  Future<void> _loadNav() async {
    final services = _services;
    if (services == null) return;
    try {
      final cfg = await services.siteConfig.fetch();
      if (!mounted) return;
      setState(() => _nav = cfg.nav);
    } catch (_) {
      // Non-fatal: keep the default tabs.
    }
  }

  bool get _showTestBanner {
    final me = _me;
    return me != null &&
        (me.personalityType == null || me.personalityType!.isEmpty);
  }

  Future<void> _openPersonalityTest() async {
    final services = _services;
    if (services == null) return;
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TestScreen()),
    );
    if (completed == true && mounted) _loadMe();
  }

  Future<void> _loadUnread() async {
    final services = _services;
    if (services == null) return;
    try {
      final count = await services.messages.unreadCount();
      if (mounted && count != _unreadMessages) {
        setState(() => _unreadMessages = count);
      }
      // Every poll also evaluates the notification path (SSE is the
      // instant trigger; the poll is the guaranteed fallback).
      MessageNotifications.instance?.handleUnreadPing();
    } catch (_) {
      // Non-fatal: the badge keeps its last known value.
    }
  }

  Future<void> _loadNotifUnread() async {
    final services = _services;
    if (services == null) return;
    try {
      final count = await services.notifications.unreadCount();
      if (mounted && count != _notifUnread) {
        setState(() => _notifUnread = count);
      }
      SocialNotifications.instance?.handleNotificationPing();
    } catch (_) {
      // Non-fatal: the badge keeps its last known value.
    }
  }

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

  Future<void> _checkNewArticles() async {
    final services = _services;
    if (services == null) return;
    try {
      final latest = await services.articles.latestId();
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(ArticlesService.seenIdPrefKey);
      if (stored == null) {
        await prefs.setInt(ArticlesService.seenIdPrefKey, latest);
        return; // first run: baseline, no dot
      }
      if (!mounted || latest <= stored) return;
      if (!_hasNewArticles) {
        setState(() => _hasNewArticles = true);
      }
    } catch (_) {
      // Non-fatal: the dot just does not appear on this check.
    }
  }

  Future<void> _openNotifications() async {
    final services = _services;
    if (services == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(
          notifications: services.notifications,
          realtime: services.realtime,
        ),
      ),
    );
    if (mounted) _loadNotifUnread();
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
        // A fresh first page re-baselines what counts as seen.
        _seenMaxId = feedMaxPostId(page.posts, _seenMaxId);
        _showNewPostsPill = false;
        _newPostCount = 0;
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
    if (_loading || _lastPage == null || !_lastPage!.hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await _services!.feed
          .nextPage(_lastPage!, limit: AppConfig.feedPageSize);
      if (!mounted) return;
      setState(() {
        _posts.addAll(feedAppendPosts(_posts, page.posts));
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
    // Delta check for the pill only: newer posts are offered, never
    // auto-inserted.
    FeedPage? delta;
    try {
      delta = await services.feed
          .newerThan(_seenMaxId, limit: AppConfig.feedPageSize);
    } catch (_) {
      delta = null; // best-effort; the full reload below still runs
    }
    // The ranked first page replaces the list, exactly like a website reload.
    try {
      final page = await services.feed.firstPage(limit: AppConfig.feedPageSize);
      if (!mounted) return;
      final pillPosts = delta == null
          ? const <Post>[]
          : pillEligiblePosts(delta.posts, page.posts, _seenMaxId);
      setState(() {
        _posts
          ..clear()
          ..addAll(page.posts);
        _lastPage = page;
        _loading = false;
        _error = null;
        _initialLoadDone = true;
        _seenMaxId = feedMaxPostId(page.posts, _seenMaxId);
        _showNewPostsPill = pillPosts.isNotEmpty;
        _newPostCount = pillPosts.length;
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

  Future<void> _loadNewPosts() async {
    final services = _services;
    if (services == null) return;
    FeedPage? delta;
    try {
      delta = await services.feed
          .newerThan(_seenMaxId, limit: AppConfig.feedPageSize);
    } catch (_) {
      delta = null;
    }
    if (!mounted) return;
    if (delta == null) return; // keep the pill; the next refresh retries
    // Every current post has id <= _seenMaxId, so the delta never overlaps.
    final fresh = [
      for (final p in delta.posts)
        if (p.id > _seenMaxId) p,
    ];
    if (fresh.isEmpty) {
      setState(() {
        _showNewPostsPill = false;
        _newPostCount = 0;
      });
      return;
    }
    setState(() {
      _posts.insertAll(0, fresh);
      _seenMaxId = feedMaxPostId(fresh, _seenMaxId);
      _showNewPostsPill = false;
      _newPostCount = 0;
    });
  }

  void _jumpToTopAndRefresh() {
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    unawaited(_refresh());
  }

  Future<void> _openComposer() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ComposeScreen()),
    );
    if (created == true && mounted) {
      // The new post is score-ranked, so a first-page refetch surfaces it.
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
    // The realtime token dies with the session; close the streams first.
    _services?.realtime.dispose();
    final services = await AppServices.create();
    await services.auth.logout();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(LoginScreen.routeName, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    // Derived from the server nav rules or the shipped defaults.
    final tabs = _tabs;
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        // Site header: user menu leading, notification icons on the right.
        titleSpacing: 16,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: InkWell(
            onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
            borderRadius: BorderRadius.circular(20),
            child: me != null
                ? EnclavdAvatar(
                    size: 32,
                    url: me.avatarUrl(AppConfig.apiBaseUrl),
                    borderColor:
                        PersonalityColors.forType(me.personalityType),
                  )
                : Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: EnclavdColors.cardSecondary,
                    ),
                    child: const FaIcon(FontAwesomeIcons.user,
                        size: 15, color: EnclavdColors.textSecondary),
                  ),
          ),
        ),
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0.15, 0), end: Offset.zero)
                      .animate(animation),
              child: child,
            ),
          ),
          child: _searching
              ? TextField(
                  key: const ValueKey('header-search-field'),
                  controller: _searchController,
                  focusNode: _searchFocus,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _submitSearch,
                  onTapOutside: (_) => _closeSearch(),
                  style: const TextStyle(
                      fontSize: 15, color: EnclavdColors.textPrimary),
                  cursorColor: EnclavdColors.link,
                  decoration: InputDecoration(
                    hintText: 'Search posts, people, comments...',
                    hintStyle: const TextStyle(
                        color: EnclavdColors.textSecondary, fontSize: 15),
                    isDense: true,
                    // Bar look: subtle fill, close X inside the field.
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      onPressed: _closeSearch,
                      tooltip: 'Close search',
                      icon: const FaIcon(FontAwesomeIcons.xmark,
                          size: 16, color: Colors.white),
                    ),
                  ),
                )
              : Image.asset('assets/images/enclavd-logo-white.png',
                  height: 22, key: const ValueKey('header-logo')),
        ),
        actions: [
          // Search button expands into the inline field above.
          if (!_searching)
            IconButton(
              icon: const FaIcon(FontAwesomeIcons.magnifyingGlass,
                  size: 20, color: EnclavdColors.textSecondary),
              tooltip: 'Search',
              onPressed: _openSearch,
            ),
          // Bell notifications link (red unread badge, 99+ capped).
          if (AppConfig.enableNotifications) ...[
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const FaIcon(FontAwesomeIcons.bell,
                      size: 22, color: EnclavdColors.textSecondary),
                  tooltip: 'Notifications',
                  onPressed: _openNotifications,
                ),
                if (_notifUnread > 0)
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
                        _notifUnread > 99 ? '99+' : '$_notifUnread',
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
          // Paper-plane messages link (red unread badge, 99+ capped).
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
        ],
      ),
      // The side menu opposite the logo (site's user-menu dropdown).
      endDrawer: _services == null
          ? null
          : UserMenuDrawer(auth: _services!.auth, onSignOut: _logout),
      // Tabs switch in place, keeping scroll positions; header, drawer and
      // bottom nav stay common.
      body: Column(
        children: [
          // Maintenance banner for allowed ranks.
          if (_maintenance != null)
            _MaintenanceBanner(config: _maintenance!),
          Expanded(
            child: IndexedStack(
              index: _navIndex,
              children: [
                for (final tab in tabs)
                  switch (tab.url) {
                    '' => RefreshIndicator(
                        onRefresh: _refresh,
                        color: EnclavdColors.link,
                        child: _buildBody(),
                      ),
                    'articles' => _articlesTabBuilt && _services != null
                        ? ArticlesScreen(articles: _services!.articles)
                        : const SizedBox.shrink(),
                    'domain' => _domainsTabBuilt && _services != null
                        ? DomainsScreen(
                            domains: _services!.domains,
                            social: _services!.social,
                          )
                        : const SizedBox.shrink(),
                    'vote' => _votesTabBuilt && _services != null
                        ? VotesScreen(votes: _services!.votes)
                        : const SizedBox.shrink(),
                    _ => const SizedBox.shrink(),
                  },
              ],
            ),
          ),
        ],
      ),
      // The composer FAB is feed-only.
      floatingActionButton:
          _navIndex < tabs.length && tabs[_navIndex].url == ''
              ? FloatingActionButton(
                  onPressed: _openComposer,
                  backgroundColor: EnclavdColors.primaryButton,
                  foregroundColor: Colors.white,
                  tooltip: 'Create post',
                  child: const FaIcon(FontAwesomeIcons.pen, size: 20),
                )
              : null,
      // Bottom nav driven by the server's nav rules.
      bottomNavigationBar: NavigationBar(
        backgroundColor: EnclavdColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: EnclavdColors.primaryButton.withValues(alpha: 0.35),
        selectedIndex: _navIndex,
        onDestinationSelected: (index) {
          if (index < 0 || index >= tabs.length) return;
          final url = tabs[index].url;
          setState(() {
            _navIndex = index;
            if (url == 'articles') {
              // First visit builds the body; the red dot clears here.
              _articlesTabBuilt = true;
              _hasNewArticles = false;
            } else if (url == 'domain') {
              // Built lazily on first visit, like the Updates tab.
              _domainsTabBuilt = true;
            } else if (url == 'vote') {
              // Built lazily on first visit, like the other tabs.
              _votesTabBuilt = true;
            }
          });
          if (url == '') {
            // Feed tab = home: jump to the top + refresh.
            _jumpToTopAndRefresh();
          }
          // Tab switch = a pageview using the site's own paths.
          trackScreen(url == '' ? '/feed' : '/$url');
        },
        destinations: [
          for (final tab in tabs)
            NavigationDestination(
              icon: _tabIcon(tab, selected: false),
              selectedIcon: _tabIcon(tab, selected: true),
              label: tab.text,
            ),
        ],
      ),
    );
  }

  Widget _tabIcon(NavLink tab, {required bool selected}) {
    switch (tab.url) {
      case 'articles':
        return _updatesIcon(selected: selected);
      case 'domain':
        return FaIcon(FontAwesomeIcons.globe,
            color: selected ? EnclavdColors.link : EnclavdColors.textSecondary);
      case 'vote':
        // FA6 vote-yea glyph; the site's nav config carries no vote icon.
        return FaIcon(FontAwesomeIcons.checkToSlot,
            color: selected ? EnclavdColors.link : EnclavdColors.textSecondary);
      default: // '' = home, plus any future known page
        return FaIcon(FontAwesomeIcons.barsStaggered,
            color: selected ? EnclavdColors.link : EnclavdColors.textSecondary);
    }
  }

  Widget _updatesIcon({required bool selected}) {
    final icon = FaIcon(
      FontAwesomeIcons.newspaper,
      color: selected ? EnclavdColors.link : EnclavdColors.textSecondary,
    );
    if (!_hasNewArticles) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        const Positioned(
          top: -3,
          right: -7,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFFEF4444), // bg-red-500
              shape: BoxShape.circle,
            ),
            child: SizedBox(width: 8, height: 8),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (!_initialLoadDone && _loading) {
      // Skeleton cards while the first page loads, never a bare spinner.
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
      return ErrorView(message: _error!, onRetry: _loadFirst);
    }
    final bannerOffset = _showTestBanner ? 1 : 0;
    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: _posts.length + (_loading ? 1 : 0) + bannerOffset,
          itemBuilder: (context, index) {
            if (_showTestBanner && index == 0) {
              return _PersonalityTestBanner(onTakeTest: _openPersonalityTest);
            }
            final postIndex = index - bannerOffset;
            if (postIndex >= _posts.length) {
              // Small inline shimmer for the next page instead of a spinner.
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: ShimmerBox(width: 160, height: 22)),
              );
            }
            return PostCard(
              // Key by post id so a refresh never reuses a card's State
              // for a different post.
              key: ValueKey(_posts[postIndex].id),
              post: _posts[postIndex],
              apiBaseUrl: AppConfig.apiBaseUrl,
              social: _services!.social,
              onEditPost: _editPost,
              onDeletePost: _deletePost,
              // Only ONE comment section open at a time across the feed.
              commentsOpen: _openCommentsPostId == _posts[postIndex].id,
              onToggleComments: () => setState(() {
                _openCommentsPostId = _openCommentsPostId == _posts[postIndex].id
                    ? null
                    : _posts[postIndex].id;
              }),
            );
          },
        ),
        // Pill floats above the list; hidden state keeps its entrance animation.
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !_showNewPostsPill,
            child: AnimatedSlide(
              offset:
                  _showNewPostsPill ? Offset.zero : const Offset(0, -0.5),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: _showNewPostsPill ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: Center(
                  child: _NewPostsPill(
                    count: _newPostCount,
                    onTap: _loadNewPosts,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Highest post id seen, kept monotonic so nothing is re-offered.
int feedMaxPostId(Iterable<Post> posts, int floor) =>
    posts.fold<int>(floor, (m, p) => p.id > m ? p.id : m);

/// newly fetched page posts not already on screen.
List<Post> feedAppendPosts(List<Post> current, List<Post> incoming) {
  final known = {for (final p in current) p.id};
  return [for (final p in incoming) if (!known.contains(p.id)) p];
}

/// Delta posts genuinely new: never shown (id > [seenMaxId]) and not on screen.
List<Post> pillEligiblePosts(
  List<Post> delta,
  List<Post> onScreen,
  int seenMaxId,
) {
  final onScreenIds = {for (final p in onScreen) p.id};
  return [
    for (final p in delta)
      if (p.id > seenMaxId && !onScreenIds.contains(p.id)) p,
  ];
}

class _NewPostsPill extends StatelessWidget {
  const _NewPostsPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? '\u{2B07} 1 new post' : '\u{2B07} $count new posts';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF2563EB), // site blue-600
                Color(0xFF7C3AED), // site purple-600
              ],
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonalityTestBanner extends StatelessWidget {
  const _PersonalityTestBanner({required this.onTakeTest});

  final VoidCallback onTakeTest;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EnclavdColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: EnclavdColors.warning.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: FaIcon(FontAwesomeIcons.triangleExclamation,
                    color: EnclavdColors.warning, size: 24),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Your profile is incomplete',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Complete the personality test to unlock personalized '
            'recommendations and all restricted account features.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: EnclavdColors.textSecondary,
                fontSize: 13,
                height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onTakeTest,
            style: FilledButton.styleFrom(
              backgroundColor: EnclavdColors.primaryButton,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              textStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            child: const Text('Take personality test'),
          ),
        ],
      ),
    );
  }
}

class _MaintenanceBanner extends StatelessWidget {
  const _MaintenanceBanner({required this.config});

  final MaintenanceConfig config;

  @override
  Widget build(BuildContext context) {
    const amber = EnclavdColors.warning;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FaIcon(FontAwesomeIcons.screwdriverWrench,
              size: 14, color: amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Maintenance Mode',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                const Text(
                  'The site is currently in maintenance mode.',
                  style: TextStyle(
                      fontSize: 11.5, color: EnclavdColors.textSecondary),
                ),
                if (config.reason.isNotEmpty || config.estTime.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (config.reason.isNotEmpty) 'Reason: ${config.reason}',
                      if (config.estTime.isNotEmpty) 'Ends: ${config.estTime}',
                    ].join('  -  '),
                    style: const TextStyle(
                        fontSize: 11, color: EnclavdColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
