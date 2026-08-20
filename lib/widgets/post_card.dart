import 'package:flutter/material.dart';

import '../api/auth_service.dart';
import '../api/feed_service.dart';
import '../api/social_service.dart';
import '../theme/enclavd_theme.dart';
import 'enclavd_image.dart';
import 'shimmer.dart';

/// Post card — visual port of feed/components/post_card.php, now with
/// interactive like + comments.
///
/// Layout (top→bottom):
///   avatar (35px, personality-colored border) · username (rank color)
///   · personality badge · warning count ⚠ · relative time (right)
///   content (pre-line, clamped, "Show more")
///   image (when present; /public/gallery/<name>)
///   like ♥ (tappable, optimistic) · comment count (tappable → comments)
///   comments section (lazy-loaded on first open, composer at the bottom)
class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.apiBaseUrl,
    required this.social,
  });

  final Post post;
  final String apiBaseUrl;
  final SocialService social;

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
  /// authoritative count, roll back on failure.
  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    setState(() {
      _likeBusy = true;
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
    });

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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AuthorRow(post: widget.post, apiBaseUrl: widget.apiBaseUrl),
            const SizedBox(height: 8),
            _PostContent(post: widget.post),
            if (widget.post.image != null && widget.post.image!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _PostImage(post: widget.post, apiBaseUrl: widget.apiBaseUrl),
            ],
            const Divider(height: 24),
            _ActionRow(
              liked: _liked,
              likeCount: _likeCount,
              commentCount: _commentCount,
              onLike: _toggleLike,
              onComments: _openComments,
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
    );
  }
}

/// Author row: avatar + username + badges + relative time.
class _AuthorRow extends StatelessWidget {
  const _AuthorRow({required this.post, required this.apiBaseUrl});

  final Post post;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    final personality = PersonalityColors.forType(post.personalityType);
    return Row(
      children: [
        // 35px circular avatar, personality-colored border (border_color),
        // falls back to default-avatar on error — matches the site's onerror.
        Container(
          width: 35,
          height: 35,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: EnclavdColors.cardSecondary,
            border: Border.all(
              color: personality ?? EnclavdColors.border,
              width: 2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: EnclavdImage(
            resolveMediaUrl(apiBaseUrl, avatarPath: post.profilePictureUrl),
            fit: BoxFit.cover,
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
                    child: Text(
                      post.username,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: post.isBlocked
                            ? RankColors.forRank('Blocked')
                            : RankColors.forRank(post.rank),
                        fontWeight: FontWeight.w600,
                        decoration: post.isBlocked ? TextDecoration.lineThrough : null,
                        decorationColor: RankColors.forRank('Blocked'),
                      ),
                    ),
                  ),
                  if (post.personalityType != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    const Icon(Icons.warning_amber_rounded,
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
        const SizedBox(width: 8),
        Text(
          relativeTime(post.createdAt),
          style: const TextStyle(color: EnclavdColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

/// Content with the site's show-more heuristic.
class _PostContent extends StatefulWidget {
  const _PostContent({required this.post});

  final Post post;

  @override
  State<_PostContent> createState() => _PostContentState();
}

class _PostContentState extends State<_PostContent> {
  bool _expanded = false;

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
        Text(
          widget.post.content,
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

/// Post image with shimmer-while-loading + fade-in (EnclavdImage).
class _PostImage extends StatelessWidget {
  const _PostImage({required this.post, required this.apiBaseUrl});

  final Post post;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    return EnclavdImage(
      resolveMediaUrl(apiBaseUrl, galleryName: post.image),
      fit: BoxFit.contain,
      width: double.infinity,
      errorIcon: Icons.broken_image_outlined,
      borderRadius: BorderRadius.circular(8),
      placeholderHeight: 160,
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
    required this.onComments,
  });

  final bool liked;
  final int likeCount;
  final int commentCount;
  final VoidCallback onLike;
  final VoidCallback onComments;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: onLike,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  color: liked
                      ? EnclavdColors.likeActive
                      : EnclavdColors.textSecondary,
                  size: 22,
                ),
                const SizedBox(width: 6),
                Text('$likeCount',
                    style: TextStyle(
                        color: liked
                            ? EnclavdColors.likeActive
                            : EnclavdColors.textSecondary)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 20),
        InkWell(
          onTap: onComments,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline,
                    color: EnclavdColors.textSecondary, size: 22),
                const SizedBox(width: 6),
                Text('$commentCount',
                    style:
                        const TextStyle(color: EnclavdColors.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }
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
      return Text(error!, style: const TextStyle(color: EnclavdColors.textSecondary));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final comment in comments)
          _CommentRow(
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
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  : const Icon(Icons.send, color: EnclavdColors.link),
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
class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.apiBaseUrl,
    required this.onDelete,
  });

  final Comment comment;
  final String apiBaseUrl;
  final void Function(Comment) onDelete;

  @override
  Widget build(BuildContext context) {
    final personality = PersonalityColors.forType(comment.personalityType);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: EnclavdColors.cardSecondary,
              border: Border.all(
                color: personality ?? EnclavdColors.border,
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: EnclavdImage(
              resolveMediaUrl(apiBaseUrl, avatarPath: comment.profilePictureUrl),
              fit: BoxFit.cover,
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
                    const SizedBox(width: 6),
                    Text(
                      comment.createdAt,
                      style: const TextStyle(
                          color: EnclavdColors.textSecondary, fontSize: 11),
                    ),
                    if (comment.isOwner) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => onDelete(comment),
                        child: const Icon(Icons.delete_outline,
                            size: 15, color: EnclavdColors.textSecondary),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comment.content,
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
}
