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
  bool _banGateHandled = false;

  // Maintenance mode (site_config.php 'maintenance'): the web shows a
  // banner to allowed ranks while non-allowed ranks hit the full-page
  // lockout. The app mirrors that split on the SAME gate — banner when
  // the rank is allowed, MaintenanceScreen when it isn't — and the
  // mid-session re-check (feed load or app resume) picks up a toggle
  // made while the app was open, exactly like the ban gate above.
  MaintenanceConfig? _maintenance;
  bool _maintenanceGateHandled = false;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scrollController = ScrollController();
  final List<Post> _posts = [];
  FeedPage? _lastPage;
  bool _loading = false;
  bool _initialLoadDone = false;
  String? _error;

  // One comment section open at a time: the id of the post whose comments
  // are open, null = all closed. Opening another post's comments closes
  // this one (the site collapses the previous section on a new open).
  int? _openCommentsPostId;

  // Unread messages badge (site header: paper-plane icon + red count).
  int _unreadMessages = 0;
  Timer? _unreadTimer;

  // Unread NOTIFICATIONS badge (site header: bell icon + red count).
  int _notifUnread = 0;
  StreamSubscription<RealtimeEvent>? _realtimeSub;
  StreamSubscription<bool>? _sseStatusSub;

  // Header search (site header.php: the search button left of the bell —
  // expands into an inline search field, Enter → SearchResultsScreen).
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // New-articles dot on the Updates bottom-nav tab: true while the newest
  // article id is ahead of the id stored at the last visit (launch check
  // + resume; cleared when the Updates tab is opened).
  bool _hasNewArticles = false;

  // The shell hosts the site's nav pages in place — feed, articles and
  // domains — under the SAME header + bottom nav (the site's header
  // persists across pages). The articles/domains bodies build lazily on
  // first tab visit so their loads only happen when the user SEES the tab.
  int _navIndex = 0;
  bool _articlesTabBuilt = false;
  bool _domainsTabBuilt = false;
  bool _votesTabBuilt = false;

  // Server-driven bottom nav (GET /api/v1/site_config → nav): the site's
  // global nav rules decide which pages exist, their order and labels.
  // Empty until the fetch lands; the getters below fall back to the
  // shipped defaults, so the menu is never missing over a network blip.
  List<NavLink> _nav = const [];

  /// Fallback tabs when the server config can't be fetched — the exact
  /// set the app shipped with (labels match the old hardcoded bar).
  static const _defaultNav = [
    NavLink(url: '', text: 'Feed', public: true),
    NavLink(url: 'articles', text: 'Updates', public: true),
    NavLink(url: 'domain', text: 'Domains', public: false),
  ];

  /// Pages the native app can actually render; server nav entries for any
  /// other url are skipped (the web may list pages the app has no screen
  /// for, e.g. faq, leaderboard — they simply don't become tabs).
  static const _knownNavUrls = {'', 'articles', 'domain', 'vote'};

  /// Server nav when loaded, else the shipped defaults.
  List<NavLink> get _effectiveNav => _nav.isNotEmpty ? _nav : _defaultNav;

  /// The tabs to render right now — the site's global nav rules applied:
  /// known pages only, deduped, shown when public OR the session is live
  /// (the same rule header.php applies: guests see public pages, logged-in
  /// users see everything).
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
    // The site's header badges are SSE-driven with a 30s poll fallback —
    // the app runs the same pairing: SSE events update them instantly,
    // the poll covers a dead stream. Site parity on the gating too:
    // while the SSE stream is live the poll does NOT run (the site's
    // `if (EnclavdRealtime.connected) return;`) — event-driven only.
    _unreadTimer =
        Timer.periodic(const Duration(seconds: 30), (_) {
      if (_services?.realtime.isSseConnected ?? false) {
        // DIAGNOSTIC: with a live stream the poll must NOT run (site
        // parity). If this prints forever while NO events arrive, the
        // stream is a zombie gating the fallback — the tell for that
        // state in logcat.
        debugPrint('FS: poll skipped (sse connected)');
        return;
      }
      _loadUnread();
      _loadNotifUnread();
    });
    final realtime = _services!.realtime;
    // A fresh SSE stream means anything missed while the old one was down
    // (or was a zombie) must be reconciled from REST — the site does the
    // same on EventSource reconnect (visibilitychange → re-poll).
    _sseStatusSub = realtime.sseStatus.listen((connected) {
      if (!connected) return;
      debugPrint('FS: sse reconnected — reconciling badges');
      _loadUnread();
      _loadNotifUnread();
    });
    _realtimeSub = realtime.events.listen((event) {
      debugPrint('FS: event ${event.type} unread=${event.unreadCount}');
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
      } else if (event.type == 'notification') {
        // Badge ping = a like/comment/mention somewhere: surface it as a
        // device notification AND refresh the open drawer (the drawer's
        // own listener handles the latter; this path is for the badge).
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

  /// Header search: the magnifier (left of the bell) expands into an
  /// inline search field. Closing happens via the field's own X (white,
  /// inside the bar) or by tapping anywhere outside it — both clear the
  /// query and collapse back to the logo.
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

  /// Enter in the header search field → the results screen (api/v1/search
  /// with shimmer while loading).
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

  /// Site parity (visibilitychange): returning to the app reconciles —
  /// Android drops idle SSE sockets, so resume reconnects the stream (the
  /// service's own retry also covers it, but this makes it instant) and
  /// refreshes the badge + notification state right away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Foreground: probe the WS (ping/pong — zombie sockets reconnect NOW
    // instead of waiting out the backoff), force a FRESH SSE stream (a
    // half-open zombie reads as connected and gates the polls off forever
    // — restart-only until this), re-sync BOTH badges from REST.
    debugPrint('FS: resumed — reconnecting realtime, re-syncing badges');
    _services?.realtime.onForeground();
    _loadUnread();
    _loadNotifUnread();
    _checkNewArticles();
    // Mid-session ban gate: a ban issued while the app was backgrounded
    // lands here (web parity — check_blocked_user on every load).
    _loadMe();
  }

  /// The header avatar + drawer header need the current user (api/v1/me).
  /// Also the mid-session ban gate: the web shows check_blocked_user() on
  /// every page load, so the app must too — if the account is banned while
  /// the app is open, the ban screen replaces the whole stack on the next
  /// me() (feed load or app resume), not only at login.
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
      // Mid-session maintenance gate (web parity — header.php locks out
      // non-allowed ranks on every page load): enabled + rank not in the
      // allowed list → maintenance screen; enabled + allowed → banner.
      // A config fetch failure keeps the current banner state — the web
      // server still enforces its own pages either way.
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

  /// The bottom nav is server-driven: site_config.php $nav_links decides
  /// which pages exist, their order and labels. A fetch failure falls back
  /// to the shipped defaults — the app never loses its menu over a
  /// network blip (the same fetch also feeds the login/register gates).
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

  /// Site header parity: while accounts.personality_type is empty the
  /// header shows the yellow "incomplete profile" banner; the app shows
  /// it at the top of the feed instead. Pushes the native test — when it
  /// completes (the quiz replaces itself with the results screen and this
  /// route future resolves true) the account is refreshed so the banner
  /// disappears.
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

  /// Header NOTIFICATIONS badge count + live-path check, mirroring
  /// [_loadUnread] exactly (SSE is the instant trigger, this poll is the
  /// dead-stream fallback; the shared dedupe prevents double-notifies).
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

  /// New-articles check (site-inspired "what's new" affordance): compare the
  /// newest article id against the id stored at the last visit. First run
  /// stores the baseline silently (no dot); afterwards a moved id lights the
  /// red dot on the Updates tab until the user opens the list. Failures are
  /// non-fatal — the dot simply stays as it was.
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

  /// Opens the notification drawer (site: bell header link). The drawer
  /// marks everything read on open; refresh the badge on return.
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

  /// Feed nav button: scroll back to the top of the feed, then refresh
  /// (the site's header logo tap behaves the same way — home + re-poll).
  /// Unawaited — a tap must never block the nav bar; the scroll is
  /// best-effort when the list has no position yet.
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

  @override
  Widget build(BuildContext context) {
    final me = _me;
    // The tabs rendered right now, derived from the server nav rules
    // (order, labels, public||logged-in filter) or the shipped defaults.
    final tabs = _tabs;
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        // Site header (header.php): the wordmark, with the user menu
        // trigger (avatar) LEADING — the right side is purely the
        // notification icons (bell + messages).
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
                    hintText: 'Search posts, people, comments…',
                    hintStyle: const TextStyle(
                        color: EnclavdColors.textSecondary, fontSize: 15),
                    isDense: true,
                    // The bar look: subtle fill + rounded corners, with the
                    // close X INSIDE the field (white) instead of a red
                    // button in the header actions.
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
          // Site header: the search button (left of the bell) — expands
          // into the inline field above; Enter lands on the results
          // screen. While the field is engaged it takes the button's
          // space (the close X lives inside the bar itself).
          if (!_searching)
            IconButton(
              icon: const FaIcon(FontAwesomeIcons.magnifyingGlass,
                  size: 20, color: EnclavdColors.textSecondary),
              tooltip: 'Search',
              onPressed: _openSearch,
            ),
          // Site header: the bell notifications link (red unread badge,
          // 99+ capped) sits left of the paper-plane.
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
        ],
      ),
      // The side menu opposite the logo (site's user-menu dropdown).
      endDrawer: _services == null
          ? null
          : UserMenuDrawer(auth: _services!.auth, onSignOut: _logout),
      // Both main tabs live in the shell: the feed and the articles list
      // switch in place, keeping their scroll positions; the header, the
      // user-menu drawer and the bottom nav stay common. Children align
      // with the server-driven tab order.
      body: Column(
        children: [
          // Maintenance banner for allowed ranks (the web's info-yellow
          // box under the header) — non-allowed ranks never reach this
          // screen; the gate sends them to MaintenanceScreen instead.
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
                        ? DomainsScreen(domains: _services!.domains)
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
      // The composer FAB is feed-only (the site's New Post button lives on
      // the feed page).
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
      // Main navigation driven by the site's global nav rules
      // (site_config.php $nav_links): order, labels and the
      // public/logged-in visibility filter come from the server.
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
              // Updates = the native articles tab (the site's /articles).
              // First visit builds the body — its load advances the
              // seen-id baseline — and the red dot clears here: the user
              // has arrived.
              _articlesTabBuilt = true;
              _hasNewArticles = false;
            } else if (url == 'domain') {
              // Domains = the native forum tab (the site's /domain). Built
              // lazily on first visit like the Updates tab.
              _domainsTabBuilt = true;
            } else if (url == 'vote') {
              // Votes = the native community-voting tab (the site's /vote).
              // Built lazily on first visit like the other tabs.
              _votesTabBuilt = true;
            }
          });
          if (url == '') {
            // Feed tab = the app's home: jump to the top + refresh (the
            // site's header logo does the same — home + re-poll).
            _jumpToTopAndRefresh();
          }
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

  /// Native icon for a nav entry, keyed by its site url (the web's Font
  /// Awesome classes are web-only; the app picks its own icons per page).
  /// The Updates icon keeps its unread red dot.
  Widget _tabIcon(NavLink tab, {required bool selected}) {
    switch (tab.url) {
      case 'articles':
        return _updatesIcon(selected: selected);
      case 'domain':
        return FaIcon(FontAwesomeIcons.globe,
            color: selected ? EnclavdColors.link : EnclavdColors.textSecondary);
      default: // '' = home, plus any future known page
        return FaIcon(FontAwesomeIcons.barsStaggered,
            color: selected ? EnclavdColors.link : EnclavdColors.textSecondary);
    }
  }

  /// The Updates tab icon; a red dot (site's unread-marker color) sits on
  /// the top-right corner while new articles exist since the last visit.
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
      return ErrorView(message: _error!, onRetry: _loadFirst);
    }
    final bannerOffset = _showTestBanner ? 1 : 0;
    return ListView.builder(
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
          // Key by post id so ListView.builder never reuses a card's State
          // (like count/liked flags) for a different post after a refresh —
          // that reuse made brand-new posts show a stale "1 like".
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
    );
  }
}

/// The personality-test nudge shown at the top of the feed while
/// accounts.personality_type is empty. Modern card (site parity only in
/// intent — the header's yellow info box is intentionally NOT copied):
/// centered icon, short copy, and a full-width primary action.
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

/// Maintenance banner for allowed ranks — web parity with header.php's
/// info-yellow box (non-allowed ranks never see this screen; the gate
/// sends them to MaintenanceScreen). Compact native strip: wrench icon,
/// status line, then the reason + estimated end when provided.
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
                    ].join('  ·  '),
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
