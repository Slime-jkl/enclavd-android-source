import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart'; // friendlyErrorText
import '../api/social_service.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/comment_section.dart';

/// Full-screen comments for a post (smooth zoom-in transition) with the
/// composer pinned at the bottom. No post preview: a tall post squeezed
/// the thread and pushed the composer under the keyboard. Pops with the
/// latest comment count so the feed card stays in sync.
class CommentsScreen extends StatefulWidget {
  const CommentsScreen({
    super.key,
    required this.postId,
    this.initialCount = 0,
    required this.social,
    required this.apiBaseUrl,
    this.highlightCommentId,
  });

  final int postId;

  /// The count the caller already knows (a feed card); the first page
  /// corrects it.
  final int initialCount;

  final SocialService social;
  final String apiBaseUrl;

  /// Comment to land on - a notification tap: the list pages forward until
  /// it is loaded, then scrolls to it and tints it.
  final int? highlightCommentId;

  /// Zoom-in route: the page scales + fades in from the card, and
  /// reverses (zoom-out) when the back button closes it.
  static Route<int> route({
    required int postId,
    int initialCount = 0,
    required SocialService social,
    required String apiBaseUrl,
    int? highlightCommentId,
  }) {
    return PageRouteBuilder<int>(
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => CommentsScreen(
        postId: postId,
        initialCount: initialCount,
        social: social,
        apiBaseUrl: apiBaseUrl,
        highlightCommentId: highlightCommentId,
      ),
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

  int _commentCount = 0;

  /// How many extra pages the highlight seek may pull before giving up: a
  /// stale target (deleted comment) must not page through the whole thread.
  static const int _highlightMaxPages = 6;

  @override
  void initState() {
    super.initState();
    _commentCount = widget.initialCount;
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
      // page 1, DESC
      final page = await widget.social.listComments(widget.postId);
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
      return;
    }
    // Outside the fetch's try: a seek that comes up empty must not blank a
    // list that loaded fine.
    await _seekHighlight();
  }

  /// Pages forward until the comment a notification pointed at is loaded
  /// (it is usually in the first page; a busy post can push it back), so
  /// the list can scroll to it.
  Future<void> _seekHighlight() async {
    final target = widget.highlightCommentId;
    if (target == null) return;
    var pages = 0;
    while (mounted &&
        pages < _highlightMaxPages &&
        _commentsHasMore &&
        !_comments.any((c) => c.id == target)) {
      pages++;
      final before = _comments.length;
      await _loadMoreComments();
      // A failed or empty page must not spin this loop.
      if (_comments.length == before) return;
    }
  }

  Future<void> _loadMoreComments() async {
    if (_commentsLoadingMore || !_commentsHasMore) return;
    setState(() => _commentsLoadingMore = true);
    try {
      final page = await widget.social.listComments(
        widget.postId,
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
    _commentController.text = current.isEmpty ? mention : '$current $mention';
    _commentController.selection =
        TextSelection.collapsed(offset: _commentController.text.length);
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
        widget.postId,
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
        if (c.parentCommentId != null &&
            toDrop.contains(c.parentCommentId) &&
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
          await widget.social.deleteComment(comment.id, widget.postId);
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
            Divider(height: 1, color: context.enclavd.divider),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                children: [
                  if (_comments.isEmpty &&
                      !_commentsLoading &&
                      _commentsError == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No comments yet - start the discussion.',
                            style: TextStyle(
                                fontSize: 13,
                                color: context.enclavd.textSecondary)),
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
                    highlightId: widget.highlightCommentId,
                  ),
                ],
              ),
            ),
            // Pinned composer: always within reach of the keyboard.
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: context.enclavd.card,
                border: Border(
                    top: BorderSide(color: context.enclavd.border, width: 1)),
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
            icon: FaIcon(FontAwesomeIcons.chevronDown,
                size: 18, color: context.enclavd.textPrimary),
            tooltip: 'Close',
          ),
          const SizedBox(width: 4),
          Text(
            'Comments',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.enclavd.textPrimary,
            ),
          ),
          const Spacer(),
          FaIcon(FontAwesomeIcons.comments,
              size: 14, color: context.enclavd.textSecondary),
          const SizedBox(width: 6),
          Text(
            '$commentCount',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.enclavd.textSecondary),
          ),
        ],
      ),
    );
  }
}
