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
import '../theme/enclavd_theme.dart';
import '../widgets/error_view.dart';
import '../utils/content_spans.dart'; // commentContentSpans (@mentions, URLs)
import '../widgets/enclavd_avatar.dart';
import '../widgets/post_card.dart';
import '../widgets/shimmer.dart';
import 'compose_screen.dart';
import 'profile_screen.dart';

/// Forum thread view (site: /domain thread view) — the OP post rendered as
/// a full interactive PostCard, then the replies oldest-first (forum
/// reading order) with a reply composer at the bottom.
///
/// Data comes from api/v1/domains.php?post_id=N (OP + breadcrumb) and
/// api/v1/comments?post_id=N&order=asc (replies). The OP card is the SAME
/// PostCard as the feed (likes, double-tap, edit/delete) with its inline
/// comments suppressed — the replies below ARE the comments, forum style.
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

  /// The category the thread was opened from (AppBar subtitle / breadcrumb
  /// leaf; the API's own trail is authoritative once loaded).
  final String? breadcrumbName;

  /// Injected for tests (real screen resolves AppServices.current).
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

  final _replyController = TextEditingController();
  bool _replying = false;

  AppServices? _services;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  SocialService get _social => widget.social ?? _services!.social;

  PostsService get _posts => widget.posts ?? _services!.posts;

  Future<void> _load() async {
    // When tests inject both services, skip the AppServices dance entirely
    // (no prefs/plugins under flutter test).
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
      final replies =
          await _social.listComments(widget.postId, asc: true); // forum order
      if (!mounted) return;
      setState(() {
        _replies = replies;
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

  Future<void> _sendReply() async {
    final content = _replyController.text.trim();
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

  /// A copy of the post with a fresh comment count (the OP card renders
  /// `post.commentCount`; the forum replies live outside the card).
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

  /// Edit flow: the composer is prefilled (ComposeScreen(post: …)) and pops
  /// true when saved — refetch so the OP shows the updated content.
  Future<void> _editPost(Post post) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ComposeScreen(post: post)),
    );
    if (saved == true && mounted) _load();
  }

  /// Delete flow: same confirm + api/v1 delete as the feed; the thread is
  /// gone afterwards, so the screen pops back to the category list.
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
    // Breadcrumb: Domains / Category / Thread #id — the leaf category
    // name is the AppBar title (the site's breadcrumb trail).
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
      // Reply composer pinned above the keyboard (site: the thread's
      // #reply-form; the app keeps it always visible like the chat input).
      bottomNavigationBar: _post == null
          ? null
          : _ReplyComposer(
              controller: _replyController,
              sending: _replying,
              onSend: _sendReply,
            ),
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
        PostCard(
          key: ValueKey(post.id),
          post: post,
          apiBaseUrl: AppConfig.apiBaseUrl,
          social: _social,
          onEditPost: _editPost,
          onDeletePost: _deletePost,
          hideInlineComments: true, // replies live below, forum style
        ),
        const SizedBox(height: 14),
        _RepliesHeader(count: post.commentCount),
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
              child: Text('No replies yet — start the discussion.',
                  style: TextStyle(
                      fontSize: 13, color: EnclavdColors.textSecondary)),
            ),
          )
        else
          for (var i = 0; i < _replies.length; i++)
            _ForumReplyRow(
              key: ValueKey(_replies[i].id),
              reply: _replies[i],
              number: i + 1,
              onDelete: _deleteReply,
            ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// "Replies (N)" section header (site: domain_comment_list's count header).
class _RepliesHeader extends StatelessWidget {
  const _RepliesHeader({required this.count});

  final int count;

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
        ],
      ),
    );
  }
}

/// One forum reply — the site's domain_comment_card port: #number + avatar
/// + username (rank color) + relative time + content (@mentions/URLs
/// linkified like the feed comments), delete for own replies.
class _ForumReplyRow extends StatefulWidget {
  const _ForumReplyRow({
    super.key,
    required this.reply,
    required this.number,
    required this.onDelete,
  });

  final Comment reply;
  final int number;
  final void Function(Comment) onDelete;

  @override
  State<_ForumReplyRow> createState() => _ForumReplyRowState();
}

class _ForumReplyRowState extends State<_ForumReplyRow> {
  final List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan>? _cachedSpans;

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  Comment get reply => widget.reply;

  List<InlineSpan> _spans() {
    final cached = _cachedSpans;
    if (cached != null) return cached;
    final spans = commentContentSpans(
      reply.content,
      onMention: (username) => _openMention(username),
      onUrl: (url) => _openUrl(url),
      recognizers: _recognizers,
    );
    _cachedSpans = spans;
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
      // Unknown username — site parity (plain text), no error UI.
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Defensive — never let a link open break the replies.
    }
  }

  @override
  Widget build(BuildContext context) {
    final personality = PersonalityColors.forType(reply.personalityType);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reply number gutter (site: the forum-reply #num).
          SizedBox(
            width: 28,
            child: Center(
              child: Text(
                '#${widget.number}',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: EnclavdColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _openProfile(context, reply.userId),
            child: EnclavdAvatar(
              size: 32,
              url: resolveMediaUrl(AppConfig.apiBaseUrl,
                  avatarPath: reply.profilePictureUrl),
              borderColor: personality,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: EnclavdColors.cardSecondary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        reply.createdAt,
                        style: const TextStyle(
                            color: EnclavdColors.textSecondary, fontSize: 11),
                      ),
                      if (reply.isOwner) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => widget.onDelete(reply),
                          child: const FaIcon(FontAwesomeIcons.trashCan,
                              size: 13,
                              color: EnclavdColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(children: _spans()),
                    style: const TextStyle(
                        color: EnclavdColors.textPrimary, fontSize: 14),
                  ),
                ],
              ),
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

/// Bottom reply composer (site: the thread's #reply-form, always visible
/// like the chat input bar).
class _ReplyComposer extends StatelessWidget {
  const _ReplyComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      // The shell's bottom nav is not present here (pushed route) — this
      // bar must clear the PHONE's nav bar (gesture-nav phones).
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: const BoxDecoration(
        color: EnclavdColors.card,
        border: Border(top: BorderSide(color: EnclavdColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                style: const TextStyle(
                    fontSize: 14, color: EnclavdColors.textPrimary),
                cursorColor: EnclavdColors.link,
                decoration: const InputDecoration(
                  hintText: 'Reply…',
                  hintStyle: TextStyle(
                      color: EnclavdColors.textSecondary, fontSize: 14),
                  filled: true,
                  fillColor: EnclavdColors.background,
                  isDense: true,
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
            const SizedBox(width: 8),
            IconButton(
              onPressed: sending ? null : onSend,
              icon: const FaIcon(FontAwesomeIcons.paperPlane,
                  size: 18, color: EnclavdColors.link),
              tooltip: 'Send reply',
            ),
          ],
        ),
      ),
    );
  }
}
