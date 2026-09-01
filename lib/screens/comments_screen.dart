import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart'; // friendlyErrorText
import '../api/auth_service.dart'; // resolveMediaUrl
import '../api/feed_service.dart'; // Post
import '../api/social_service.dart';
import '../theme/enclavd_theme.dart';
import '../utils/content_spans.dart';
import '../utils/db_time.dart';
import '../widgets/comment_section.dart';
import '../widgets/enclavd_avatar.dart';
import '../widgets/post_card.dart'; // PostImage
import 'hashtag_screen.dart';
import 'profile_screen.dart';

/// Full-screen comments for a post: the post + its comment thread take
/// over the whole screen (smooth zoom-in transition) with the composer
/// pinned at the bottom, so writing is easy. Pops with the latest
/// comment count so the feed card stays in sync.
class CommentsScreen extends StatefulWidget {
  const CommentsScreen({
    super.key,
    required this.post,
    required this.social,
    required this.apiBaseUrl,
  });

  final Post post;
  final SocialService social;
  final String apiBaseUrl;

  /// Zoom-in route: the page scales + fades in from the card, and
  /// reverses (zoom-out) when the back button closes it.
  static Route<int> route({
    required Post post,
    required SocialService social,
    required String apiBaseUrl,
  }) {
    return PageRouteBuilder<int>(
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) =>
          CommentsScreen(post: post, social: social, apiBaseUrl: apiBaseUrl),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  // Owned here so reply taps can insert "@username " and focus the
  // pinned composer.
  final _commentController = TextEditingController();
  final _commentFocus = FocusNode();
  bool _commentSending = false;

  // Set by a comment's reply button: arms parent_comment_id on submit
  // and shows the "Replying to @user" chip above the composer.
  Comment? _replyTarget;

  List<Comment> _comments = const [];
  bool _commentsLoading = true;
  String? _commentsError;

  bool _commentsHasMore = false;
  bool _commentsLoadingMore = false;

  int _commentCount;

  _CommentsScreenState() : _commentCount = 0;

  Post get _post => widget.post;

  @override
  void initState() {
    super.initState();
    _commentCount = _post.commentCount;
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() {
      _commentsLoading = true;
      _commentsError = null;
    });
    try {
      final page =
          await widget.social.listComments(_post.id); // page 1, DESC
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
        _post.id,
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
    setState(() => _replyTarget = comment);
    _commentFocus.requestFocus();
  }

  void _dismissReplyTarget() => setState(() => _replyTarget = null);

  Future<void> _sendComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty || _commentSending) return;
    setState(() {
      _commentSending = true;
      // Optimistic: bump now, server total corrects on success.
      _commentCount += 1;
    });
    try {
      final (comment, newCount) = await widget.social.createComment(
        _post.id,
        content,
        parentCommentId: _replyTarget?.id,
      );
      if (!mounted) return;
      setState(() {
        _comments = [comment, ..._comments]; // newest first (server order)
        _commentCount = newCount;
        _commentSending = false;
        _replyTarget = null;
      });
      _commentController.clear();
      _commentFocus.unfocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _commentSending = false;
        _commentCount -= 1; // roll back the optimistic bump
      });
      _toast(friendlyErrorText(e));
    }
  }

  /// Drops a comment and its whole subtree from the local list (the
  /// server deletes the subtree too).
  void _dropCommentSubtree(int id) {
    final toDrop = <int>{id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final c in _comments) {
        if (c.parentCommentId != null && toDrop.contains(c.parentCommentId) &&
            !toDrop.contains(c.id)) {
          toDrop.add(c.id);
          grew = true;
        }
      }
    }
    _comments = _comments.where((c) => !toDrop.contains(c.id)).toList();
  }

  Future<void> _deleteComment(Comment comment) async {
    setState(() {
      _dropCommentSubtree(comment.id);
      _commentCount -= 1; // optimistic; server total corrects on success
    });
    try {
      final newCount =
          await widget.social.deleteComment(comment.id, _post.id);
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

  void _close() => Navigator.of(context).pop(_commentCount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(commentCount: _commentCount, onClose: _close),
            _PostHeader(post: _post, apiBaseUrl: widget.apiBaseUrl),
            const Divider(height: 1, color: EnclavdColors.divider),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                children: [
                  if (_comments.isEmpty && !_commentsLoading &&
                      _commentsError == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No comments yet - start the discussion.',
                            style: TextStyle(
                                fontSize: 13,
                                color: EnclavdColors.textSecondary)),
                      ),
                    ),
                  CommentsSection(
                    comments: _comments,
                    loading: _commentsLoading,
                    error: _commentsError,
                    hasMore: _commentsHasMore,
                    loadingMore: _commentsLoadingMore,
                    onLoadMore: _loadMoreComments,
                    onDelete: _deleteComment,
                    onReply: _replyToComment,
                    apiBaseUrl: widget.apiBaseUrl,
                  ),
                ],
              ),
            ),
            // Pinned composer: always within reach of the keyboard.
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: const BoxDecoration(
                color: EnclavdColors.card,
                border: Border(
                    top: BorderSide(color: EnclavdColors.border, width: 1)),
              ),
              child: CommentComposer(
                controller: _commentController,
                focusNode: _commentFocus,
                sending: _commentSending,
                replyTarget: _replyTarget,
                onDismissReply: _dismissReplyTarget,
                onSend: _sendComment,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim top bar: back button + a live comment count.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.commentCount, required this.onClose});

  final int commentCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const FaIcon(FontAwesomeIcons.chevronDown,
                size: 18, color: EnclavdColors.textPrimary),
            tooltip: 'Close',
          ),
          const SizedBox(width: 4),
          const Text(
            'Comments',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: EnclavdColors.textPrimary,
            ),
          ),
          const Spacer(),
          const FaIcon(FontAwesomeIcons.comments,
              size: 14, color: EnclavdColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            '$commentCount',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: EnclavdColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Compact post context above the thread: author, time, clamped content
/// and the image (if any).
class _PostHeader extends StatefulWidget {
  const _PostHeader({required this.post, required this.apiBaseUrl});

  final Post post;
  final String apiBaseUrl;

  @override
  State<_PostHeader> createState() => _PostHeaderState();
}

class _PostHeaderState extends State<_PostHeader> {
  final List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan>? _cachedSpans;

  Post get post => widget.post;

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  List<InlineSpan> _spans() {
    if (_cachedSpans != null) return _cachedSpans!;
    final spans = postContentSpans(
      post.content,
      onHashtag: (tag) => _openHashtag(tag),
      onUrl: (url) => _openUrl(url),
      recognizers: _recognizers,
    );
    _cachedSpans = spans;
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
      // Never let a link open break the header.
    }
  }

  void _openProfile(int authorId) {
    if (authorId <= 0) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProfileScreen(userId: authorId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final personality = PersonalityColors.forType(post.personalityType);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _openProfile(post.authorId),
                child: EnclavdAvatar(
                  size: 40,
                  url: resolveMediaUrl(widget.apiBaseUrl,
                      avatarPath: post.profilePictureUrl),
                  borderColor: personality,
                  square: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => _openProfile(post.authorId),
                      child: Text(
                        post.username,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: post.isBlocked
                              ? RankColors.forRank('Blocked')
                              : RankColors.forRank(post.rank),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          decoration: post.isBlocked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      relativeTime(post.createdAt),
                      style: const TextStyle(
                          color: EnclavdColors.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Clamped context; the full content lives on the feed card.
          Text.rich(
            TextSpan(children: _spans()),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: EnclavdColors.textPrimary,
                fontSize: 14,
                height: 1.45),
          ),
          if (post.image != null && post.image!.isNotEmpty) ...[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: PostImage(post: post, apiBaseUrl: widget.apiBaseUrl),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
