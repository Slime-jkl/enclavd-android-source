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
import '../utils/confirm_dialog.dart';
import '../utils/content_spans.dart'; // postContentSpans + commentContentSpans
import '../utils/db_time.dart';
import '../widgets/enclavd_avatar.dart';
import '../widgets/comment_quote_card.dart';
import '../widgets/error_view.dart';
import '../widgets/post_card.dart'; // PostCardSkeleton, PostImage,
// rankColorFromCssClass
import '../widgets/rank_badge.dart';
import '../widgets/replies_pager.dart';
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

  // Reply pagination: fixed 20-row pages over the oldest-first reply
  // list. The thread OPENS on the last (newest) page and the pager
  // walks back through older replies. Page 0 asks the server for the
  // newest page; _replyPage/_replyPages mirror the page after the fetch.
  static const int _repliesPerPage = 20;

  int _replyPage = 1;
  int _replyPages = 1;

  bool _replyBusy = false; // a page fetch is in flight

  // Owned here so the initial jump to the newest reply can scroll the
  // reply list to its end once the first page lands.
  final _repliesScroll = ScrollController();
  bool _jumpToRepliesEnd = false;

  int? _expandedReplyId;

  /// Scrolls the reply list to its newest row once the frame that
  /// changed its content has laid out. Used after landing on the last
  /// page and after posting, so the fresh reply is in view.
  void _scheduleRepliesEndJump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_jumpToRepliesEnd || !_repliesScroll.hasClients) {
        _jumpToRepliesEnd = false;
        return;
      }
      _repliesScroll.jumpTo(_repliesScroll.position.maxScrollExtent);
      _jumpToRepliesEnd = false;
    });
  }

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
    _repliesScroll.dispose();
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

  /// Initial reply load: the newest (last) page, scrolled to its end so
  /// the latest reply is in view on busy threads.
  Future<void> _loadReplies() async {
    _jumpToRepliesEnd = true;
    await _fetchReplyPage(0);
  }

  /// Fetches one grouped reply page (0 = newest) and swaps the list.
  /// The old rows stay on screen while the fetch runs; [_replyBusy]
  /// disables the pager meanwhile. A failed page fetch keeps the current
  /// rows and surfaces a toast - only the very first load falls back to
  /// the full-width error state (no rows to keep).
  Future<void> _fetchReplyPage(int page) async {
    final post = _post;
    if (post == null || _replyBusy) return;
    setState(() {
      _replyBusy = true;
      _repliesError = null;
      // Nothing on screen yet (first load / retry): show the shimmer.
      if (_replies.isEmpty) _repliesLoading = true;
    });
    try {
      final result = await _social.forumRepliesPage(
        widget.postId,
        page: page,
        perPage: _repliesPerPage,
      );
      if (!mounted) return;
      setState(() {
        _replies = result.comments;
        _replyPage = result.page;
        _replyPages = result.pages;
        _replyBusy = false;
        _repliesLoading = false;
        _post = _withCommentCount(post, result.total);
        // A freshly loaded newest page shows its tail first.
        if (result.page == result.pages) _jumpToRepliesEnd = true;
      });
      _scheduleRepliesEndJump();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _replyBusy = false;
        _repliesLoading = false;
        if (_replies.isEmpty) {
          _repliesError = 'Could not load replies.';
        }
      });
      if (_replies.isNotEmpty) _toast('Could not load replies.');
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
      final (comment, newCount) = await _social.createComment(
        widget.postId,
        content,
        parentCommentId: quote?.id,
      );
      if (!mounted) return;
      setState(() {
        // Append locally (the tree places the reply under its root on
        // the next build) instead of refetching, so the fresh reply
        // never flickers out of view mid-page; the pager refetches when
        // the user navigates. A sent reply rides at the list end.
        _replies = [..._replies, comment];
        _replying = false;
        _quoting = null;
        _jumpToRepliesEnd = true;
        // Keep the OP card's count in sync.
        final post = _post;
        if (post != null) _post = _withCommentCount(post, newCount);
      });
      _scheduleRepliesEndJump();
      _replyController.clear();
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _replying = false);
      _toast(friendlyErrorText(e));
    }
  }

  /// Drops a comment and its whole subtree from the local list (the
  /// server deletes the subtree too).
  void _dropSubtree(int id) {
    final toDrop = <int>{id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final c in _replies) {
        if (c.parentCommentId != null && toDrop.contains(c.parentCommentId) &&
            !toDrop.contains(c.id)) {
          toDrop.add(c.id);
          grew = true;
        }
      }
    }
    _replies = _replies.where((c) => !toDrop.contains(c.id)).toList();
  }

  Future<void> _deleteReply(Comment comment) async {
    try {
      final newCount =
          await _social.deleteComment(comment.id, widget.postId);
      if (!mounted) return;
      setState(() {
        _dropSubtree(comment.id);
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
      controller: _repliesScroll,
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
        else ...[
          // One pager above the first reply, one under the last. Single-
          // page threads skip both so short discussions stay clean.
          if (_replyPages > 1) ...[
            RepliesPager(
              page: _replyPage,
              pages: _replyPages,
              busy: _replyBusy,
              onPage: _fetchReplyPage,
            ),
            const SizedBox(height: 6),
          ],
          // Flat reply list. A reply that answers another one carries
          // its quoted text inline (quote card), so rows never nest.
          // Numbers stay global across pages: fixed 20-row pages, so the
          // first row of page N is at (N - 1) * 20 + 1.
          for (var i = 0; i < _replies.length; i++)
            _ForumReplyCard(
              key: ValueKey(_replies[i].id),
              reply: _replies[i],
              number: (_replyPage - 1) * _repliesPerPage + i + 1,
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
          if (_replyPages > 1)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: RepliesPager(
                page: _replyPage,
                pages: _replyPages,
                busy: _replyBusy,
                onPage: _fetchReplyPage,
              ),
            ),
        ],
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
                  size: 54,
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
                        Expanded(
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
                            style: IconButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                minimumSize: Size.zero),
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
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
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

  /// Reply number within the whole thread (continues across pages).
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

  Future<void> _confirmDelete() async {
    final confirmed = await confirmDelete(
      context,
      title: 'Delete this reply?',
      body: 'This cannot be undone. The reply and any replies '
          'under it will be permanently removed.',
    );
    if (!confirmed || !mounted) return;
    widget.onDelete(reply);
  }

  CommentQuote? _parsedQuote;
  CommentQuote? get _quote =>
      _parsedQuote ??= parseCommentQuote(reply.content);

  /// The part after any quote prefix; read-more clamps THIS, never the
  /// quoted block.
  String get _body => _quote?.body ?? reply.content;

  String get _visibleContent {
    final content = _body;
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
    if (text.length < _body.length) {
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
              size: 48,
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
                    Expanded(
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
                    const SizedBox(width: 6),
                    Text(
                      relativeTime(reply.createdAtUtc),
                      style: const TextStyle(
                          color: EnclavdColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
                // Quoted context renders as its own block; the reply's
                // own text follows (read-more clamps only the reply).
                if (_quote != null) ...[
                  CommentQuoteCard(quote: _quote!),
                  const SizedBox(height: 6),
                ],
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(children: _spans()),
                  style: const TextStyle(
                      color: EnclavdColors.textPrimary,
                      fontSize: 14,
                      height: 1.4),
                ),
                if (_body.length > _readMoreLimit)
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
                        onTap: () => _confirmDelete(),
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
