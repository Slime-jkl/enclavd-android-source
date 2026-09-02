import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/auth_service.dart'; // resolveMediaUrl
import '../api/social_service.dart';
import '../main.dart'; // AppServices.current (mention -> profile resolution)
import '../screens/profile_screen.dart';
import '../theme/enclavd_theme.dart';
import '../utils/confirm_dialog.dart';
import '../utils/content_spans.dart';
import '../utils/db_time.dart';
import 'comment_quote_card.dart';
import 'enclavd_avatar.dart';
import 'replies_toggle.dart';
import 'shimmer.dart';
import 'thread_connector.dart';

/// Scrollable comment list: one thread (root + clamped replies behind a
/// rounded L connector) per top-level comment, plus the load-more seam.
/// The composer lives separately so hosts can pin it at the bottom.
class CommentsSection extends StatefulWidget {
  const CommentsSection({
    super.key,
    required this.comments,
    required this.loading,
    required this.error,
    required this.hasMore,
    required this.loadingMore,
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
  final VoidCallback onLoadMore;
  final void Function(Comment) onDelete;
  final void Function(Comment) onReply;
  final String apiBaseUrl;

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  int? _expandedCommentId;

  // Reply groups the user opened. Default: every group is collapsed
  // behind its 'n replies' toggle until tapped.
  final Set<int> _openThreads = {};

  void _toggleReplies(int rootId) {
    setState(() {
      if (!_openThreads.remove(rootId)) _openThreads.add(rootId);
    });
  }

  @override
  Widget build(BuildContext context) {
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
    final tree = CommentTree.build(widget.comments);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final root in tree.roots)
          CommentThread(
            root: root,
            children: tree.children[root.id] ?? const [],
            parentUsernames: tree.parentUsernames,
            apiBaseUrl: widget.apiBaseUrl,
            onDelete: widget.onDelete,
            onReply: widget.onReply,
            expandedId: _expandedCommentId,
            onToggle: (id) => setState(() {
              _expandedCommentId = _expandedCommentId == id ? null : id;
            }),
            nestedOpen: _openThreads.contains(root.id),
            onToggleNested: () => _toggleReplies(root.id),
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

/// Pinned reply composer: input + send, with a dismissible "Replying to
/// @user" chip when a comment's reply button armed a target.
class CommentComposer extends StatelessWidget {
  const CommentComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    this.replyTarget,
    this.onDismissReply,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  /// Armed reply target: shows the "Replying to @user" chip above the
  /// input; the target id rides along on submit.
  final Comment? replyTarget;
  final VoidCallback? onDismissReply;

  @override
  Widget build(BuildContext context) {
    final target = replyTarget;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (target != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
              decoration: BoxDecoration(
                color: EnclavdColors.cardSecondary.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
                border: const Border(
                    left: BorderSide(color: EnclavdColors.link, width: 3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FaIcon(FontAwesomeIcons.reply,
                      size: 12, color: EnclavdColors.link),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Replying to @${target.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: EnclavdColors.link,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (onDismissReply != null)
                    InkWell(
                      onTap: onDismissReply,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: FaIcon(FontAwesomeIcons.xmark,
                            size: 13, color: EnclavdColors.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
          ),
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
        ),
      ],
    );
  }
}

/// One top-level comment plus its clamped replies, behind a left rail.
/// The reply group starts collapsed behind a count toggle; expanding
/// reveals the rows (with the L connector) and moves the toggle under
/// them so the group can be closed again.
class CommentThread extends StatelessWidget {
  const CommentThread({
    super.key,
    required this.root,
    required this.children,
    required this.parentUsernames,
    required this.apiBaseUrl,
    required this.onDelete,
    required this.onReply,
    required this.expandedId,
    required this.onToggle,
    required this.nestedOpen,
    required this.onToggleNested,
  });

  final Comment root;
  final List<Comment> children;
  final Map<int, String> parentUsernames;
  final String apiBaseUrl;
  final void Function(Comment) onDelete;
  final void Function(Comment) onReply;
  final int? expandedId;
  final void Function(int id) onToggle;

  /// Whether this thread's nested replies are shown.
  final bool nestedOpen;
  final VoidCallback onToggleNested;

  @override
  Widget build(BuildContext context) {
    final showRail = children.isNotEmpty && nestedOpen;
    final rootRow = CommentRow(
      // Key by id: new comments prepend, so positional reuse would
      // misattach row state.
      key: ValueKey(root.id),
      comment: root,
      apiBaseUrl: apiBaseUrl,
      onDelete: onDelete,
      onReply: onReply,
      expanded: root.id == expandedId,
      onToggle: () => onToggle(root.id),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showRail)
          // Carry the rail up to the root avatar: rail x 21 = 12 indent +
          // 18/2, start 32 = the avatar's rim at that x (6 pad + 28 box,
          // minus the inset). Painted BEHIND the row, so the avatar and
          // its border cover the overlap and the line seems to start at
          // the rim.
          Stack(
            fit: StackFit.passthrough,
            children: [
              const Positioned.fill(
                child: RailDrop(
                  color: EnclavdColors.border,
                  railX: 21,
                  startY: 32,
                ),
              ),
              rootRow,
            ],
          )
        else
          rootRow,
        if (children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (nestedOpen)
                  for (var i = 0; i < children.length; i++)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ThreadElbow(
                            color: EnclavdColors.border,
                            elbowY: 20, // child avatar 28 center + 6 pad
                            isLast: i == children.length - 1,
                          ),
                          Expanded(
                            child: CommentRow(
                              key: ValueKey(children[i].id),
                              comment: children[i],
                              replyToUsername:
                                  parentUsernames[children[i].id],
                              apiBaseUrl: apiBaseUrl,
                              onDelete: onDelete,
                              onReply: onReply,
                              expanded: children[i].id == expandedId,
                              onToggle: () => onToggle(children[i].id),
                            ),
                          ),
                        ],
                      ),
                    ),
                // Keep the toggle under the reply column so it lines up
                // with the nested text, not the avatar rail.
                Row(
                  children: [
                    const SizedBox(width: 18),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: RepliesToggle(
                          count: children.length,
                          open: nestedOpen,
                          onTap: onToggleNested,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class CommentRow extends StatefulWidget {
  const CommentRow({
    super.key,
    required this.comment,
    required this.apiBaseUrl,
    required this.onDelete,
    required this.onReply,
    required this.expanded,
    required this.onToggle,
    this.replyToUsername,
  });

  final Comment comment;
  final String apiBaseUrl;
  final void Function(Comment) onDelete;

  final void Function(Comment) onReply;

  final bool expanded;

  final VoidCallback onToggle;

  /// Direct reply target, shown as a hint line on nested rows.
  final String? replyToUsername;

  @override
  State<CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends State<CommentRow> {
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

  Future<void> _confirmDelete() async {
    final confirmed = await confirmDelete(
      context,
      title: 'Delete this comment?',
      body: 'This cannot be undone. The comment and any replies '
          'under it will be permanently removed.',
    );
    if (!confirmed || !mounted) return;
    widget.onDelete(comment);
  }

  CommentQuote? _parsedQuote;
  CommentQuote? get _quote =>
      _parsedQuote ??= parseCommentQuote(comment.content);

  /// The part after any quote prefix; read-more clamps THIS, never the
  /// quoted block.
  String get _body => _quote?.body ?? comment.content;

  String get _visibleContent {
    final content = _body;
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
                        onTap: () => _confirmDelete(),
                        child: const FaIcon(FontAwesomeIcons.trashCan,
                            size: 14, color: EnclavdColors.textSecondary),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                if (_quote != null) ...[
                  CommentQuoteCard(quote: _quote!),
                  const SizedBox(height: 6),
                ] else if (widget.replyToUsername case final target?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      'Replying to @$target',
                      style: const TextStyle(
                        color: EnclavdColors.link,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Text.rich(
                  TextSpan(children: _spans()),
                  style: const TextStyle(
                      color: EnclavdColors.textPrimary, fontSize: 14),
                ),
                if (_body.length > _readMoreLimit)
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
