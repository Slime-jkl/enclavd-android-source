import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/feed_service.dart';
import '../config/app_config.dart';
import '../main.dart';
import '../services/sound_service.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/post_card.dart';
import '../widgets/shimmer.dart';
import 'compose_screen.dart';
import 'login_screen.dart';

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

class _FeedScreenState extends State<FeedScreen> {
  AppServices? _services;

  final _scrollController = ScrollController();
  final List<Post> _posts = [];
  FeedPage? _lastPage;
  bool _loading = false;
  bool _initialLoadDone = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _init();
  }

  Future<void> _init() async {
    _services = await AppServices.create();
    if (!mounted) return;
    _loadFirst();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
    final services = await AppServices.create();
    await services.auth.logout();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(LoginScreen.routeName, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Site header: logo mark + brand name (header.php).
        title: Row(
          children: [
            Image.asset('assets/images/default-logo.png', height: 26),
            const SizedBox(width: 8),
            const Text('Enclavd',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.arrowRightFromBracket,
                color: EnclavdColors.textSecondary, size: 20),
            tooltip: 'Log out',
            onPressed: _logout,
          ),
        ],
      ),
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
