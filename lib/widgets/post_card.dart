import 'dart:async';
import 'dart:math' as math;

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../api/auth_service.dart';
import '../api/feed_service.dart';
import '../api/social_service.dart';
import '../main.dart'; // AppServices.current (mention -> profile resolution)
import '../screens/comments_screen.dart';
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
import 'ignite_button.dart';
import 'ignite_flame_overlay.dart';
import 'likers_sheet.dart';
import 'personality_chip.dart';
import 'post_actions_sheet.dart';
import 'ui/app_button.dart';
import 'ui/app_motion.dart';
import 'ui/app_surface.dart';

class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.apiBaseUrl,
    required this.social,
    this.onEditPost,
    this.onDeletePost,
    this.onPostUpdated,
  });

  final Post post;
  final String apiBaseUrl;
  final SocialService social;

  /// Shows an Edit/Delete menu on the viewer's own posts.
  final void Function(Post post)? onEditPost;
  final void Function(Post post)? onDeletePost;

  /// Fires whenever this card changes the engagement it shows (like, comment,
  /// ignite). The list the card came from owns the post, so it has to take the
  /// new copy: this State is thrown away when the card scrolls out of the cache
  /// extent, and the rebuild seeds from that list, not from here.
  final void Function(Post post)? onPostUpdated;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with IgniteFlamePlayer<PostCard> {
  late int _likeCount;
  late bool _liked;
  late int _commentCount;
  late int _igniteCount;
  late bool _ignited;

  // True while a like toggle is in flight (blocks double-taps).
  bool _likeBusy = false;

  // Heart-burst overlay on double-tap.
  bool _burst = false;

  // --- Drag-to-like (site parity) -----------------------------------------
  // Hold the heart until it arms, then drag it over the post body and drop
  // it there to like. The drop target is only claimed after the hold, so a
  // swipe that starts on the heart still scrolls the feed: the long-press
  // recognizer steps aside as soon as the finger leaves touch slop.
  bool _dragActive = false;
  bool _dragOverDrop = false;
  Offset? _dragPosition; // pointer in the card's Stack space
  Rect? _dropRect; // post body in the card's Stack space
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _dropTargetKey = GlobalKey();

  // Drag-to-like interaction state. The heart lifts the instant the finger
  // lands (zero-delay acknowledgement); the drop tray and the drag itself arm
  // after a ~3-frame still hold, and any movement past the slop radius hands
  // the gesture straight back to the scroll view.
  bool _pressHeld = false;
  bool _likeTrayVisible = false;
  bool _suppressTapLike = false;
  Offset? _dragOrigin;
  Offset? _pressStart;
  bool _tapHandled = false;
  Timer? _trayClearTimer;
  Timer? _suppressResetTimer;

  // The site's "how to like" nudge: a plain tap on an unliked heart must not
  // like, it has to teach the drag instead.
  bool _likeHintVisible = false;
  Timer? _likeHintTimer;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post.likeCount;
    _liked = widget.post.userLiked;
    _commentCount = widget.post.commentCount;
    _igniteCount = widget.post.igniteCount;
    _ignited = widget.post.userIgnited;
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cards are keyed by post id, so a refresh swaps in a fresh Post and
    // keeps this State. Adopt its server counts, or a reload never shows
    // likes/comments made elsewhere. Skip while a like toggle is in
    // flight: its response is authoritative and lands right after.
    final old = oldWidget.post;
    final fresh = widget.post;
    if (!_likeBusy) {
      if (old.userLiked != fresh.userLiked) _liked = fresh.userLiked;
      if (old.likeCount != fresh.likeCount) _likeCount = fresh.likeCount;
      if (old.userIgnited != fresh.userIgnited) _ignited = fresh.userIgnited;
      if (old.igniteCount != fresh.igniteCount) {
        _igniteCount = fresh.igniteCount;
      }
    }
    if (old.commentCount != fresh.commentCount) {
      _commentCount = fresh.commentCount;
    }
  }

  /// Mirror what this card shows into the list that owns the post. A card
  /// scrolled past the cache extent is disposed; the rebuild reads the list.
  void _reportUp() {
    widget.onPostUpdated?.call(
      widget.post.copyWithEngagement(
        likeCount: _likeCount,
        commentCount: _commentCount,
        userLiked: _liked,
        igniteCount: _igniteCount,
        userIgnited: _ignited,
      ),
    );
  }

  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    setState(() {
      _likeBusy = true;
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
    });
    _reportUp();
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
      _reportUp();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = !_liked; // roll back
        _likeCount += _liked ? 1 : -1;
        _likeBusy = false;
      });
      _reportUp();
      _toast('Could not update the like. Try again.');
    }
  }

  void _likeFromGesture() {
    if (_liked || _likeBusy) return;
    _toggleLike();
    _showBurst();
  }

  void _onHeartTap() {
    // A tap that stopped a moving feed never likes and never nags.
    if (_suppressTapLike) {
      _suppressTapLike = false;
      _suppressResetTimer?.cancel();
      return;
    }
    // The pointer-up handler already toggled the unlike for instant feedback;
    // swallow the arena-resolved tap that follows ~300ms later.
    if (_tapHandled) {
      _tapHandled = false;
      return;
    }
    if (_liked) {
      _toggleLike();
      return;
    }
    // Likes are made by dragging the heart onto the post (site parity); a tap
    // on an unliked heart teaches the gesture instead of liking.
    _showLikeHint();
  }

  /// The site's tooltip for a tap on an unliked heart: "Drag the heart onto
  /// the post to like it", near the heart, for a couple of seconds.
  void _showLikeHint() {
    _likeHintTimer?.cancel();
    if (!_likeHintVisible) setState(() => _likeHintVisible = true);
    _likeHintTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _likeHintVisible = false);
    });
  }

  // --- Drag-to-like ---------------------------------------------------------

  /// The heart lifts the instant the finger lands (zero-delay feedback); the
  /// drag itself arms after a tiny still window. A scroll that merely begins
  /// on the heart moves past the slop radius first and keeps the feed
  /// scrolling.
  void _onLikePointerDown(PointerDownEvent event) {
    _pressStart = event.position;
    _tapHandled = false;
    final scroll = Scrollable.maybeOf(context)?.position;
    final scrolling = scroll?.isScrollingNotifier.value ?? false;
    if (scrolling) {
      // Tapping a moving feed should stop it, never like a post.
      scroll!.jumpTo(scroll.pixels);
      _suppressTapLike = true;
      // If the finger then drifts instead of tapping, no tap will fire to
      // consume the flag; clear it shortly after so later taps still like.
      _suppressResetTimer?.cancel();
      _suppressResetTimer = Timer(const Duration(milliseconds: 600), () {
        _suppressTapLike = false;
      });
      return;
    }
    if (_likeBusy) return;
    setState(() => _pressHeld = true);
    _trayClearTimer?.cancel();
  }

  void _onLikePointerUp(PointerUpEvent event) {
    final start = _pressStart;
    _pressStart = null;
    final travelled = start == null ? 0.0 : (event.position - start).distance;
    if (_pressHeld) setState(() => _pressHeld = false);
    if (!_dragActive && _likeTrayVisible) {
      setState(() => _likeTrayVisible = false);
      _scheduleTrayClear();
    }
    // Unlike is a plain tap even on a liked post — and it must feel instant,
    // so it fires here instead of waiting out the ancestor double-tap window.
    if (_liked &&
        !_dragActive &&
        !_suppressTapLike &&
        !_likeBusy &&
        travelled < 10) {
      _tapHandled = true;
      _toggleLike();
    }
  }

  void _onLikePointerCancel(PointerCancelEvent event) {
    _pressStart = null;
    if (_pressHeld) setState(() => _pressHeld = false);
  }

  /// Keeps the overlay mounted just long enough to fade out, then drops it so
  /// hidden tray content can never be found by semantics or tests.
  void _scheduleTrayClear() {
    _trayClearTimer?.cancel();
    _trayClearTimer = Timer(AppMotion.fast, () {
      if (mounted && !_likeTrayVisible) {
        setState(() => _dropRect = null);
      }
    });
  }

  void _armLikeDrag(Offset globalPosition) {
    // A tap that stopped a moving feed must never grow into a like, and a
    // liked post only supports tap-to-unlike (same as the site).
    if (_suppressTapLike || _liked || _likeBusy) {
      if (_likeTrayVisible) {
        setState(() => _likeTrayVisible = false);
        _scheduleTrayClear();
      }
      return;
    }
    final position = _toStackSpace(globalPosition);
    final rect = _measureDropRect();
    if (position == null || rect == null) return;
    _trayClearTimer?.cancel();
    HapticFeedback.mediumImpact();
    setState(() {
      _dragActive = true;
      _dragOverDrop = false;
      _dragOrigin = position;
      _dragPosition = position;
      _dropRect = rect;
      _likeTrayVisible = true;
      _likeHintVisible = false;
    });
    _likeHintTimer?.cancel();
  }

  void _updateLikeDrag(Offset globalPosition) {
    if (!_dragActive) return;
    final position = _toStackSpace(globalPosition);
    if (position == null) return;
    final over = _dropRect?.contains(position) ?? false;
    if (over != _dragOverDrop) HapticFeedback.selectionClick();
    setState(() {
      _dragPosition = position;
      _dragOverDrop = over;
    });
  }

  void _endLikeDrag(Offset globalPosition) {
    if (!_dragActive) return;
    final position = _toStackSpace(globalPosition);
    final dropped =
        position != null && (_dropRect?.contains(position) ?? false);
    final travelled = position != null && _dragOrigin != null
        ? (position - _dragOrigin!).distance
        : 0.0;
    setState(() {
      _dragActive = false;
      _dragOverDrop = false;
      _dragPosition = null;
      _likeTrayVisible = false;
    });
    _scheduleTrayClear();
    if (_liked) return;
    if (_suppressTapLike) {
      _suppressTapLike = false;
      return;
    }
    if (dropped) {
      HapticFeedback.mediumImpact();
      _likeFromGesture();
    } else if (travelled < 12) {
      // A press that never moved is a tap, and a tap on an unliked heart
      // teaches the drag — it never likes.
      _showLikeHint();
    }
  }

  void _cancelLikeDrag() {
    if (!_dragActive && !_likeTrayVisible && !_pressHeld) return;
    setState(() {
      _dragActive = false;
      _dragOverDrop = false;
      _dragPosition = null;
      _likeTrayVisible = false;
      _pressHeld = false;
    });
    _scheduleTrayClear();
  }

  /// The drop tray covers the post body (text, embed, media) exactly like the
  /// site's combined content bounds. Null until the card has been laid out.
  Rect? _measureDropRect() {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final targetBox =
        _dropTargetKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || targetBox == null || !targetBox.hasSize) {
      return null;
    }
    final topLeft = stackBox.globalToLocal(
      targetBox.localToGlobal(Offset.zero),
    );
    // Exactly the content bounds, like the site's tray: text, embed, media.
    return topLeft & targetBox.size;
  }

  Offset? _toStackSpace(Offset globalPosition) {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return null;
    return stackBox.globalToLocal(globalPosition);
  }

  /// The ignite lights itself; the card takes the like it carried and plays
  /// the flame. A re-press replays it.
  void _onIgniteResult(IgniteResult result) {
    setState(() {
      if (result.likeCount > 0) _likeCount = result.likeCount;
      if (result.granted) _liked = true;
      _ignited = true;
      _igniteCount = result.countAfter(_igniteCount);
    });
    playIgniteFlame();
    _reportUp();
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
      backgroundColor: context.enclavd.card,
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
    // Domain posts route to the forum thread (web parity: the comment
    // button is a link to /d/slug/id). Everything else opens the
    // full-screen comments view with a zoom-in transition.
    if (widget.post.hasDomain) {
      await _openDomainThread();
      return;
    }
    final newCount = await Navigator.of(context).push<int>(
      CommentsScreen.route(
        postId: widget.post.id,
        initialCount: widget.post.commentCount,
        social: widget.social,
        apiBaseUrl: widget.apiBaseUrl,
        post: widget.post,
      ),
    );
    // The full-screen view pops with the latest total; keep the card
    // count in sync (covers comments added while it was open).
    if (newCount != null && mounted) {
      setState(() => _commentCount = newCount);
      _reportUp();
    }
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

  Future<void> _openPostActions() async {
    final post = widget.post;
    final action = await showPostActions(
      context,
      post: post,
      canEdit: post.isOwner && widget.onEditPost != null,
      canDelete: post.isOwner && widget.onDeletePost != null,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case PostAction.edit:
        widget.onEditPost?.call(post);
      case PostAction.delete:
        widget.onDeletePost?.call(post);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // One surface per post, the same chrome every reworked screen uses.
    // Long-press still opens the drawer; owners get a visible menu button so
    // edit/delete is discoverable without knowing the gesture.
    final canManage = widget.post.isOwner &&
        (widget.onEditPost != null || widget.onDeletePost != null);
    return AppSurface(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.zero,
      radius: 12,
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        // Double-tap likes (never unlikes); long press opens the post
        // drawer (id, stamps, and edit/delete on your own posts).
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _likeFromGesture,
        onLongPress: _openPostActions,
        child: Stack(
          key: _stackKey,
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PostAuthorRow(
                    post: widget.post,
                    apiBaseUrl: widget.apiBaseUrl,
                    onOpenActions: canManage ? _openPostActions : null,
                  ),
                  if (widget.post.hasDomain &&
                      (widget.post.domainName?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 8),
                    _DomainPromotionBanner(
                      post: widget.post,
                      onTap: _openDomainThread,
                    ),
                  ],
                  const SizedBox(height: 10),
                  KeyedSubtree(
                    key: _dropTargetKey,
                    // Full width, even for a one-line post: the tray and the
                    // drop zone should span the card like they do on the site.
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PostContent(post: widget.post),
                          // First YouTube link in the post renders between
                          // the text and the image.
                          if (extractYouTubeId(widget.post.content)
                              case final id?)
                            _YouTubeEmbed(
                              videoId: id,
                              apiBaseUrl: widget.apiBaseUrl,
                            ),
                          if (widget.post.galleryImages.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            PostCarousel(
                              post: widget.post,
                              apiBaseUrl: widget.apiBaseUrl,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const AppDivider(),
                  const SizedBox(height: 2),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _ActionRow(
                        liked: _liked,
                        likeCount: _likeCount,
                        commentCount: _commentCount,
                        onLike: _onHeartTap,
                        onLikers: _openLikers,
                        onComments: _openComments,
                        pressed: _pressHeld,
                        onLikePressStart: _onLikePointerDown,
                        onLikePressEnd: _onLikePointerUp,
                        onLikePressCancel: _onLikePointerCancel,
                        onLikeDragArm: _armLikeDrag,
                        onLikeDragMove: _updateLikeDrag,
                        onLikeDragDrop: _endLikeDrag,
                        onLikeDragCancel: _cancelLikeDrag,
                        dragEnabled: () => !_liked && !_likeBusy,
                        ignite: IgniteButton(
                          postId: widget.post.id,
                          ignited: _ignited,
                          count: _igniteCount,
                          size: 18,
                          social: widget.social,
                          onResult: _onIgniteResult,
                        ),
                      ),
                      if (_likeHintVisible)
                        const Positioned(
                          left: 0,
                          bottom: 46,
                          child: IgnorePointer(child: _LikeHintBubble()),
                        ),
                    ],
                  ),
                  if (widget.post.hasDomain) ...[
                    const AppDivider(),
                    Align(
                      alignment: Alignment.center,
                      child: InkWell(
                        onTap: _openDomainThread,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FaIcon(
                                FontAwesomeIcons.arrowUpRightFromSquare,
                                color: context.enclavd.link,
                                size: 12,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _commentCount > 0
                                    ? 'View in Domains ($_commentCount '
                                        '${_commentCount == 1 ? 'reply' : 'replies'})'
                                    : 'View in Domains',
                                style: TextStyle(
                                  color: context.enclavd.link,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Heart burst on double-tap (site's showHeartAnimation).
            if (_burst)
              const Positioned.fill(
                child: IgnorePointer(child: Center(child: _HeartBurst())),
              ),
            // The site's ignite flame, over the card it was played on.
            if (flamePlaying)
              Positioned.fill(child: IgnorePointer(child: flameLayer)),
            // Drag-to-like: darken the card, show the dashed tray over the
            // post body, and let the heart follow the finger. The fades keep
            // a cancelled gesture (a scroll, a stray touch) from popping.
            if (_dropRect != null) ...[
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _likeTrayVisible ? 1 : 0,
                    duration: AppMotion.fast,
                    curve: AppMotion.enter,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: _dropRect!,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _likeTrayVisible ? 1 : 0,
                    duration: AppMotion.fast,
                    curve: AppMotion.enter,
                    child: AnimatedScale(
                      scale: _likeTrayVisible ? 1 : 0.97,
                      duration: AppMotion.normal,
                      curve: AppMotion.spring,
                      child: _LikeDropTray(active: _dragOverDrop),
                    ),
                  ),
                ),
              ),
              if (_dragPosition != null && _dropRect != null)
                Positioned(
                  left: _dragPosition!.dx - 24,
                  top: _dragPosition!.dy - 24,
                  child: IgnorePointer(
                    child: _DragHeart(
                      position: _dragPosition!,
                      rect: _dropRect!,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _trayClearTimer?.cancel();
    _suppressResetTimer?.cancel();
    _likeHintTimer?.cancel();
    super.dispose();
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
      child: const FaIcon(
        FontAwesomeIcons.heart,
        color: Color(0xFFF87171),
        size: 64,
      ), // text-red-500 text-6xl
    );
  }
}

class PostAuthorRow extends StatelessWidget {
  const PostAuthorRow({
    super.key,
    required this.post,
    required this.apiBaseUrl,
    this.onOpenActions,
  });

  final Post post;
  final String apiBaseUrl;

  /// Shows the overflow menu beside the timestamp when the viewer can act on
  /// the post (owner edit/delete). Null keeps the row read-only.
  final VoidCallback? onOpenActions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => _openProfile(context, post.authorId),
          child: EnclavdAvatar(
            size: 36,
            url: resolveMediaUrl(
              apiBaseUrl,
              avatarPath: post.profilePictureUrl,
            ),
            rank: post.isBlocked ? 'Blocked' : post.rank,
          ),
        ),
        const SizedBox(width: 10),
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
                              ? context.enclavd.rankName('Blocked')
                              : context.enclavd.rankName(post.rank),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          decoration: post.isBlocked
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: context.enclavd.rankName('Blocked'),
                        ),
                      ),
                    ),
                    if (post.personalityType != null) ...[
                      const SizedBox(width: 6),
                      PersonalityChip(type: post.personalityType!),
                    ],
                    if (post.warningCount > 0) ...[
                      const SizedBox(width: 6),
                      FaIcon(
                        FontAwesomeIcons.triangleExclamation,
                        color: context.enclavd.warning,
                        size: 14,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${post.warningCount}',
                        style: TextStyle(
                          color: context.enclavd.warning,
                          fontSize: 10,
                        ),
                      ),
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
          style: TextStyle(
            color: context.enclavd.textSecondary,
            fontSize: 11.5,
          ),
        ),
        if (onOpenActions != null) ...[
          const SizedBox(width: 2),
          AppIconButton(
            icon: FontAwesomeIcons.ellipsis,
            onPressed: onOpenActions,
            tooltip: 'Post options',
            size: 30,
          ),
        ],
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

class PostContent extends StatefulWidget {
  const PostContent({super.key, required this.post});

  final Post post;

  @override
  State<PostContent> createState() => PostContentState();
}

class PostContentState extends State<PostContent> {
  bool _expanded = false;

  // Owned here so they get disposed; postContentSpans hands them over.
  final List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan>? _cachedSpans;
  Color? _cachedLinkColor; // palette the cache was tokenized with

  @override
  void didUpdateWidget(covariant PostContent oldWidget) {
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
    final linkColor = context.enclavd.link;
    if (_cachedSpans != null && _cachedLinkColor == linkColor) {
      return _cachedSpans!;
    }
    // Drop the previous round's recognizers so none are orphaned.
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final spans = postContentSpans(
      widget.post.content,
      linkColor: linkColor,
      onHashtag: (tag) => _openHashtag(tag),
      onUrl: (url) => _openUrl(url),
      recognizers: _recognizers,
    );
    _cachedSpans = spans;
    _cachedLinkColor = linkColor;
    return spans;
  }

  void _openHashtag(String tag) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => HashtagScreen(tag: tag)));
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
          style: TextStyle(
            fontSize: 14.5,
            height: 1.42,
            color: context.enclavd.textPrimary,
          ),
        ),
        if (needs)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              foregroundColor: context.enclavd.link,
              padding: const EdgeInsets.only(top: 2),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(_expanded ? 'Show less' : 'Show more'),
          ),
      ],
    );
  }
}

/// Probe an image's aspect ratio with a tiny 128px decode, one shot. The
/// listener detaches as soon as the ratio is known, so the only frame left
/// alive is the display decode.
class _AspectProbe extends StatefulWidget {
  const _AspectProbe({required this.url, required this.builder});

  final String url;
  final Widget Function(BuildContext context, double? aspect) builder;

  @override
  State<_AspectProbe> createState() => _AspectProbeState();
}

class _AspectProbeState extends State<_AspectProbe> {
  double? _aspect;
  ImageStream? _stream;
  bool _probeStarted = false;

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

  /// A new url (post edit, carousel slide swap) starts a fresh probe.
  @override
  void didUpdateWidget(covariant _AspectProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url) return;
    _stream?.removeListener(_probeListener);
    _stream = null;
    _aspect = null;
    _probeStarted = false;
    _ensureProbe();
  }

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
      CachedNetworkImageProvider(widget.url),
    );
    final stream = provider.resolve(ImageConfiguration.empty);
    _stream = stream;
    stream.addListener(_probeListener);
  }

  @override
  Widget build(BuildContext context) {
    _ensureProbe();
    return widget.builder(context, _aspect);
  }
}

/// Post image, capped at half the viewport height; tap -> fullscreen viewer.
class PostImage extends StatefulWidget {
  const PostImage({super.key, required this.post, required this.apiBaseUrl});

  final Post post;
  final String apiBaseUrl;

  @override
  State<PostImage> createState() => PostImageState();
}

class PostImageState extends State<PostImage> {
  String get _url =>
      resolveMediaUrl(widget.apiBaseUrl, galleryName: widget.post.image);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _AspectProbe(
        url: _url,
        builder: (context, aspect) => LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = constraints.maxWidth;
            // Cap at 50vh like the site's max-h-[50vh].
            final maxHeight = MediaQuery.sizeOf(context).height * 0.5;
            final height = aspect == null
                ? 180.0 // probing: shimmer at a sane default
                : math.min(contentWidth / aspect, maxHeight);
            return GestureDetector(
              onTap: () => showPostImageViewer(context, [_url]),
              // Long-press saves to the gallery; tap opens the fullscreen viewer.
              onLongPress: () => _showImageSaveSheet(context, _url),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  EnclavdImage(
                    _url,
                    width: contentWidth,
                    height: height,
                    fit: BoxFit.contain,
                    errorAsset: 'assets/images/no-image.jpg',
                    borderRadius: BorderRadius.circular(10),
                  ),
                  const _ExpandHint(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Several images in one post: a swipeable carousel. One image (or a post
/// from before the carousel) renders through [PostImage] unchanged, so the
/// single-image card keeps its exact layout.
class PostCarousel extends StatefulWidget {
  const PostCarousel({super.key, required this.post, required this.apiBaseUrl});

  final Post post;
  final String apiBaseUrl;

  @override
  State<PostCarousel> createState() => _PostCarouselState();
}

class _PostCarouselState extends State<PostCarousel> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.post.galleryImages;
    if (slides.length <= 1) {
      return PostImage(post: widget.post, apiBaseUrl: widget.apiBaseUrl);
    }

    final urls = [
      for (final name in slides)
        resolveMediaUrl(widget.apiBaseUrl, galleryName: name),
    ];

    return Center(
      child: _AspectProbe(
        // The frame follows the lead image's ratio, so swiping never
        // resizes the card; other slides letterbox inside it.
        url: urls.first,
        builder: (context, aspect) => LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = constraints.maxWidth;
            final maxHeight = MediaQuery.sizeOf(context).height * 0.5;
            final height = aspect == null
                ? 180.0
                : math.min(contentWidth / aspect, maxHeight);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: contentWidth,
                  height: height,
                  child: GestureDetector(
                    onTap: () => showPostImageViewer(
                      context,
                      urls,
                      initialIndex: _index,
                    ),
                    onLongPress: () =>
                        _showImageSaveSheet(context, urls[_index]),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        PageView.builder(
                          controller: _controller,
                          itemCount: urls.length,
                          // Build the neighbouring slides ahead of the swipe
                          // so their images start downloading while the
                          // current slide is still on screen. The skeleton
                          // fills any slide that has not decoded yet.
                          allowImplicitScrolling: true,
                          onPageChanged: (i) => setState(() => _index = i),
                          itemBuilder: (context, i) => EnclavdImage(
                            urls[i],
                            width: contentWidth,
                            height: height,
                            fit: BoxFit.contain,
                            errorAsset: 'assets/images/no-image.jpg',
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        const _ExpandHint(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _CarouselDots(
                  count: urls.length,
                  index: _index,
                  onTap: (i) => _controller.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CarouselDots extends StatelessWidget {
  const _CarouselDots({
    required this.count,
    required this.index,
    required this.onTap,
  });

  final int count;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Container(
                key: ValueKey('carousel-dot-$i'),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == index
                      ? context.enclavd.link
                      : context.enclavd.textSecondary.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ExpandHint extends StatelessWidget {
  const _ExpandHint();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const FaIcon(
          FontAwesomeIcons.expand,
          size: 13,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Fullscreen viewer. One url renders the plain zoomable image; several render
/// a pager with a counter, so a carousel opens on the slide that was tapped.
void showPostImageViewer(
  BuildContext context,
  List<String> urls, {
  int initialIndex = 0,
}) {
  if (urls.isEmpty) return;
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: _ImageViewer(
        urls: urls,
        initialIndex: initialIndex.clamp(0, urls.length - 1),
      ),
    ),
  );
}

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.urls, required this.initialIndex});

  final List<String> urls;
  final int initialIndex;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: PageView.builder(
              controller: _controller,
              itemCount: urls.length,
              allowImplicitScrolling: true,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                maxScale: 5,
                // Same shimmer contract as the card: swiping the fullscreen
                // pager must hold a skeleton, not a blank page, until the
                // slide decodes.
                child: SizedBox.expand(
                  child: EnclavdImage(
                    urls[i],
                    fit: BoxFit.contain,
                    errorAsset: 'assets/images/no-image.jpg',
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 24,
          right: 24,
          child: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const FaIcon(
              FontAwesomeIcons.xmark,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
        if (urls.length > 1)
          Positioned(
            bottom: 28,
            left: 0,
            right: 0,
            child: Center(
              child: _ImageCounter(text: '${_index + 1}/${urls.length}'),
            ),
          ),
      ],
    );
  }
}

class _ImageCounter extends StatelessWidget {
  const _ImageCounter({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

void _showImageSaveSheet(BuildContext context, String url) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.enclavd.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => SafeArea(
      child: ListTile(
        leading: FaIcon(
          FontAwesomeIcons.download,
          color: context.enclavd.link,
          size: 18,
        ),
        title: const Text(
          'Save image to device',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Saves to the Enclavd folder in your gallery',
          style: TextStyle(
            color: context.enclavd.textSecondary,
            fontSize: 12.5,
          ),
        ),
        onTap: () {
          Navigator.of(sheetContext).pop();
          _saveImageToDevice(context, url);
        },
      ),
    ),
  );
}

Future<void> _saveImageToDevice(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = await GallerySaver().saveImage(url);
  messenger.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
  );
}

class _DomainPromotionBanner extends StatelessWidget {
  const _DomainPromotionBanner({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final promoter = (post.promoterUsername?.isNotEmpty ?? false)
        ? post.promoterUsername!
        : 'System';
    final domainName = post.domainName ?? '';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          // Soft tint, no border; text scales to fit, never wraps.
          color: context.enclavd.link.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            FaIcon(
              FontAwesomeIcons.bullhorn,
              color: context.enclavd.link,
              size: 11,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      color: context.enclavd.textSecondary,
                      fontSize: 11.5,
                      height: 1.25,
                    ),
                    children: [
                      TextSpan(
                        text: '@$promoter ',
                        style: TextStyle(
                          color: context.enclavd.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const TextSpan(text: 'charted this to '),
                      if (domainName.isNotEmpty)
                        TextSpan(
                          text: domainName,
                          style: TextStyle(
                            color: context.enclavd.link,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const TextSpan(text: ' Domain.'),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
    required this.pressed,
    required this.onLikePressStart,
    required this.onLikePressEnd,
    required this.onLikePressCancel,
    required this.onLikeDragArm,
    required this.onLikeDragMove,
    required this.onLikeDragDrop,
    required this.onLikeDragCancel,
    required this.dragEnabled,
    required this.ignite,
  });

  final bool liked;
  final int likeCount;
  final int commentCount;
  final VoidCallback onLike;
  final VoidCallback onLikers;
  final VoidCallback onComments;

  /// Drag-to-like: the heart lifts the moment it is pressed, and the drag
  /// arms after a very short still hold so scrolling keeps priority.
  final bool pressed;
  final ValueChanged<PointerDownEvent> onLikePressStart;
  final ValueChanged<PointerUpEvent> onLikePressEnd;
  final ValueChanged<PointerCancelEvent> onLikePressCancel;
  final ValueChanged<Offset> onLikeDragArm;
  final ValueChanged<Offset> onLikeDragMove;
  final ValueChanged<Offset> onLikeDragDrop;
  final VoidCallback onLikeDragCancel;

  /// A liked post can only be unliked by tapping, so the drag recognizer must
  /// stay out of the arena entirely and let the tap win.
  final bool Function() dragEnabled;

  /// The shared ignite control, built by the card (it carries its own state).
  final Widget ignite;

  @override
  Widget build(BuildContext context) {
    // Groups sit on a 40px touch target: the icons stay visually light but
    // the row is comfortable to hit while scrolling.
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              _LikeDragTarget(
                liked: liked,
                likeCount: likeCount,
                pressed: pressed,
                onPressStart: onLikePressStart,
                onPressEnd: onLikePressEnd,
                onPressCancel: onLikePressCancel,
                onTapHeart: onLike,
                onTapCount: onLikers,
                onDragArm: onLikeDragArm,
                onDragMove: onLikeDragMove,
                onDragDrop: onLikeDragDrop,
                onDragCancel: onLikeDragCancel,
                dragEnabled: dragEnabled,
              ),
              const SizedBox(width: 10),
              _TapGroup(
                onTap: onComments,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FaIcon(
                      commentCount > 0
                          ? FontAwesomeIcons.solidComments
                          : FontAwesomeIcons.solidComment,
                      color: context.enclavd.textSecondary,
                      size: 18,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$commentCount',
                      style: TextStyle(
                        color: context.enclavd.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // Ignite: one a day, lit on the post that holds it.
              ignite,
            ],
          ),
        ),
        // "Liked by N" opposite the buttons; count also opens the likers sheet.
        if (likeCount > 0)
          InkWell(
            onTap: onLikers,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Text(
                'Liked by $likeCount',
                style: TextStyle(
                  color: context.enclavd.link, // textLink: text-blue-400
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A 40px-tall touch target around a compact icon or count, so the action row
/// stays visually quiet without shrinking the hit area below the 44px guideline
/// once the card padding is included.
class _TapGroup extends StatelessWidget {
  const _TapGroup({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: 40,
          child: Center(widthFactor: 1, child: child),
        ),
      ),
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
        NavigationDelegate(onNavigationRequest: _onNavigationRequest),
      );
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      // Default blocks autoplay=1; flip so the tap starts the video.
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    controller.loadRequest(
      Uri.parse(
        'https://www.youtube-nocookie.com/embed/${widget.videoId}'
        '?playsinline=1&rel=0&autoplay=1',
      ),
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
      launchUrl(
        Uri.parse(request.url.toString()),
        mode: LaunchMode.externalApplication,
      );
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
        mode: LaunchMode.externalApplication,
      );
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
                    color: context.enclavd.card,
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
                        ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
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

/// The heart + count as one target. A tap keeps its old meaning (like /
/// open the likers list); holding arms the drag without stealing a scroll,
/// because the long-press recognizer bows out the moment the finger leaves
/// the tight pre-accept slop.
/// The heart lifts the moment it is pressed; the drag arms after a short
/// still hold. The count next to it stays a plain tap target for the likers
/// sheet, exactly like the site's separate count link.
class _LikeDragTarget extends StatelessWidget {
  const _LikeDragTarget({
    required this.liked,
    required this.likeCount,
    required this.pressed,
    required this.onPressStart,
    required this.onPressEnd,
    required this.onPressCancel,
    required this.onTapHeart,
    required this.onTapCount,
    required this.onDragArm,
    required this.onDragMove,
    required this.onDragDrop,
    required this.onDragCancel,
    required this.dragEnabled,
  });

  final bool liked;
  final int likeCount;
  final bool pressed;
  final ValueChanged<PointerDownEvent> onPressStart;
  final ValueChanged<PointerUpEvent> onPressEnd;
  final ValueChanged<PointerCancelEvent> onPressCancel;
  final VoidCallback onTapHeart;
  final VoidCallback onTapCount;
  final ValueChanged<Offset> onDragArm;
  final ValueChanged<Offset> onDragMove;
  final ValueChanged<Offset> onDragDrop;
  final VoidCallback onDragCancel;
  final bool Function() dragEnabled;

  @override
  Widget build(BuildContext context) {
    final color =
        liked ? context.enclavd.likeActive : context.enclavd.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Listener(
          onPointerDown: onPressStart,
          onPointerUp: onPressEnd,
          onPointerCancel: onPressCancel,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: <Type, GestureRecognizerFactory>{
              _HoldToLikeGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                      _HoldToLikeGestureRecognizer>(
                () => _HoldToLikeGestureRecognizer(
                  enabled: dragEnabled,
                  onArm: onDragArm,
                  onMove: onDragMove,
                  onDrop: onDragDrop,
                  onCancel: onDragCancel,
                ),
                (recognizer) {},
              ),
            },
            child: _TapGroup(
              onTap: onTapHeart,
              child: AnimatedScale(
                scale: pressed ? 1.18 : 1,
                duration: AppMotion.instant,
                curve: AppMotion.emphasized,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FaIcon(
                    FontAwesomeIcons.solidHeart,
                    key: const ValueKey('like-heart'),
                    color: color,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        // Tappable -> the "Liked by" list.
        _TapGroup(
          onTap: onTapCount,
          child: Text(
            '$likeCount',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Arms the drag instantly after a short still hold, and steps out of the way
/// the moment the finger leaves the slop radius: a flick that merely starts on
/// the heart therefore scrolls the feed without ever lifting the tray, while a
/// deliberate press-and-hold grabs the heart almost immediately.
class _HoldToLikeGestureRecognizer extends OneSequenceGestureRecognizer {
  _HoldToLikeGestureRecognizer({
    required this.enabled,
    required this.onArm,
    required this.onMove,
    required this.onDrop,
    required this.onCancel,
  }) : super(debugOwner: 'PostCard like drag');

  /// Liked posts do not support the drag at all: letting this recognizer join
  /// the arena would swallow the tap that unlikes them.
  final bool Function() enabled;
  final ValueChanged<Offset> onArm;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onDrop;
  final VoidCallback onCancel;

  /// Two to three frames at 60 Hz: long enough for a flick to declare itself,
  /// short enough to feel like the drag starts the moment the finger lands.
  static const Duration _hold = Duration(milliseconds: 50);

  /// The finger leaving this radius before the hold resolves is a scroll, not
  /// a grab (10 px sits just inside the platform's ~18 px touch slop).
  static const double _slop = 10;

  /// A pre-arm move this fast is an unambiguous flick: hand off immediately,
  /// even if it is still inside the slop radius.
  static const double _flickVelocity = 1400;

  Timer? _timer;
  int? _pointer;
  Offset _origin = Offset.zero;
  Offset _lastPosition = Offset.zero;
  Duration _lastTime = Duration.zero;
  bool _armed = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer != null) return;
    if (!enabled()) {
      resolve(GestureDisposition.rejected);
      return;
    }
    _pointer = event.pointer;
    _origin = event.position;
    _lastPosition = event.position;
    _lastTime = event.timeStamp;
    startTrackingPointer(event.pointer, event.transform);
    _timer = Timer(_hold, () {
      if (_armed || _pointer == null) return;
      _armed = true;
      resolve(GestureDisposition.accepted);
      onArm(_origin);
    });
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      if (!_armed) {
        // Distance decides first: leave the slop radius and the scroll view
        // keeps the gesture. Velocity is the second opinion — a fast flick
        // that is still inside the radius is equally clearly a scroll.
        final travelled = (event.position - _origin).distance;
        final dt = event.timeStamp - _lastTime;
        final speed = dt > Duration.zero
            ? (event.position - _lastPosition).distance /
                (dt.inMicroseconds / 1e6)
            : 0.0;
        _lastPosition = event.position;
        _lastTime = event.timeStamp;
        if (travelled > _slop || speed > _flickVelocity) {
          _timer?.cancel();
          _timer = null;
          resolve(GestureDisposition.rejected);
          stopTrackingPointer(event.pointer);
        }
        return;
      }
      onMove(event.position);
    } else if (event is PointerUpEvent) {
      if (_armed) {
        onDrop(event.position);
      } else {
        resolve(GestureDisposition.rejected);
      }
      _finish();
    } else if (event is PointerCancelEvent) {
      if (_armed) onCancel();
      _finish();
    }
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
    final pointer = _pointer;
    _pointer = null;
    _armed = false;
    if (pointer != null) stopTrackingPointer(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    _timer?.cancel();
    _timer = null;
    onCancel();
    _finish();
    super.rejectGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'hold-to-like';
}

/// The dashed red tray the site paints over the post body while dragging.
class _LikeDropTray extends StatelessWidget {
  const _LikeDropTray({required this.active});

  /// True when the dragged heart is over the tray (release will like).
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.fast,
      decoration: BoxDecoration(
        // Opaque enough to read the label over the post text it covers.
        color: active
            ? Color.alphaBlend(
                context.enclavd.likeActive.withValues(alpha: 0.16),
                const Color(0xFA0F172A),
              )
            : const Color(0xFA0F172A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: const Color(0xFFF87171).withValues(alpha: active ? 1 : 0.9),
        ),
        // CustomPaint sizes to its child; without this the dashed border
        // would trace the label instead of the drop zone.
        child: const SizedBox.expand(
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Drag the heart here to like',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFFECACA),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The site's tooltip for a tap on an unliked heart: a small bubble above the
/// action row that says how likes are actually made. Fades in fast so the tap
/// itself still feels acknowledged.
class _LikeHintBubble extends StatelessWidget {
  const _LikeHintBubble();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.fast,
      curve: AppMotion.enter,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, 4 * (1 - t)), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xF20F172A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.enclavd.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FaIcon(
              FontAwesomeIcons.solidHeart,
              color: Color(0xFFF87171),
              size: 11,
            ),
            const SizedBox(width: 6),
            Text(
              'Drag the heart onto the post to like it',
              style: TextStyle(
                color: context.enclavd.textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The heart that follows the finger, scaling up and fading slightly with
/// distance from the tray centre (the site's distance feedback).
class _DragHeart extends StatelessWidget {
  const _DragHeart({required this.position, required this.rect});

  final Offset position;
  final Rect rect;

  @override
  Widget build(BuildContext context) {
    final normalized = math.min((position - rect.center).distance / 240, 1.0);
    final scale = 1 + 0.45 * normalized;
    final opacity = 1 - 0.45 * normalized;
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: FaIcon(
              FontAwesomeIcons.solidHeart,
              color: Color(0xFFF87171), // text-red-500
              size: 44,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;
  static const double radius = 12;
  static const double strokeWidth = 2;
  static const double dash = 6;
  static const double gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (final metric in path.computeMetrics()) {
      var start = 0.0;
      while (start < metric.length) {
        final end = math.min(start + dash, metric.length);
        canvas.drawPath(metric.extractPath(start, end), paint);
        start = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) => old.color != color;
}
