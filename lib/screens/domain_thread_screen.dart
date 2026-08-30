import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/gestures.dart'; // TapGestureRecognizer
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/auth_service.dart'; // resolveMediaUrl
import '../api/domains_service.dart';
import '../api/feed_service.dart'; // Post
import '../api/posts_service.dart';
import '../api/social_service.dart';
import '../config/app_config.dart';
import '../main.dart'; // AppServices (edit/delete need posts + social)
import '../services/analytics_service.dart';
import '../services/sound_service.dart';
import '../theme/enclavd_theme.dart';
import '../utils/content_spans.dart'; // postContentSpans + commentContentSpans
import '../utils/db_time.dart';
import '../widgets/enclavd_avatar.dart';
import '../widgets/error_view.dart';
import '../widgets/post_card.dart'; // PostCardSkeleton, PostImage,
// rankColorFromCssClass
import '../widgets/rank_badge.dart';
import '../widgets/shimmer.dart';
import 'compose_screen.dart';
import 'hashtag_screen.dart';
import 'profile_screen.dart';

class DomainThreadScreen extends StatefulWidget {
  const DomainThreadScreen({
    super.key,
    required this.domains,
    required this.postId,
    this.breadcrumbName,
    this.social,
    this.posts,
  });

  final DomainsService domains;
  final int postId;

  /// The category the thread was opened from (breadcrumb leaf).
  final String? breadcrumbName;

  final SocialService? social;
  final PostsService? posts;

  @override
  State<DomainThreadScreen> createState() => _DomainThreadScreenState();
}

class _DomainThreadScreenState extends State<DomainThreadScreen> {
  Post? _post;
  List<DomainCategory> _breadcrumb = const [];
  List<Comment> _replies = const [];
  bool _loading = true;
  bool _repliesLoading = true;
  String? _error;
  String? _repliesError;

  // Reply pagination: one page (10) at a time, oldest-first forum order.
  bool _repliesHasMore = false;
  bool _repliesLoadingMore = false;

  int? _expandedReplyId;

  Comment? _quoting;

  final _replyController = TextEditingController();
  final _replyFocus = FocusNode();
  bool _replying = false;
  bool _composerOpen = false; // composer at the top of replies, hidden

  AppServices? _services;

  @override
  void initState() {
    super.initState();
    trackScreen('/thread');
    _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  SocialService get _social => widget.social ?? _services!.social;

  PostsService get _posts => widget.posts ?? _services!.posts;

  Future<void> _load() async {
    // Tests inject both services; skip the AppServices dance then.
    if (widget.social == null || widget.posts == null) {
      _services ??= AppServices.current ?? await AppServices.create();
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.domains.thread(widget.postId);
      if (!mounted) return;
      setState(() {
        _post = detail.post;
        _breadcrumb = detail.breadcrumb;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.status == 404
            ? 'Thread not found.'
            : (e.message.isNotEmpty ? e.message : 'Could not load the thread.');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the thread.';
      });
    }
    await _loadReplies();
  }

  Future<void> _loadReplies() async {
    final post = _post;
    if (post == null) return;
    if (mounted) {
      setState(() {
        _repliesLoading = true;
        _repliesError = null;
      });
    }
    try {
      // Page 1, oldest first (forum order); "Load more" appends the rest.
      final page = await _social.listComments(widget.postId, asc: true);
      if (!mounted) return;
      setState(() {
        _replies = page.comments;
        _repliesHasMore = page.hasMore;
        _repliesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _repliesLoading = false;
        _repliesError = 'Could not load replies.';
      });
    }
  }

  Future<void> _loadMoreReplies() async {
    if (_repliesLoadingMore || !_repliesHasMore) return;
    setState(() => _repliesLoadingMore = true);
    try {
      final page = await _social.listComments(
        widget.postId,
        asc: true,
        offset: _replies.length,
      );
      if (!mounted) return;
      setState(() {
        _replies = [..._replies, ...page.comments];
        _repliesHasMore = page.hasMore;
        _repliesLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _repliesLoadingMore = false);
      _toast('Could not load more replies.');
    }
  }

  void _quoteReply(Comment reply) {
    setState(() {
      _quoting = reply;
      _composerOpen = true;
    });
    _replyController.clear();
    _replyFocus.requestFocus();
  }

  void _toggleComposer() {
    setState(() => _composerOpen = !_composerOpen);
    if (_composerOpen) {
      // Focus after the frame so the reveal animation doesn't fight it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _replyFocus.requestFocus();
      });
    }
  }

  void _dismissQuote() => setState(() => _quoting = null);

  String _quotePrefix(Comment q) {
    final stripped = q.content.replaceAllMapped(
        RegExp(r'@([A-Za-z0-9_]+)'), (m) => m.group(1)!);
    final collapsed = stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
    final clamped = collapsed.length > 160
        ? '${collapsed.substring(0, 160)}...'
        : collapsed;
    return '@${q.username} wrote: "$clamped"\n\n';
  }

  Future<void> _sendReply() async {
    final quote = _quoting;
    final typed = _replyController.text.trim();
    final content = quote == null ? typed : '${_quotePrefix(quote)}$typed';
    if (content.isEmpty || _replying) return;
    setState(() => _replying = true);
    try {
      final (comment, newCount) =
          await _social.createComment(widget.postId, content);
      if (!mounted) return;
      setState(() {
        // Oldest-first list: a new reply APPENDS at the end.
        _replies = [..._replies, comment];
        _replying = false;
        _quoting = null;
        // Keep the OP card's count in sync.
        final post = _post;
        if (post != null) _post = _withCommentCount(post, newCount);
      });
      _replyController.clear();
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _replying = false);
      _toast(friendlyErrorText(e));
    }
  }

  Future<void> _deleteReply(Comment comment) async {
    try {
      final newCount =
          await _social.deleteComment(comment.id, widget.postId);
      if (!mounted) return;
      setState(() {
        _replies = _replies.where((c) => c.id != comment.id).toList();
        final post = _post;
        if (post != null) _post = _withCommentCount(post, newCount);
      });
    } catch (_) {
      if (!mounted) return;
      _toast('Could not delete the reply.');
    }
  }

  static Post _withCommentCount(Post post, int count) => Post(
        id: post.id,
        authorId: post.authorId,
        content: post.content,
        createdAt: post.createdAt,
        feedScore: post.feedScore,
        likeCount: post.likeCount,
        commentCount: count,
        userLiked: post.userLiked,
        warningCount: post.warningCount,
        username: post.username,
        profilePictureUrl: post.profilePictureUrl,
        personalityType: post.personalityType,
        isActive: post.isActive,
        rank: post.rank,
        image: post.image,
        isOwner: post.isOwner,
      );

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editPost(Post post) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ComposeScreen(post: post)),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _deletePost(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this thread?'),
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
      await _posts.deletePost(postId: post.id, content: post.content);
      if (!mounted) return;
      _toast('Thread deleted');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      _toast('Could not delete the thread.');
    }
  }

  String get _title {
    // The leaf category name is the AppBar title (the site's breadcrumb trail).
    if (_breadcrumb.isNotEmpty) {
      return _breadcrumb.last.name;
    }
    return widget.breadcrumbName ?? 'Thread';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_post != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  '#${_post!.id}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: EnclavdColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
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
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: const [PostCardSkeleton()],
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        _ForumPostCard(
          key: ValueKey(post.id),
          post: post,
          apiBaseUrl: AppConfig.apiBaseUrl,
          social: _social,
          onEditPost: _editPost,
          onDeletePost: _deletePost,
        ),
        const SizedBox(height: 14),
        // Reply composer at the top of the replies, hidden until the
        // "Reply" button reveals it (site: comment_list card).
        if (_composerOpen)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: EnclavdColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: EnclavdColors.border),
            ),
            child: _ReplyComposer(
              controller: _replyController,
              focusNode: _replyFocus,
              sending: _replying,
              onSend: _sendReply,
              quote: _quoting,
              onDismissQuote: _dismissQuote,
            ),
          ),
        _RepliesHeader(
            count: post.commentCount, onReply: _toggleComposer),
        if (_repliesLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(child: ShimmerBox(width: 140, height: 20)),
          )
        else if (_repliesError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_repliesError!,
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: EnclavdColors.textSecondary)),
                TextButton(
                  onPressed: _loadReplies,
                  child: const Text('Retry',
                      style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          )
        else if (_replies.isEmpty)
          // Site empty state (domain_comment_list: "No replies yet.").
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text('No replies yet - start the discussion.',
                  style: TextStyle(
                      fontSize: 13, color: EnclavdColors.textSecondary)),
            ),
          )
        else
          for (var i = 0; i < _replies.length; i++)
            _ForumReplyCard(
              key: ValueKey(_replies[i].id),
              reply: _replies[i],
              number: i + 1,
              apiBaseUrl: AppConfig.apiBaseUrl,
              onDelete: _deleteReply,
              onReply: _quoteReply,
              expanded: _replies[i].id == _expandedReplyId,
              onToggle: () => setState(() {
                _expandedReplyId = _expandedReplyId == _replies[i].id
                    ? null
                    : _replies[i].id;
              }),
            ),
        if (_repliesHasMore)
          Center(
            child: TextButton.icon(
              onPressed: _repliesLoadingMore ? null : _loadMoreReplies,
              icon: _repliesLoadingMore
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const FaIcon(FontAwesomeIcons.anglesDown,
                      size: 13, color: EnclavdColors.link),
              label: Text(
                  _repliesLoadingMore ? 'Loading...' : 'Load more replies'),
              style: TextButton.styleFrom(
                foregroundColor: EnclavdColors.link,
                textStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _ForumPostCard extends StatefulWidget {
  const _ForumPostCard({
    super.key,
    required this.post,
    required this.apiBaseUrl,
    required this.social,
    this.onEditPost,
    this.onDeletePost,
  });

  final Post post;
  final String apiBaseUrl;
  final SocialService social;

  final void Function(Post post)? onEditPost;
  final void Function(Post post)? onDeletePost;

  @override
  State<_ForumPostCard> createState() => _ForumPostCardState();
}

class _ForumPostCardState extends State<_ForumPostCard> {
  late int _likeCount;
  late bool _liked;
  bool _likeBusy = false;

  // Cached per CONTENT, not State lifetime: an edit must invalidate them.
  final List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan>? _cachedSpans;
  String? _cachedContent;

  Post get post => widget.post;

  @override
  void initState() {
    super.initState();
    _likeCount = post.likeCount;
    _liked = post.userLiked;
  }

  @override
  void didUpdateWidget(_ForumPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.content != post.content) {
      _cachedSpans = null;
      _cachedContent = null;
    }
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  List<InlineSpan> _spans() {
    final content = post.content;
    if (_cachedContent == content && _cachedSpans != null) {
      return _cachedSpans!;
    }
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final spans = postContentSpans(
      content,
      onHashtag: (tag) => _openHashtag(tag),
      onUrl: (url) => _openUrl(url),
      recognizers: _recognizers,
    );
    _cachedSpans = spans;
    _cachedContent = content;
    return spans;
  }

  void _openHashtag(String tag) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HashtagScreen(tag: tag),
    ));
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Never let a link open break the card.
    }
  }

  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    setState(() {
      _likeBusy = true;
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
    });
    if (_liked) {
      SoundService.instance.like();
    }
    try {
      final result = await widget.social.toggleLike(post.id);
      if (!mounted) return;
      setState(() {
        _liked = result.liked;
        _likeCount = result.likeCount;
        _likeBusy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = !_liked; // roll back
        _likeCount += _liked ? 1 : -1;
        _likeBusy = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('Could not update the like.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final personality = PersonalityColors.forType(post.personalityType);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EnclavdColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author header: big avatar + name/rank/time, ... for own posts.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _openProfile(context, post.authorId),
                child: EnclavdAvatar(
                  size: 46,
                  url: resolveMediaUrl(widget.apiBaseUrl,
                      avatarPath: post.profilePictureUrl),
                  borderColor: personality,
                  square: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: GestureDetector(
                            onTap: () => _openProfile(context, post.authorId),
                            child: Text(
                              post.username,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: post.isBlocked
                                    ? RankColors.forRank('Blocked')
                                    : RankColors.forRank(post.rank),
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                decoration: post.isBlocked
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor:
                                    RankColors.forRank('Blocked'),
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          relativeTime(post.createdAt),
                          style: const TextStyle(
                              color: EnclavdColors.textSecondary,
                              fontSize: 11.5),
                        ),
                        if (post.isOwner &&
                            (widget.onEditPost != null ||
                                widget.onDeletePost != null)) ...[
                          const SizedBox(width: 2),
                          PopupMenuButton<String>(
                            icon: const FaIcon(FontAwesomeIcons.ellipsis,
                                size: 15,
                                color: EnclavdColors.textSecondary),
                            padding: EdgeInsets.zero,
                            onSelected: (value) {
                              if (value == 'edit' && widget.onEditPost != null) {
                                widget.onEditPost!(post);
                              }
                              if (value == 'delete' &&
                                  widget.onDeletePost != null) {
                                widget.onDeletePost!(post);
                              }
                            },
                            itemBuilder: (context) => [
                              if (widget.onEditPost != null)
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      FaIcon(FontAwesomeIcons.pen,
                                          size: 14,
                                          color: EnclavdColors.textSecondary),
                                      SizedBox(width: 8),
                                      Text('Edit Post'),
                                    ],
                                  ),
                                ),
                              if (widget.onDeletePost != null)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      FaIcon(FontAwesomeIcons.trashCan,
                                          size: 14,
                                          color: EnclavdColors.textSecondary),
                                      SizedBox(width: 8),
                                      Text('Delete Post'),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Identity row: rank badge (personality tags are
                    // hidden on domain pages) + active warnings.
                    Row(
                      children: [
                        RankBadge(rank: post.rank),
                        if (post.warningCount > 0) ...[
                          const SizedBox(width: 6),
                          const FaIcon(FontAwesomeIcons.triangleExclamation,
                              color: EnclavdColors.warning, size: 13),
                          Text('${post.warningCount}',
                              style: const TextStyle(
                                  color: EnclavdColors.warning, fontSize: 10)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Forums don't clamp the OP's content.
          Text.rich(
            TextSpan(children: _spans()),
            style: const TextStyle(
                color: EnclavdColors.textPrimary,
                fontSize: 14.5,
                height: 1.45),
          ),
          if (post.image != null && post.image!.isNotEmpty) ...[
            const SizedBox(height: 12),
            PostImage(post: post, apiBaseUrl: widget.apiBaseUrl),
          ],
          const SizedBox(height: 14),
          const Divider(height: 1, color: EnclavdColors.divider),
          const SizedBox(height: 10),
          // Action row: like (plain toggle) + comment count.
          Row(
            children: [
              InkWell(
                onTap: _toggleLike,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      FaIcon(
                        FontAwesomeIcons.heart,
                        size: 16,
                        color: _liked
                            ? EnclavdColors.likeActive
                            : EnclavdColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$_likeCount',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _liked
                              ? EnclavdColors.likeActive
                              : EnclavdColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 18),
              const FaIcon(FontAwesomeIcons.comments,
                  size: 15, color: EnclavdColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                '${post.commentCount}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (post.lastReplyAt != null &&
                  post.lastReplyUsername != null)
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(
                          fontSize: 11, color: EnclavdColors.textSecondary),
                      children: [
                        TextSpan(
                            text:
                                'Last reply ${relativeTime(post.lastReplyAt!)} @'),
                        TextSpan(
                          text: post.lastReplyUsername!,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: post.lastReplyActive == 'false'
                                ? RankColors.forRank('Blocked')
                                : RankColors.forRank(
                                    post.lastReplyRank ?? 'Member'),
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _openProfile(BuildContext context, int authorId) {
    if (authorId <= 0) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProfileScreen(userId: authorId),
    ));
  }
}

class _RepliesHeader extends StatelessWidget {
  const _RepliesHeader({required this.count, required this.onReply});

  final int count;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      child: Row(
        children: [
          const FaIcon(FontAwesomeIcons.reply,
              size: 13, color: EnclavdColors.link),
          const SizedBox(width: 8),
          Text(
            count == 1 ? '1 Reply' : '$count Replies',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: EnclavdColors.textSecondary,
            ),
          ),
          const Spacer(),
          // Squared Reply button reveals the composer (site: comment
          // list card header).
          InkWell(
            key: const Key('replyToggle'),
            onTap: onReply,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: EnclavdColors.cardSecondary,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: EnclavdColors.border),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FaIcon(FontAwesomeIcons.reply,
                      size: 11, color: EnclavdColors.link),
                  SizedBox(width: 6),
                  Text(
                    'Reply',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: EnclavdColors.link,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForumReplyCard extends StatefulWidget {
  const _ForumReplyCard({
    super.key,
    required this.reply,
    required this.number,
    required this.apiBaseUrl,
    required this.onDelete,
    required this.onReply,
    required this.expanded,
    required this.onToggle,
  });

  final Comment reply;
  final int number;
  final String apiBaseUrl;
  final void Function(Comment) onDelete;

  final void Function(Comment) onReply;

  final bool expanded;

  final VoidCallback onToggle;

  @override
  State<_ForumReplyCard> createState() => _ForumReplyCardState();
}

class _ForumReplyCardState extends State<_ForumReplyCard> {
  final List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan>? _cachedSpans;
  String? _cachedFor; // 'full' | 'short' slice the cache holds

  static const int _readMoreLimit = 200;
  bool get _expanded => widget.expanded;

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  Comment get reply => widget.reply;

  String get _visibleContent {
    final content = reply.content;
    if (_expanded || content.length <= _readMoreLimit) return content;
    final preview = content.substring(0, _readMoreLimit);
    final lastSpace = preview.lastIndexOf(' ');
    return lastSpace > _readMoreLimit * 0.6
        ? content.substring(0, lastSpace)
        : preview;
  }

  List<InlineSpan> _spans() {
    final key = _expanded ? 'full' : 'short';
    if (_cachedFor == key && _cachedSpans != null) return _cachedSpans!;
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final text = _visibleContent;
    final spans = commentContentSpans(
      text,
      onMention: (username) => _openMention(username),
      onUrl: (url) => _openUrl(url),
      recognizers: _recognizers,
    );
    if (text.length < reply.content.length) {
      spans.add(const TextSpan(text: '...'));
    }
    _cachedSpans = spans;
    _cachedFor = key;
    return spans;
  }

  Future<void> _openMention(String username) async {
    final services = AppServices.current ?? await AppServices.create();
    if (!mounted) return;
    try {
      final profile = await services.profile.fetchProfileByUsername(username);
      if (!mounted || profile.id <= 0) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(userId: profile.id),
      ));
    } catch (_) {
      // Unknown username: plain text, no error UI.
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Never let a link open break the replies.
    }
  }

  @override
  Widget build(BuildContext context) {
    final personality = PersonalityColors.forType(reply.personalityType);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EnclavdColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openProfile(context, reply.userId),
            child: EnclavdAvatar(
              size: 40,
              url: resolveMediaUrl(widget.apiBaseUrl,
                  avatarPath: reply.profilePictureUrl),
              borderColor: personality,
              square: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: username (rank color) + rank badge + time.
                Row(
                  children: [
                    Flexible(
                      child: GestureDetector(
                        onTap: () => _openProfile(context, reply.userId),
                        child: Text(
                          reply.username,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: rankColorFromCssClass(reply.nameColor),
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    RankBadge(rank: reply.rank),
                    if (reply.hasWarnings) ...[
                      const SizedBox(width: 6),
                      const FaIcon(FontAwesomeIcons.triangleExclamation,
                          color: EnclavdColors.warning, size: 12),
                    ],
                    const Spacer(),
                    Text(
                      relativeTime(reply.createdAtUtc),
                      style: const TextStyle(
                          color: EnclavdColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(children: _spans()),
                  style: const TextStyle(
                      color: EnclavdColors.textPrimary,
                      fontSize: 14,
                      height: 1.4),
                ),
                if (reply.content.length > _readMoreLimit)
                  GestureDetector(
                    onTap: widget.onToggle,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        _expanded ? 'Show less' : 'Read more',
                        style: const TextStyle(
                          color: EnclavdColors.link,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                // Footer actions: Quote-reply / Delete + reply number.
                Row(
                  children: [
                    if (!reply.isOwner)
                      InkWell(
                        key: Key('replyQuote-${reply.id}'),
                        onTap: () => widget.onReply(reply),
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 4, vertical: 4),
                          child: Row(
                            children: [
                              FaIcon(FontAwesomeIcons.quoteLeft,
                                  size: 12, color: EnclavdColors.link),
                              SizedBox(width: 5),
                              Text(
                                'Reply',
                                style: TextStyle(
                                  color: EnclavdColors.link,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (reply.isOwner)
                      InkWell(
                        onTap: () => widget.onDelete(reply),
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 4, vertical: 4),
                          child: Row(
                            children: [
                              FaIcon(FontAwesomeIcons.trashCan,
                                  size: 12, color: EnclavdColors.likeActive),
                              SizedBox(width: 5),
                              Text(
                                'Delete',
                                style: TextStyle(
                                  color: EnclavdColors.likeActive,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      '#${widget.number}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: EnclavdColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openProfile(BuildContext context, int authorId) {
    if (authorId <= 0) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProfileScreen(userId: authorId),
    ));
  }
}

class _ReplyComposer extends StatelessWidget {
  const _ReplyComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    this.quote,
    this.onDismissQuote,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  final Comment? quote;
  final VoidCallback? onDismissQuote;

  @override
  Widget build(BuildContext context) {
    // Embedded in the replies card (parent supplies the box).
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            if (quote != null) ...[
              _QuoteBanner(quote: quote!, onDismiss: onDismissQuote),
              const SizedBox(height: 6),
            ],
            Row(
              // Stays aligned with the input's center as it grows.
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 1000,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    style: const TextStyle(
                        fontSize: 14, color: EnclavdColors.textPrimary),
                    cursorColor: EnclavdColors.link,
                    // 1000-char cap enforced silently, no counter.
                    decoration: const InputDecoration(
                      hintText: 'Reply...',
                      hintStyle: TextStyle(
                          color: EnclavdColors.textSecondary, fontSize: 14),
                      filled: true,
                      fillColor: EnclavdColors.background,
                      isDense: true,
                      counterText: '',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: EnclavdColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: EnclavdColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                        borderSide:
                            BorderSide(color: EnclavdColors.link, width: 2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: sending ? null : onSend,
                  icon: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const FaIcon(FontAwesomeIcons.paperPlane,
                          size: 18, color: EnclavdColors.link),
                  tooltip: 'Send reply',
                ),
              ],
            ),
          ],
        ),
    );
  }
}

class _QuoteBanner extends StatelessWidget {
  const _QuoteBanner({required this.quote, required this.onDismiss});

  final Comment quote;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final collapsed = quote.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: EnclavdColors.cardSecondary.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: const Border(
            left: BorderSide(color: EnclavdColors.link, width: 3)),
      ),
      child: Row(
        children: [
          const FaIcon(FontAwesomeIcons.quoteLeft,
              size: 13, color: EnclavdColors.link),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to @${quote.username}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: EnclavdColors.link,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  collapsed,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: EnclavdColors.textSecondary),
                ),
              ],
            ),
          ),
          if (onDismiss != null)
            InkWell(
              onTap: onDismiss,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: FaIcon(FontAwesomeIcons.xmark,
                    size: 14, color: EnclavdColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
