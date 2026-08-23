import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/feed_service.dart';
import '../config/app_config.dart';
import '../main.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/error_view.dart';
import '../widgets/post_card.dart';
import '../widgets/shimmer.dart';
import 'compose_screen.dart';

/// Hashtag page — port of the site's feed/tag.php.
///
/// Header: `#tag` + "N posts" (textLink, like the site), then every post
/// carrying that hashtag, newest first, keyset-paginated via
/// GET /api/v1/posts?tag=… (last_created_at/last_id). PostCards are keyed by
/// post id (no stale like-state reuse — the phantom-like rule).
class HashtagScreen extends StatefulWidget {
  const HashtagScreen({super.key, required this.tag});

  /// The tag WITHOUT the leading '#' (extracted from the post body).
  final String tag;

  static const routeName = '/hashtag';

  @override
  State<HashtagScreen> createState() => _HashtagScreenState();
}

class _HashtagScreenState extends State<HashtagScreen> {
  late final AppServices _services;

  final List<Post> _posts = [];
  FeedPage? _lastPage;
  bool _loading = false;
  bool _initialLoadDone = false;
  String? _error;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFirst() async {
    _services = await AppServices.create();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _initialLoadDone = false;
      _error = null;
    });
    try {
      final page = await _services.feed.tagPosts(
        widget.tag,
        limit: AppConfig.feedPageSize,
      );
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
        await _services.apiClient.clearSession();
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialLoadDone = true;
        _error = 'Failed to load posts.';
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
    final page = _lastPage;
    if (page == null || !page.hasMore || page.lastCreatedAt == null) return;
    setState(() => _loading = true);
    try {
      final next = await _services.feed.tagPosts(
        widget.tag,
        limit: AppConfig.feedPageSize,
        lastCreatedAt: page.lastCreatedAt,
        lastId: page.lastId,
      );
      if (!mounted) return;
      setState(() {
        _posts.addAll(next.posts);
        _lastPage = next;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _refresh() => _loadFirst();

  Future<void> _editPost(Post post) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => ComposeScreen(post: post)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('#${widget.tag}')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: EnclavdColors.link,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && !_initialLoadDone) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: const [
          _TagHeaderSkeleton(),
          SizedBox(height: 8),
          PostCardSkeleton(),
          PostCardSkeleton(),
        ],
      );
    }
    if (_error != null && _posts.isEmpty) {
return ErrorView(message: _error!, onRetry: _loadFirst);
    }

    final total = _lastPage?.total;
    final itemCount =
        1 + (_posts.isEmpty ? 1 : _posts.length) + (_loading ? 1 : 0);
    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          // Tag header (tag.php): "#tag" + "N posts".
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('#${widget.tag}',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: EnclavdColors.link)),
                const SizedBox(width: 8),
                Text(
                  total == null
                      ? '${_posts.length} post${_posts.length == 1 ? '' : 's'}'
                      : '$total post${total == 1 ? '' : 's'}',
                  style: const TextStyle(
                      color: EnclavdColors.textSecondary, fontSize: 14),
                ),
              ],
            ),
          );
        }
        if (_posts.isEmpty) {
          // Empty state (tag.php: "No posts found with this hashtag.").
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                FaIcon(FontAwesomeIcons.hashtag,
                    size: 32, color: EnclavdColors.textSecondary),
                SizedBox(height: 12),
                Text('No posts found with this hashtag.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: EnclavdColors.textSecondary)),
              ],
            ),
          );
        }
        if (index >= 1 + _posts.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: ShimmerBox(width: 160, height: 22)),
          );
        }
        return PostCard(
          // Key by post id (prevents stale like-state reuse when the list
          // refreshes — the phantom-like fix).
          key: ValueKey(_posts[index - 1].id),
          post: _posts[index - 1],
          apiBaseUrl: AppConfig.apiBaseUrl,
          social: _services.social,
          onEditPost: _editPost,
          onDeletePost: _deletePost,
        );
      },
    );
  }
}

/// Header shimmer placeholder (the site's tag header skeleton).
class _TagHeaderSkeleton extends StatelessWidget {
  const _TagHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        ShimmerBox(width: 120, height: 26),
        SizedBox(width: 12),
        ShimmerBox(width: 48, height: 16),
      ],
    );
  }
}
