import 'dart:async';
import 'dart:math' as math;

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../api/auth_service.dart';
import '../api/feed_service.dart';
import '../api/social_service.dart';
import '../api/api_client.dart';
import '../main.dart'; // AppServices.current (mention -> profile resolution)
import '../screens/domain_thread_screen.dart';
import '../screens/hashtag_screen.dart';
import '../screens/profile_screen.dart';
import '../services/gallery_saver.dart';
import '../services/sound_service.dart';
import '../theme/enclavd_theme.dart';
import '../utils/content_spans.dart';
import '../utils/db_time.dart';
import 'cached_image.dart';
import 'enclavd_avatar.dart';
import 'enclavd_image.dart';
import 'likers_sheet.dart';
import 'personality_chip.dart';
import 'shimmer.dart';

class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.apiBaseUrl,
    required this.social,
    this.onEditPost,
    this.onDeletePost,
    this.hideInlineComments = false,
    this.commentsOpen,
    this.onToggleComments,
  });

  final Post post;
  final String apiBaseUrl;
  final SocialService social;

  /// Shows an Edit/Delete menu on the viewer's own posts.
  final void Function(Post post)? onEditPost;
  final void Function(Post post)? onDeletePost;

  /// Forum-thread mode: the card's inline comments section is suppressed.
  final bool hideInlineComments;

  /// Controlled mode: the owning list decides which section is open.
  final bool? commentsOpen;
  final VoidCallback? onToggleComments;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late int _likeCount;
  late bool _liked;
  late int _commentCount;

  bool get _commentsOpen => widget.commentsOpen ?? _internalCommentsOpen;
  bool _internalCommentsOpen = false;
  bool _commentsLoading = false;
  List<Comment> _comments = const [];
  String? _commentsError;

  bool _commentsHasMore = false;
  bool _commentsLoadingMore = false;

  // Owned here so reply taps can insert "@username " and focus the composer.
  final _commentController = TextEditingController();
  final _commentFocus = FocusNode();
  bool _commentSending = false;

  // True while a like toggle is in flight (blocks double-taps).
  bool _likeBusy = false;

  // Heart-burst overlay on double-tap.
  bool _burst = false;

  // Drag-to-like tray while the heart is held.
  bool _dragActive = false;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post.likeCount;
    _liked = widget.post.userLiked;
    _commentCount = widget.post.commentCount;
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocus.dispose();
    super.dispose();
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
      final result = await widget.social.toggleLike(widget.post.id);
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
      _toast('Could not update the like. Try again.');
    }
  }

  void _likeFromGesture() {
    if (_liked || _likeBusy) return;
    _toggleLike();
    _showBurst();
  }

  void _onHeartTap() {
    if (_likeBusy) return;
    if (_liked) {
      _toggleLike();
    } else {
      _toast('Drag the heart onto the post to like it');
    }
  }

  void _beginDrag() {
    if (_liked || _likeBusy) return;
    setState(() => _dragActive = true);
  }

  void _endDrag() {
    if (mounted) setState(() => _dragActive = false);
  }

  void _showBurst() {
    setState(() => _burst = true);
    Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _burst = false);
    });
  }

  void _openLikers() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EnclavdColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => LikersSheet(
        postId: widget.post.id,
        social: widget.social,
        apiBaseUrl: widget.apiBaseUrl,
      ),
    );
  }

  Future<void> _openComments() async {
    // Domain posts route to the forum thread instead of inline comments
    // (web parity: the comment button is a link to /d/slug/id).
    if (widget.post.hasDomain) {
      await _openDomainThread();
      return;
    }
    // Forum-thread mode: the card's inline section is suppressed.
    if (widget.hideInlineComments) return;
    final toggle = widget.onToggleComments;
    if (toggle != null) {
      // Controlled mode: the owning list decides which section is open.
      final opening = !(widget.commentsOpen ?? false);
      toggle();
      if (opening) {
        setState(() {
          _commentsLoading = true;
          _commentsError = null;
        });
        await _loadComments();
      }
      return;
    }
    if (_commentsOpen) {
      setState(() => _internalCommentsOpen = false);
      return;
    }
    setState(() {
      _internalCommentsOpen = true;
      _commentsLoading = true;
      _commentsError = null;
    });
    await _loadComments();
  }

  Future<void> _openDomainThread() async {
    AppServices services;
    try {
      services = AppServices.current ?? await AppServices.create();
    } catch (_) {
      return; // no container (tests/edge): never crash a card tap
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DomainThreadScreen(
          domains: services.domains,
          postId: widget.post.id,
          breadcrumbName: widget.post.domainName,
          social: widget.social,
        ),
      ),
    );
  }

  Future<void> _loadComments() async {
    try {
      final page =
          await widget.social.listComments(widget.post.id); // page 1, DESC
      if (!mounted) return;
      setState(() {
        _comments = page.comments;
        _commentCount = page.total;
        _commentsHasMore = page.hasMore;
        _commentsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _commentsLoading = false;
        _commentsError = 'Could not load comments.';
      });
    }
  }

  Future<void> _loadMoreComments() async {
    if (_commentsLoadingMore || !_commentsHasMore) return;
    setState(() => _commentsLoadingMore = true);
    try {
      final page = await widget.social.listComments(
        widget.post.id,
        offset: _comments.length,
      );
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, ...page.comments];
        _commentCount = page.total;
        _commentsHasMore = page.hasMore;
        _commentsLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _commentsLoadingMore = false);
      _toast('Could not load more comments.');
    }
  }

  void _replyToComment(Comment comment) {
    final current = _commentController.text.trim();
    final mention = '@${comment.username} ';
    _commentController.text = current.isEmpty
        ? mention
        : '$current $mention';
    _commentController.selection = TextSelection.collapsed(
        offset: _commentController.text.length);
    _commentFocus.requestFocus();
  }

  Future<void> _sendComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty || _commentSending) return;
    setState(() {
      _commentSending = true;
      // Optimistic: bump now, server total corrects on success.
      _commentCount += 1;
    });
    try {
      final (comment, newCount) =
          await widget.social.createComment(widget.post.id, content);
      if (!mounted) return;
      setState(() {
        _comments = [comment, ..._comments]; // newest first (server order)
        _commentCount = newCount;
        _commentSending = false;
      });
      _commentController.clear();
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _commentSending = false;
        _commentCount -= 1; // roll back the optimistic bump
      });
      _toast(friendlyErrorText(e));
    }
  }

  Future<void> _deleteComment(Comment comment) async {
    setState(() {
      _comments = _comments.where((c) => c.id != comment.id).toList();
      _commentCount -= 1; // optimistic; server total corrects on success
    });
    try {
      final newCount =
          await widget.social.deleteComment(comment.id, widget.post.id);
      if (!mounted) return;
      setState(() => _commentCount = newCount);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _commentCount += 1; // roll back
        // Restore the comment (newest-first by id, like the server order).
        _comments = [..._comments, comment]
          ..sort((a, b) => b.id.compareTo(a.id));
      });
      _toast('Could not delete the comment.');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        // Double-tap likes (never unlikes).
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _likeFromGesture,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AuthorRow(
                    post: widget.post,
                    apiBaseUrl: widget.apiBaseUrl,
                    onEdit: widget.onEditPost,
                    onDelete: widget.onDeletePost,
                  ),
                  if (widget.post.hasDomain &&
                      (widget.post.domainName?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 8),
                    _DomainPromotionBanner(
                      post: widget.post,
                      onTap: _openDomainThread,
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Drop target is the content area (text + image) only.
                  DragTarget<String>(
                    onAcceptWithDetails: (_) => _likeFromGesture(),
                    builder: (context, candidates, rejected) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PostContent(post: widget.post),
                        // First YouTube link in the post renders between
                        // the text and the image.
                        if (extractYouTubeId(widget.post.content) case final id?)
                          _YouTubeEmbed(
                              videoId: id, apiBaseUrl: widget.apiBaseUrl),
                        if (widget.post.image != null &&
                            widget.post.image!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          PostImage(
                              post: widget.post, apiBaseUrl: widget.apiBaseUrl),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 8),
                  _ActionRow(
                    liked: _liked,
                    likeCount: _likeCount,
                    commentCount: _commentCount,
                    onLike: _onHeartTap,
                    onLikers: _openLikers,
                    onComments: _openComments,
                    onDragStarted: _beginDrag,
                    onDragEnded: _endDrag,
                  ),
                  if (widget.post.hasDomain) ...[
                    const Divider(height: 12),
                    Center(
                      child: InkWell(
                        onTap: _openDomainThread,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const FaIcon(
                                FontAwesomeIcons.arrowUpRightFromSquare,
                                color: EnclavdColors.link,
                                size: 13,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _commentCount > 0
                                    ? 'View in Domains ($_commentCount '
                                        '${_commentCount == 1 ? 'reply' : 'replies'})'
                                    : 'View in Domains',
                                style: const TextStyle(
                                  color: EnclavdColors.link,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_commentsOpen) ...[
                    const SizedBox(height: 8),
                    _CommentsSection(
                      comments: _comments,
                      loading: _commentsLoading,
                      error: _commentsError,
                      hasMore: _commentsHasMore,
                      loadingMore: _commentsLoadingMore,
                      sending: _commentSending,
                      controller: _commentController,
                      focusNode: _commentFocus,
                      onSend: _sendComment,
                      onLoadMore: _loadMoreComments,
                      onDelete: _deleteComment,
                      onReply: _replyToComment,
                      apiBaseUrl: widget.apiBaseUrl,
                    ),
                  ],
                ],
              ),
            ),
            // Darken the card + drop hint while the heart is held.
            if (_dragActive)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.6),
                    alignment: Alignment.center,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                      child: CustomPaint(
                        painter: _DashedBorderPainter(
                          color: const Color(0xFFF87171).withValues(alpha: 0.9),
                          radius: BorderRadius.circular(12),
                          dashLength: 6,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF0F172A).withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Text(
                              'Drag the heart here to like',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFFECACA), // red-200
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Heart burst on double-tap (site's showHeartAnimation).
            if (_burst)
              const Positioned.fill(
                child: IgnorePointer(
                  child: Center(child: _HeartBurst()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeartBurst extends StatelessWidget {
  const _HeartBurst();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 4),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      builder: (context, scale, child) {
        final opacity = (1 - (scale - 1) / 3).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: const FaIcon(FontAwesomeIcons.heart,
          color: Color(0xFFF87171), size: 64), // text-red-500 text-6xl
    );
  }
}

class _AuthorRow extends StatelessWidget {
  const _AuthorRow({
    required this.post,
    required this.apiBaseUrl,
    this.onEdit,
    this.onDelete,
  });

  final Post post;
  final String apiBaseUrl;
  final void Function(Post post)? onEdit;
  final void Function(Post post)? onDelete;

  @override
  Widget build(BuildContext context) {
    final personality = PersonalityColors.forType(post.personalityType);
    return Row(
      children: [
        GestureDetector(
          onTap: () => _openProfile(context, post.authorId),
          child: EnclavdAvatar(
            size: 35,
            url:
                resolveMediaUrl(apiBaseUrl, avatarPath: post.profilePictureUrl),
            borderColor: personality,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => _openProfile(context, post.authorId),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        post.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: post.isBlocked
                              ? RankColors.forRank('Blocked')
                              : RankColors.forRank(post.rank),
                          fontWeight: FontWeight.w600,
                          decoration: post.isBlocked
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: RankColors.forRank('Blocked'),
                        ),
                      ),
                    ),
                    if (post.personalityType != null) ...[
                      const SizedBox(width: 6),
                      PersonalityChip(type: post.personalityType!),
                    ],
                    if (post.warningCount > 0) ...[
                      const SizedBox(width: 6),
                      const FaIcon(FontAwesomeIcons.triangleExclamation,
                          color: EnclavdColors.warning, size: 14),
                      Text('${post.warningCount}',
                          style: const TextStyle(
                              color: EnclavdColors.warning, fontSize: 10)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          relativeTime(post.createdAt),
          style:
              const TextStyle(color: EnclavdColors.textSecondary, fontSize: 12),
        ),
        // Own-post Edit/Delete menu (site's post_menu.php).
        if (post.isOwner && (onEdit != null || onDelete != null))
          PopupMenuButton<String>(
            icon: const FaIcon(FontAwesomeIcons.ellipsis,
                size: 16, color: EnclavdColors.textSecondary),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: Size.zero),
            onSelected: (value) {
              if (value == 'edit' && onEdit != null) onEdit!(post);
              if (value == 'delete' && onDelete != null) onDelete!(post);
            },
            itemBuilder: (context) => [
              if (onEdit != null)
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      FaIcon(FontAwesomeIcons.pen,
                          size: 14, color: EnclavdColors.textSecondary),
                      SizedBox(width: 8),
                      Text('Edit Post'),
                    ],
                  ),
                ),
              if (onDelete != null)
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      FaIcon(FontAwesomeIcons.trashCan,
                          size: 14, color: EnclavdColors.textSecondary),
                      SizedBox(width: 8),
                      Text('Delete Post'),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }

  void _openProfile(BuildContext context, int authorId) {
    if (authorId <= 0) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ProfileScreen(userId: authorId)),
    );
  }
}

class _PostContent extends StatefulWidget {
  const _PostContent({required this.post});

  final Post post;

  @override
  State<_PostContent> createState() => _PostContentState();
}

class _PostContentState extends State<_PostContent> {
  bool _expanded = false;

  // Owned here so they get disposed; postContentSpans hands them over.
  final List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan>? _cachedSpans;

  @override
  void didUpdateWidget(covariant _PostContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Post edits keep this State alive (cards are keyed by id); drop the
    // cached spans or the old text keeps rendering.
    if (oldWidget.post.content != widget.post.content) {
      _cachedSpans = null;
      _expanded = false;
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
    final cached = _cachedSpans;
    if (cached != null) return cached;
    final spans = postContentSpans(
      widget.post.content,
      onHashtag: (tag) => _openHashtag(tag),
      onUrl: (url) => _openUrl(url),
      recognizers: _recognizers,
    );
    _cachedSpans = spans;
    return spans;
  }

  void _openHashtag(String tag) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => HashtagScreen(tag: tag)),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Never let a link open break the feed.
    }
  }

  bool get _needsOverflow {
    final content = widget.post.content;
    final charCount = content.trim().length;
    final newlineCount = '\n'.allMatches(content).length;
    return charCount > 250 || (charCount + newlineCount * 75) > 300;
  }

  @override
  Widget build(BuildContext context) {
    final needs = _needsOverflow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(children: _spans()),
          maxLines: needs && !_expanded ? 4 : null,
          overflow: needs && !_expanded ? TextOverflow.ellipsis : null,
          style: const TextStyle(
            fontSize: 15,
            height: 1.15,
            color: EnclavdColors.textPrimary,
          ),
        ),
        if (needs)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 4),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(_expanded ? 'Show less' : 'Show more'),
          ),
      ],
    );
  }
}

/// Post image, capped at half the viewport height; tap -> fullscreen viewer.
class PostImage extends StatefulWidget {
  const PostImage({
    super.key,
    required this.post,
    required this.apiBaseUrl,
  });

  final Post post;
  final String apiBaseUrl;

  @override
  State<PostImage> createState() => PostImageState();
}

class PostImageState extends State<PostImage> {
  double? _aspect;
  ImageStream? _stream;
  bool _probeStarted = false;

  String get _url =>
      resolveMediaUrl(widget.apiBaseUrl, galleryName: widget.post.image);

  late final ImageStreamListener _probeListener = ImageStreamListener(
    (info, _) {
      // Probe decode was only for the aspect ratio; detach immediately.
      _stream?.removeListener(_probeListener);
      _stream = null;
      if (!mounted || _aspect != null) return;
      setState(() => _aspect = info.image.width / info.image.height);
    },
    // Probe failures fall through to EnclavdImage's errorBuilder.
    onError: (_, __) {
      _stream?.removeListener(_probeListener);
      _stream = null;
    },
  );

  @override
  void dispose() {
    _stream?.removeListener(_probeListener);
    super.dispose();
  }

  void _ensureProbe() {
    if (_probeStarted) return;
    _probeStarted = true;
    final provider = ResizeImage.resizeIfNeeded(
      128,
      null,
      CachedNetworkImageProvider(_url),
    );
    final stream = provider.resolve(ImageConfiguration.empty);
    _stream = stream;
    stream.addListener(_probeListener);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: LayoutBuilder(builder: (context, constraints) {
        final contentWidth = constraints.maxWidth;
        // Cap at 50vh like the site's max-h-[50vh].
        final maxHeight = MediaQuery.sizeOf(context).height * 0.5;
        _ensureProbe();
        final height = _aspect == null
            ? 180.0 // probing: shimmer at a sane default
            : math.min(contentWidth / _aspect!, maxHeight);
        return GestureDetector(
          onTap: () => _viewFullImage(context, _url),
          // Long-press saves to the gallery; tap opens the fullscreen viewer.
          onLongPress: () => _showSaveSheet(context, _url),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              EnclavdImage(
                _url,
                width: contentWidth,
                height: height,
                fit: BoxFit.contain,
                errorAsset: 'assets/images/no-image.jpg',
                borderRadius: BorderRadius.circular(8),
              ),
              // No hover on touch, so keep an always-on expand hint.
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const FaIcon(FontAwesomeIcons.expand,
                      size: 13, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  void _showSaveSheet(BuildContext context, String url) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: EnclavdColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ListTile(
          leading: const FaIcon(FontAwesomeIcons.download,
              color: EnclavdColors.link, size: 18),
          title: const Text('Save image to device',
              style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Saves to the Enclavd folder in your gallery',
              style: TextStyle(
                  color: EnclavdColors.textSecondary, fontSize: 12.5)),
          onTap: () {
            Navigator.of(sheetContext).pop();
            _saveToDevice(context, url);
          },
        ),
      ),
    );
  }

  Future<void> _saveToDevice(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await GallerySaver().saveImage(url);
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
    ));
  }

  void _viewFullImage(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(dialogContext).pop(),
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Center(
                    child: Image(
                      image: CachedNetworkImageProvider(url),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 24,
              right: 24,
              child: IconButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const FaIcon(FontAwesomeIcons.xmark,
                    color: Colors.white, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DomainPromotionBanner extends StatelessWidget {
  const _DomainPromotionBanner({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final promoter =
        (post.promoterUsername?.isNotEmpty ?? false) ? post.promoterUsername! : 'System';
    final domainName = post.domainName ?? '';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          // Web parity: bg-blue-950/25 + border-blue-800/30.
          color: const Color(0xFF172554).withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF1E40AF).withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: FaIcon(FontAwesomeIcons.bullhorn,
                  color: EnclavdColors.link, size: 13),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                    color: EnclavdColors.textSecondary,
                    fontSize: 13,
                    height: 1.3,
                  ),
                  children: [
                    TextSpan(
                      text: '@$promoter ',
                      style: const TextStyle(
                        color: EnclavdColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(text: 'charted this to '),
                    if (domainName.isNotEmpty)
                      TextSpan(
                        text: domainName,
                        style: const TextStyle(
                          color: EnclavdColors.link,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const TextSpan(text: ' Domain.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.liked,
    required this.likeCount,
    required this.commentCount,
    required this.onLike,
    required this.onLikers,
    required this.onComments,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final bool liked;
  final int likeCount;
  final int commentCount;
  final VoidCallback onLike;
  final VoidCallback onLikers;
  final VoidCallback onComments;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              // Hold to drag onto the content to like; a plain tap never likes.
              LongPressDraggable<String>(
                data: 'like',
                feedback: const FaIcon(FontAwesomeIcons.heart,
                    color: EnclavdColors.likeActive, size: 40),
                childWhenDragging: Opacity(
                  opacity: 0.3,
                  child: FaIcon(
                    FontAwesomeIcons.heart,
                    key: const ValueKey('like-heart'),
                    color: liked
                        ? EnclavdColors.likeActive
                        : EnclavdColors.textSecondary,
                    size: 20,
                  ),
                ),
                onDragStarted: onDragStarted,
                onDragEnd: (_) => onDragEnded(),
                onDraggableCanceled: (_, __) => onDragEnded(),
                child: InkWell(
                  onTap: onLike,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: FaIcon(
                      FontAwesomeIcons.heart,
                      key: const ValueKey('like-heart'),
                      color: liked
                          ? EnclavdColors.likeActive
                          : EnclavdColors.textSecondary,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Tappable -> the "Liked by" list.
              InkWell(
                onTap: onLikers,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Text('$likeCount',
                      style: TextStyle(
                          color: liked
                              ? EnclavdColors.likeActive
                              : EnclavdColors.textSecondary)),
                ),
              ),
              const SizedBox(width: 20),
              InkWell(
                onTap: onComments,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      FaIcon(
                        commentCount > 0
                            ? FontAwesomeIcons.comments
                            : FontAwesomeIcons.comment,
                        color: EnclavdColors.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text('$commentCount',
                          style:
                              const TextStyle(color: EnclavdColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // "Liked by N" opposite the buttons; count also opens the likers sheet.
        if (likeCount > 0)
          InkWell(
            onTap: onLikers,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'Liked by $likeCount',
                style: const TextStyle(
                  color: EnclavdColors.link, // textLink: text-blue-400
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// First YouTube video id in the text (watch?v=, shorts/, embed/, youtu.be).
String? extractYouTubeId(String text) {
  final m = RegExp(
    r'(?:https?://)?(?:www\.)?'
    r'(?:youtube\.com/(?:watch\?v=|shorts/|embed/)|youtu\.be/)'
    r'([A-Za-z0-9_-]{11})',
    caseSensitive: false,
  ).firstMatch(text);
  return m?.group(1);
}

class _YouTubeEmbed extends StatefulWidget {
  const _YouTubeEmbed({required this.videoId, required this.apiBaseUrl});

  final String videoId;

  final String apiBaseUrl;

  @override
  State<_YouTubeEmbed> createState() => _YouTubeEmbedState();
}

class _YouTubeEmbedState extends State<_YouTubeEmbed> {
  bool _playing = false;
  WebViewController? _controller;

  WebViewController _ensureController() {
    final existing = _controller;
    if (existing != null) return existing;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F172A))
      ..setNavigationDelegate(
          NavigationDelegate(onNavigationRequest: _onNavigationRequest));
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      // Default blocks autoplay=1; flip so the tap starts the video.
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    controller.loadRequest(
      Uri.parse('https://www.youtube-nocookie.com/embed/${widget.videoId}'
          '?playsinline=1&rel=0&autoplay=1'),
      headers: {
        'Referer': widget.apiBaseUrl,
        'Referrer-Policy': 'strict-origin-when-cross-origin',
      },
    );
    _controller = controller;
    return controller;
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final url = request.url.toString();
    if (url.contains('youtube-nocookie.com/embed/') ||
        url.contains('youtube.com/embed/')) {
      return NavigationDecision.navigate;
    }
    if (url.contains('youtube.com') || url.contains('youtu.be')) {
      launchUrl(Uri.parse(request.url.toString()),
          mode: LaunchMode.externalApplication);
    }
    return NavigationDecision.prevent;
  }

  void _play() {
    _ensureController();
    setState(() => _playing = true);
  }

  void _collapse() => setState(() => _playing = false);

  Future<void> _openExternal() async {
    try {
      await launchUrl(
          Uri.parse('https://www.youtube.com/watch?v=${widget.videoId}'),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      // Never let a launcher failure break the feed.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0x66000000), // bg-black/40
          borderRadius: BorderRadius.circular(8), // rounded-lg
          border: Border.all(color: const Color(0x99374151)), // gray-700/60
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: 16 / 9, // the site's 56.25% padding-top
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Player stays mounted when collapsed; the thumbnail covers it.
              if (_controller != null) WebViewWidget(controller: _controller!),
              if (!_playing)
                // Resting state: thumbnail + scrim + red play button.
                GestureDetector(
                  onTap: _play,
                  child: Container(
                    color: EnclavdColors.card,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // hqdefault always exists; maxresdefault does not.
                        EnclavdImage(
                          'https://img.youtube.com/vi/${widget.videoId}/hqdefault.jpg',
                          fit: BoxFit.cover,
                          errorAsset: 'assets/images/no-image.jpg',
                        ),
                        // Scrim so the red button pops on any thumbnail.
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.25),
                        ),
                        const Center(
                          child: _YouTubePlayButton(
                            key: Key('youtube-play-button'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_playing) ...[
                // Overlay controls: open in YouTube, or collapse.
                Positioned(
                  top: 6,
                  right: 6,
                  child: Row(
                    children: [
                      _PlayerOverlayButton(
                        icon: FontAwesomeIcons.arrowUpRightFromSquare,
                        tooltip: 'Open in YouTube',
                        onTap: _openExternal,
                      ),
                      const SizedBox(width: 6),
                      _PlayerOverlayButton(
                        icon: FontAwesomeIcons.xmark,
                        tooltip: 'Collapse',
                        onTap: _collapse,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _YouTubePlayButton extends StatelessWidget {
  const _YouTubePlayButton({super.key});

  static const double _width = 68;
  static const double _height = 48;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _width,
      height: _height,
      decoration: BoxDecoration(
        color: const Color(0xFFFF0000), // YouTube red
        borderRadius: BorderRadius.circular(14),
      ),
      child: const CustomPaint(painter: _PlayTrianglePainter()),
    );
  }
}

class _PlayTrianglePainter extends CustomPainter {
  const _PlayTrianglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(w * 0.34, h * 0.24) // top-left
      ..lineTo(w * 0.34, h * 0.76) // bottom-left
      ..lineTo(w * 0.80, h * 0.50) // tip (right)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PlayTrianglePainter oldDelegate) => false;
}

class _PlayerOverlayButton extends StatelessWidget {
  const _PlayerOverlayButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final FaIconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
          child: FaIcon(icon, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dashLength,
  });

  final Color color;
  final BorderRadius radius;
  final double dashLength;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, radius.topLeft));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = math.min(d + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += dashLength * 2;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _CommentsSection extends StatefulWidget {
  const _CommentsSection({
    required this.comments,
    required this.loading,
    required this.error,
    required this.hasMore,
    required this.loadingMore,
    required this.sending,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onLoadMore,
    required this.onDelete,
    required this.onReply,
    required this.apiBaseUrl,
  });

  final List<Comment> comments;
  final bool loading;
  final String? error;

  final bool hasMore;
  final bool loadingMore;
  final bool sending;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onLoadMore;
  final void Function(Comment) onDelete;
  final void Function(Comment) onReply;
  final String apiBaseUrl;

  @override
  State<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<_CommentsSection> {
  int? _expandedCommentId;

  @override
  Widget build(BuildContext context) {
    final comments = widget.comments;
    if (widget.loading) {
      return const Column(
        children: [
          ShimmerBox(width: double.infinity, height: 40),
          SizedBox(height: 8),
          ShimmerBox(width: double.infinity, height: 40),
        ],
      );
    }
    if (widget.error != null) {
      return Text(widget.error!,
          style: const TextStyle(color: EnclavdColors.textSecondary));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Composer on top so replies sit right under the post.
        _CommentComposer(
          controller: widget.controller,
          focusNode: widget.focusNode,
          sending: widget.sending,
          onSend: widget.onSend,
        ),
        const Divider(height: 20),
        for (final comment in comments)
          _CommentRow(
            // Key by id: new comments prepend, so positional reuse would
            // misattach row state.
            key: ValueKey(comment.id),
            comment: comment,
            apiBaseUrl: widget.apiBaseUrl,
            onDelete: widget.onDelete,
            onReply: widget.onReply,
            expanded: comment.id == _expandedCommentId,
            onToggle: () => setState(() {
              _expandedCommentId =
                  _expandedCommentId == comment.id ? null : comment.id;
            }),
          ),
        if (widget.hasMore)
          Center(
            child: TextButton.icon(
              onPressed: widget.loadingMore ? null : widget.onLoadMore,
              icon: widget.loadingMore
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const FaIcon(FontAwesomeIcons.anglesDown,
                      size: 13, color: EnclavdColors.link),
              label: Text(
                  widget.loadingMore ? 'Loading...' : 'Load more comments'),
              style: TextButton.styleFrom(
                foregroundColor: EnclavdColors.link,
                textStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }
}

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      // Stays aligned with the input's center as it grows.
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            minLines: 1,
            maxLines: 3,
            maxLength: 1000,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            // 1000-char cap enforced silently, no counter UI.
            style: const TextStyle(
                fontSize: 14, color: EnclavdColors.textPrimary),
            cursorColor: EnclavdColors.link,
            decoration: const InputDecoration(
              hintText: 'Add a comment...',
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
                borderSide: BorderSide(color: EnclavdColors.link, width: 2),
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
          tooltip: 'Send comment',
        ),
      ],
    );
  }
}

/// Maps the server's Tailwind name_color class to our palette.
Color rankColorFromCssClass(String cssClass) {
  if (cssClass.contains('purple')) return RankColors.forRank('SysOp');
  if (cssClass.contains('red')) return RankColors.forRank('Admin');
  if (cssClass.contains('blue')) return RankColors.forRank('Officer');
  if (cssClass.contains('yellow')) return RankColors.forRank('Founding Member');
  return RankColors.forRank('Member');
}

class _CommentRow extends StatefulWidget {
  const _CommentRow({
    super.key,
    required this.comment,
    required this.apiBaseUrl,
    required this.onDelete,
    required this.onReply,
    required this.expanded,
    required this.onToggle,
  });

  final Comment comment;
  final String apiBaseUrl;
  final void Function(Comment) onDelete;

  final void Function(Comment) onReply;

  final bool expanded;

  final VoidCallback onToggle;

  @override
  State<_CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends State<_CommentRow> {
  // Owned here so they get disposed; commentContentSpans hands them over.
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

  Comment get comment => widget.comment;

  String get _visibleContent {
    final content = comment.content;
    if (_expanded || content.length <= _readMoreLimit) return content;
    final preview = content.substring(0, _readMoreLimit);
    final lastSpace = preview.lastIndexOf(' ');
    // Only cut at a word boundary when it leaves a substantial preview.
    return lastSpace > _readMoreLimit * 0.6
        ? content.substring(0, lastSpace)
        : preview;
  }

  List<InlineSpan> _spans() {
    final key = _expanded ? 'full' : 'short';
    if (_cachedFor == key && _cachedSpans != null) return _cachedSpans!;
    // Drop the previous slice's recognizers so none are orphaned.
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
    if (text.length < comment.content.length) {
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
      _openProfile(context, profile.id);
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
      // Never let a link open break the comments.
    }
  }

  @override
  Widget build(BuildContext context) {
    final personality = PersonalityColors.forType(comment.personalityType);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openProfile(context, comment.userId),
            child: EnclavdAvatar(
              size: 28,
              url: resolveMediaUrl(widget.apiBaseUrl,
                  avatarPath: comment.profilePictureUrl),
              borderColor: personality,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openProfile(context, comment.userId),
                        child: Text(
                          comment.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: rankColorFromCssClass(comment.nameColor),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      relativeTime(comment.createdAtUtc),
                      style: const TextStyle(
                          color: EnclavdColors.textSecondary, fontSize: 11),
                    ),
                    if (!comment.isOwner) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => widget.onReply(comment),
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: FaIcon(FontAwesomeIcons.reply,
                              size: 13, color: EnclavdColors.textSecondary),
                        ),
                      ),
                    ],
                    if (comment.isOwner) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => widget.onDelete(comment),
                        child: const FaIcon(FontAwesomeIcons.trashCan,
                            size: 14, color: EnclavdColors.textSecondary),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: _spans()),
                  style: const TextStyle(
                      color: EnclavdColors.textPrimary, fontSize: 14),
                ),
                if (comment.content.length > _readMoreLimit)
                  GestureDetector(
                    onTap: widget.onToggle,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openProfile(BuildContext context, int authorId) {
    if (authorId <= 0) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ProfileScreen(userId: authorId)),
    );
  }
}
