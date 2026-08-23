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

/// Post detail — a single post by id (api/v1/posts ?post_id=N) rendered
/// with the regular interactive PostCard (likes, comments, edit/delete).
///
/// The notification drawer's post taps land here instead of the browser's
/// /feed/post/<id>; the same screen is the natural host for future
/// search/permalink entry points — anything that has a post id.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.postId});

  final int postId;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  AppServices? _services;
  Post? _post;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = _services ??= await AppServices.create();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final post = await services.feed.fetchPost(widget.postId);
      if (!mounted) return;
      setState(() {
        _post = post;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 401) {
        await services.apiClient.clearSession();
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        }
        return;
      }
      setState(() {
        _loading = false;
        _error = e.status == 404
            ? 'This post does not exist.'
            : (e.message.isNotEmpty ? e.message : 'Could not load the post.');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the post.';
      });
    }
  }

  /// Edit flow: the composer is prefilled (ComposeScreen(post: …)) and pops
  /// true when saved — refetch so the card shows the updated content.
  Future<void> _editPost(Post post) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ComposeScreen(post: post)),
    );
    if (saved == true && mounted) _load();
  }

  /// Delete flow: same confirm + api/v1 delete as the feed; the post is
  /// gone afterwards, so the screen pops back to wherever it was opened.
  Future<void> _deletePost(Post post) async {
    final services = _services;
    if (services == null) return;
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
      await services.posts.deletePost(postId: post.id, content: post.content);
      if (!mounted) return;
      _toast('Post deleted');
      Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final error = _error;
    if (error != null) {
return ErrorView(message: error, onRetry: _load);
    }
    final post = _post;
    if (_loading || post == null) {
      // First load: skeleton cards like the feed (no bare spinner).
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: const [PostCardSkeleton()],
      );
    }
    final services = _services!;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        PostCard(
          key: ValueKey(post.id),
          post: post,
          apiBaseUrl: AppConfig.apiBaseUrl,
          social: services.social,
          onEditPost: _editPost,
          onDeletePost: _deletePost,
        ),
      ],
    );
  }
}
