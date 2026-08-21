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
import '../main.dart'; // AppServices.current (mention → profile resolution)
import '../screens/hashtag_screen.dart';
import '../screens/profile_screen.dart';
import '../services/sound_service.dart';
import '../theme/enclavd_theme.dart';
import '../utils/content_spans.dart';
import 'cached_image.dart';
import 'enclavd_avatar.dart';
import 'enclavd_image.dart';
import 'likers_sheet.dart';
import 'shimmer.dart';

/// Post card — visual port of feed/components/post_card.php, now with
/// interactive like + comments.
///
/// Layout (top→bottom):
///   avatar (35px, personality-colored border) · username (rank color)
///   · personality badge · warning count ⚠ · relative time (right)
///   content (pre-line, clamped, "Show more")
///   image (when present; /public/gallery/<name>)
///   action row: like ♥ (tappable, optimistic) · comment count (tappable →
///     comments) left-aligned, "Liked by N" (tappable → likers) opposite
///     (site's justify-between layout)
///   comments section (lazy-loaded on first open, composer at the bottom)
class PostCard extends StatefulWidget {
  const PostCard({
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

  /// Wired by the owning screen (feed / profile). When both are non-null and
  /// the post is the viewer's own, a ⋮ menu with Edit/Delete shows — the
  /// port of the site's post_menu.php.
  final void Function(Post post)? onEditPost;
  final void Function(Post post)? onDeletePost;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late int _likeCount;
  late bool _liked;
  late int _commentCount;

  bool _commentsOpen = false;
  bool _commentsLoading = false;
  List<Comment> _comments = const [];
  String? _commentsError;
  final _commentController = TextEditingController();
  bool _commentSending = false;

  // True while a like toggle is in flight (blocks double-taps).
  bool _likeBusy = false;

  // Heart-burst overlay (double-tap); the site's showHeartAnimation: a
  // 64px heart scales 1→4 and fades out over 0.5s at the card's center.
  bool _burst = false;

  // Drag-to-like tray (site's pointerdown drag): visible while the heart
  // is being held, darkens the card and shows the drop hint.
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
    super.dispose();
  }

  /// Optimistic toggle: flip UI instantly, reconcile with the server's
  /// authoritative count, roll back on failure. Plays the site's like sound
  /// only when the post becomes LIKED (never on unlike — likes.js parity).
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

  /// Like-ONLY entry for the double-tap / drag gestures — mirrors the site's
  /// dblclick handler (`if (!isLiked)`): already-liked posts are a no-op,
  /// these gestures can never unlike.
  void _likeFromGesture() {
    if (_liked || _likeBusy) return;
    _toggleLike();
    _showBurst();
  }

  /// Site click parity (likes.js): a tap on an ALREADY-liked heart unlikes;
  /// a tap on an unliked heart does NOT like — it shows the hint tooltip
  /// ("Drag the heart onto the post to like it").
  void _onHeartTap() {
    if (_likeBusy) return;
    if (_liked) {
      _toggleLike();
    } else {
      _toast('Drag the heart onto the post to like it');
    }
  }

  /// Long-press on the heart starts the drag → the tray appears (site's
  /// pointerdown drag). No-op when already liked (drag is only for liking).
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

  /// "Liked by" sheet (site's showLikers modal) — the like count is
  /// tappable, exactly like the site's count → likers list.
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
    if (_commentsOpen) {
      setState(() => _commentsOpen = false);
      return;
    }
    setState(() {
      _commentsOpen = true;
      _commentsLoading = true;
      _commentsError = null;
    });
    await _loadComments();
  }

  Future<void> _loadComments() async {
    try {
      final comments = await widget.social.listComments(widget.post.id);
      if (!mounted) return;
      setState(() {
        _comments = comments;
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

  Future<void> _sendComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty || _commentSending) return;
    setState(() => _commentSending = true);
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
      setState(() => _commentSending = false);
      _toast(e.toString().replaceFirst('ApiException', 'Error'));
    }
  }

  Future<void> _deleteComment(Comment comment) async {
    try {
      final newCount =
          await widget.social.deleteComment(comment.id, widget.post.id);
      if (!mounted) return;
      setState(() {
        _comments = _comments.where((c) => c.id != comment.id).toList();
        _commentCount = newCount;
      });
    } catch (_) {
      if (!mounted) return;
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
        // Double-tap the post to like — the site's dblclick → heart burst.
        // Like-only (never unlikes).
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
                  const SizedBox(height: 8),
                  // The drop target is the CONTENT area (the site's
                  // contentBounds: text + image) — dropping the heart on the
                  // action row or the author row is not a like.
                  DragTarget<String>(
                    onAcceptWithDetails: (_) => _likeFromGesture(),
                    builder: (context, candidates, rejected) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PostContent(post: widget.post),
                        // The site embeds the FIRST YouTube link in the
                        // post (post_card.php renderYouTubeEmbed) between
                        // the text and the image.
                        if (extractYouTubeId(widget.post.content) case final id?)
                          _YouTubeEmbed(
                              videoId: id, apiBaseUrl: widget.apiBaseUrl),
                        if (widget.post.image != null &&
                            widget.post.image!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _PostImage(
                              post: widget.post, apiBaseUrl: widget.apiBaseUrl),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 24),
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
                  if (_commentsOpen) ...[
                    const SizedBox(height: 8),
                    _CommentsSection(
                      comments: _comments,
                      loading: _commentsLoading,
                      error: _commentsError,
                      sending: _commentSending,
                      controller: _commentController,
                      onSend: _sendComment,
                      onDelete: _deleteComment,
                      apiBaseUrl: widget.apiBaseUrl,
                    ),
                  ],
                ],
              ),
            ),
            // Drag tray (site's pointerdown drag): darken the whole card and
            // show the dashed "Drag the heart here to like" drop zone while
            // the heart is held.
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

/// The site's showHeartAnimation port: a 64px solid heart at the card's
/// center scales 1→4 and fades out over 0.5s, then is removed.
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

/// Author row: avatar + username + badges + relative time (+ own-post menu).
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
        // Avatar + username open the author's profile (site: click through
        // the profile tooltip).
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: EnclavdColors.cardSecondary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          post.personalityType!.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: personality ?? EnclavdColors.textSecondary,
                          ),
                        ),
                      ),
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
        // Own-post actions menu (site's post_menu.php: ellipsis → Edit /
        // Delete). Only rendered for the viewer's own posts.
        if (post.isOwner && (onEdit != null || onDelete != null))
          PopupMenuButton<String>(
            icon: const FaIcon(FontAwesomeIcons.ellipsis,
                size: 16, color: EnclavdColors.textSecondary),
            padding: EdgeInsets.zero,
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

/// Content with the site's show-more heuristic. #hashtags and URLs render
/// blue and tappable (the site's convertHashtagsToLinks/convertUrlsToLinks):
/// hashtag → the hashtag page, link → the system browser (target=_blank).
class _PostContent extends StatefulWidget {
  const _PostContent({required this.post});

  final Post post;

  @override
  State<_PostContent> createState() => _PostContentState();
}

class _PostContentState extends State<_PostContent> {
  bool _expanded = false;

  // Tap recognizers owned by this State — must be disposed (postContentSpans
  // hands ownership to the caller; creating them in build() leaks otherwise).
  final List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan>? _cachedSpans;

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

  /// Hashtag tap → the hashtag page (the site's /feed/tag/<tag>).
  void _openHashtag(String tag) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => HashtagScreen(tag: tag)),
    );
  }

  /// Link tap → the system browser, like the site's target="_blank".
  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Never let a link open break the feed (defensive, like SoundService).
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

/// Post image — port of the site's `feed-image w-auto max-h-[50vh] mx-auto`:
/// capped at half the viewport height (a very tall image must never blow the
/// card up), centered, tap → fullscreen viewer (site's openImageModal).
class _PostImage extends StatelessWidget {
  const _PostImage({required this.post, required this.apiBaseUrl});

  final Post post;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    final url = resolveMediaUrl(apiBaseUrl, galleryName: post.image);
    return Center(
      child: GestureDetector(
        onTap: () => _viewFullImage(context, url),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            EnclavdImage(
              url,
              fit: BoxFit.contain,
              // max-h-[50vh] from the site's feed-image class.
              height: MediaQuery.sizeOf(context).height * 0.5,
              errorAsset: 'assets/images/no-image.jpg',
              borderRadius: BorderRadius.circular(8),
              placeholderHeight: 160,
            ),
            // The site shows a fa-expand overlay on hover; on touch there's
            // no hover, so keep a subtle always-on hint that it opens.
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
      ),
    );
  }

  /// Fullscreen viewer, mirroring the site's black/90 modal: full-res image
  /// (no cacheWidth downscale), pinch-zoom, tap or × to close.
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

/// Like + comment buttons (now interactive).
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
        // Left group (site: `flex items-center gap-6`, aligned left):
        // heart (drag source) + like count + comment button.
        Expanded(
          child: Row(
            children: [
              // The heart is a LongPressDraggable (site: pointerdown drag):
              // HOLD the heart to start the drag — the "drag the heart here to
              // like" tray appears and dropping it on the post content likes it.
              // A plain TAP never likes an unliked post (onLike handles that).
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
                    // Site uses a solid fa-heart that turns red when liked.
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
              // Like count — tappable → "Liked by" list (site: count opens the
              // showLikers modal).
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
                      // Site: fa-comments when there are comments, fa-comment when empty.
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
        // "Liked by N" — inline, opposite the buttons (site's justify-between
        // action bar: `textSecondary text-sm` wrapper, textLink button). The
        // count is also tappable → the same likers sheet.
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

/// Port of the site's extractYouTubeId (feed/helpers/url_helpers.php):
/// the FIRST YouTube video ID in the text — watch?v=, shorts/, embed/ or
/// youtu.be/ forms, 11 chars, case-insensitive like the PHP `~...~i`.
String? extractYouTubeId(String text) {
  final m = RegExp(
    r'(?:https?://)?(?:www\.)?'
    r'(?:youtube\.com/(?:watch\?v=|shorts/|embed/)|youtu\.be/)'
    r'([A-Za-z0-9_-]{11})',
    caseSensitive: false,
  ).firstMatch(text);
  return m?.group(1);
}

/// The site's YouTube embed (renderYouTubeEmbed): a 16:9 card between the
/// post text and the image. The site uses an iframe; the app embeds the
/// REAL YouTube player in a WebView, so the video plays IN the app (streamed
/// from YouTube) instead of redirecting to the YouTube app.
///
/// Tap the thumbnail → the player loads (autoplay=1) and plays inline
/// (playsinline=1). The player keeps its own controls; a small overlay row
/// offers collapse (back to the thumbnail) and an explicit "open in the
/// YouTube app" escape hatch (the player's own links — title, related —
/// also open externally via the navigation delegate).
class _YouTubeEmbed extends StatefulWidget {
  const _YouTubeEmbed({required this.videoId, required this.apiBaseUrl});

  final String videoId;

  /// Used as the embed request's Referer — YouTube requires API-client
  /// identification for embeds inside apps (without it: error 153, "Video
  /// Player Configuration Error"). Same origin the site's own embeds use.
  final String apiBaseUrl;

  @override
  State<_YouTubeEmbed> createState() => _YouTubeEmbedState();
}

class _YouTubeEmbedState extends State<_YouTubeEmbed> {
  bool _playing = false;
  WebViewController? _controller;

  /// Created lazily on first play (a WebView per card is heavy; the feed
  /// only pays for videos the user actually opens) and kept alive under
  /// the thumbnail afterwards, so collapse → re-open resumes instantly.
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
      // Default true blocks autoplay=1 even though the user JUST tapped the
      // thumbnail — flip it so the tap starts the video (the site's iframe
      // plays on click the same way).
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

  /// The embed frame stays in the WebView; the player's own OUT-links
  /// (title, related videos, "Watch on YouTube") open in the YouTube app /
  /// browser — the app itself never redirects, only explicit taps inside
  /// the player leave.
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
      // Defensive, like every other launcher call — never break the feed.
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
              // The player stays mounted once created (even while collapsed)
              // so its state survives — the thumbnail just covers it.
              if (_controller != null) WebViewWidget(controller: _controller!),
              if (!_playing)
                // Thumbnail card (tap to play). Solid background hides the
                // loaded player underneath when collapsing back.
                GestureDetector(
                  onTap: _play,
                  child: Container(
                    color: EnclavdColors.card,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // hqdefault always exists for every video id
                        // (maxresdefault does not — no broken embeds).
                        EnclavdImage(
                          'https://img.youtube.com/vi/${widget.videoId}/hqdefault.jpg',
                          fit: BoxFit.cover,
                          errorAsset: 'assets/images/no-image.jpg',
                        ),
                        Center(
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const FaIcon(FontAwesomeIcons.play,
                                size: 20, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_playing) ...[
                // Player overlay controls: collapse back to the thumbnail,
                // or hand off to the YouTube app explicitly.
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

/// Small circular overlay button on the playing embed (black/60 chip).
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

/// Dashed rounded-rect border — the site's `2px dashed` drop tray.
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

/// Lazy-loaded comments: list (newest first) + composer.
class _CommentsSection extends StatelessWidget {
  const _CommentsSection({
    required this.comments,
    required this.loading,
    required this.error,
    required this.sending,
    required this.controller,
    required this.onSend,
    required this.onDelete,
    required this.apiBaseUrl,
  });

  final List<Comment> comments;
  final bool loading;
  final String? error;
  final bool sending;
  final TextEditingController controller;
  final VoidCallback onSend;
  final void Function(Comment) onDelete;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Column(
        children: [
          ShimmerBox(width: double.infinity, height: 40),
          SizedBox(height: 8),
          ShimmerBox(width: double.infinity, height: 40),
        ],
      );
    }
    if (error != null) {
      return Text(error!,
          style: const TextStyle(color: EnclavdColors.textSecondary));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final comment in comments)
          _CommentRow(
            // Key by comment id: the list mutates at the TOP (new comments
            // prepend), so positional State reuse would attach one row's
            // cached mention recognizers to a different comment.
            key: ValueKey(comment.id),
            comment: comment,
            apiBaseUrl: apiBaseUrl,
            onDelete: onDelete,
          ),
        const Divider(height: 20),
        // Composer
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Add a comment…',
                  isDense: true,
                  // No box of its own and NO focus outline — the theme's
                  // blue OutlineInputBorder must not appear here either.
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
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
            ),
          ],
        ),
      ],
    );
  }
}

/// Port of feed/render_functions.php format_date():
/// now / Xm / Xh / Xd / Xm(month) / Xy — minutes shown as 'm' like the site.
String relativeTime(String dbDateTime) {
  final parsed = DateTime.tryParse(dbDateTime.replaceFirst(' ', 'T'));
  if (parsed == null) return '';
  final now = DateTime.now();
  final diff = now.difference(parsed);
  if (diff.inSeconds < 0) return 'now';
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  // Approximate months as 30 days (matches PHP's DateTime::diff month units).
  final days = diff.inDays;
  if (days < 30) return '${days}d';
  if (days < 365) return '${days ~/ 30}m';
  return '${days ~/ 365}y';
}

/// Maps the server's Tailwind class (name_color) to our palette. Unknown
/// classes fall back to Member gray.
Color rankColorFromCssClass(String cssClass) {
  if (cssClass.contains('purple')) return RankColors.forRank('SysOp');
  if (cssClass.contains('red')) return RankColors.forRank('Admin');
  if (cssClass.contains('blue')) return RankColors.forRank('Officer');
  if (cssClass.contains('yellow')) return RankColors.forRank('Founding Member');
  return RankColors.forRank('Member');
}

/// One comment row: avatar, username (rank color), content, relative time,
/// delete for own comments.
///
/// Content renders the site's comment pipeline (render_comment_content):
/// @mentions → link-blue profile links (the server validates mentions
/// against the post's commenters, so every mention is a real user), URLs →
/// link-blue → system browser. NO hashtags (site parity).
class _CommentRow extends StatefulWidget {
  const _CommentRow({
    super.key,
    required this.comment,
    required this.apiBaseUrl,
    required this.onDelete,
  });

  final Comment comment;
  final String apiBaseUrl;
  final void Function(Comment) onDelete;

  @override
  State<_CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends State<_CommentRow> {
  // Tap recognizers owned by this State — must be disposed (commentContent-
  // Spans hands ownership to the caller; creating them in build() leaks).
  final List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan>? _cachedSpans;

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  Comment get comment => widget.comment;

  List<InlineSpan> _spans() {
    final cached = _cachedSpans;
    if (cached != null) return cached;
    final spans = commentContentSpans(
      comment.content,
      onMention: (username) => _openMention(username),
      onUrl: (url) => _openUrl(url),
      recognizers: _recognizers,
    );
    _cachedSpans = spans;
    return spans;
  }

  /// Mention tap → the mentioned member's profile. The server only allows
  /// mentions of users who commented on the post, so the name always
  /// resolves; a stale/deleted account is a silent no-op (the site renders
  /// unknown mentions as plain text).
  Future<void> _openMention(String username) async {
    final services = AppServices.current ?? await AppServices.create();
    if (!mounted) return;
    try {
      final profile = await services.profile.fetchProfileByUsername(username);
      if (!mounted || profile.id <= 0) return;
      _openProfile(context, profile.id);
    } catch (_) {
      // Unknown username — site parity (plain text), no error UI.
    }
  }

  /// Link tap → the system browser, like the site's target="_blank".
  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Defensive — never let a link open break the comments.
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
                    Flexible(
                      child: GestureDetector(
                        onTap: () => _openProfile(context, comment.userId),
                        child: Text(
                          comment.username,
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
                      comment.createdAt,
                      style: const TextStyle(
                          color: EnclavdColors.textSecondary, fontSize: 11),
                    ),
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
