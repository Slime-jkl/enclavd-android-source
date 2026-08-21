import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../api/messages_service.dart'; // parseDbTime (DB UTC wall-clock)
import '../api/notifications_service.dart';
import '../config/app_config.dart';
import '../services/realtime_service.dart';
import '../services/social_notifications.dart';
import '../theme/enclavd_theme.dart';
import '../utils/html_entities.dart';
import '../widgets/enclavd_avatar.dart';
import 'post_detail_screen.dart';
import 'profile_screen.dart';

/// The in-app notification drawer — the site's bell dropdown (header.php +
/// components/notifications.js) as a native screen.
///
/// Site parity:
///  - opening the drawer marks EVERYTHING read (toggleNotifications →
///    markAllAsRead([])) and the badge clears;
///  - rows: avatar, message, post preview (50-char clamp, 2 lines), the
///    site's relative time; unread rows get the blue tint;
///  - taps: follow → the user's profile, post-attached types → the native
///    PostDetailScreen for that post (the site's /feed/post/<id>), which
///    fetches api/v1/posts ?post_id=N and renders the full post card;
///    user-management → no-op (site '#').
///
/// Modern app styling (0.7.0): card-style rows (rounded containers +
/// spacing instead of full-width dividers) with a type icon chip on the
/// avatar corner, preview card and a small unread dot.
///
/// Real-time: the drawer subscribes to the SAME realtime stream as the
/// feed — a `notification` SSE ping while the drawer is open refreshes the
/// list instantly (new arrivals render highlighted until the next open).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.notifications,
    required this.realtime,
  });

  final NotificationsService notifications;
  final RealtimeService realtime;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification>? _items; // null = loading
  String? _error;
  StreamSubscription<RealtimeEvent>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    // The drawer is on screen — the live path must not ALSO pop a system
    // notification for something the user is literally looking at.
    SocialNotifications.instance?.setDrawerOpen(true);
    _load();
    // Live refresh: the same SSE ping that lights the bell refreshes the
    // open drawer (site's dropdown only refreshes on open; this is the
    // app's "real time notifications" win).
    _realtimeSub = widget.realtime.events.listen((event) {
      if (event.type == 'notification') _load(silent: true);
    });
  }

  @override
  void dispose() {
    SocialNotifications.instance?.setDrawerOpen(false);
    _realtimeSub?.cancel();
    super.dispose();
  }

  /// Fetch the list; opening the drawer also marks everything read (site
  /// parity — toggleNotifications calls markAllAsRead BEFORE loading).
  /// [silent] keeps the current list on screen while refreshing.
  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _error = null);
    try {
      final items = await widget.notifications.list();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
      // Mark-read is fire-and-forget from the drawer's perspective: the
      // badge clears either way and the server state catches up.
      unawaited(widget.notifications.markAllRead());
    } catch (e) {
      if (!mounted || silent) return;
      setState(() => _error = 'Could not load notifications.');
    }
  }

  void _openNotification(AppNotification n) {
    switch (n.contentType) {
      case 'follow':
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ProfileScreen(userId: n.fromUserId),
        ));
      case 'post-like':
      case 'post-comment':
      case 'comment-mention':
        // Native post-by-id screen (api/v1/posts ?post_id=N) — the site's
        // /feed/post/<id> permalink rendered as a full post card.
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PostDetailScreen(postId: n.contentId),
        ));
      default:
        break; // user-management: site parity (the row links nowhere)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FaIcon(FontAwesomeIcons.triangleExclamation,
                  color: EnclavdColors.likeActive, size: 28),
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: EnclavdColors.textSecondary)),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final items = _items;
    if (items == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: SizedBox(
              width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
        ),
      );
    }
    if (items.isEmpty) {
      // Site empty state: fa-bell-slash + "No notifications yet".
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(FontAwesomeIcons.bellSlash,
                color: EnclavdColors.textSecondary, size: 28),
            SizedBox(height: 10),
            Text('No notifications yet',
                style: TextStyle(color: EnclavdColors.textSecondary)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 2),
        itemBuilder: (context, index) {
          final n = items[index];
          return _NotificationRow(
            notification: n,
            onTap: () => _openNotification(n),
          );
        },
      ),
    );
  }
}

/// Modern card row: rounded container with a type icon chip, personality
/// border avatar, message, preview card and relative time; unread rows
/// get the blue tint + a small dot (site's unread bg, app's card shape).
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  static const Map<String, (FaIconData, Color)> _typeIcons = {
    'post-like': (FontAwesomeIcons.heart, EnclavdColors.likeActive),
    'post-comment': (FontAwesomeIcons.comment, EnclavdColors.link),
    'comment-mention': (FontAwesomeIcons.at, Color(0xFFC084FC)),
    'follow': (FontAwesomeIcons.userPlus, Color(0xFF34D399)),
    'user-management': (FontAwesomeIcons.shieldHalved, Color(0xFFFACC15)),
  };

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final unread = !n.read;
    final (icon, iconColor) = _typeIcons[n.contentType] ??
        (FontAwesomeIcons.bell, EnclavdColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: unread
            ? const Color(0x1A3B82F6) // site: bg-blue-500/10
            : EnclavdColors.card,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    EnclavdAvatar(
                      size: 40,
                      url: n.avatarUrl(AppConfig.apiBaseUrl),
                    ),
                    // Type chip on the avatar corner — the modern "what
                    // kind of event" affordance.
                    Positioned(
                      right: -4,
                      bottom: -4,
                      // alignment is REQUIRED: without it the container
                      // passes tight 18x18 constraints to the FaIcon, whose
                      // glyph paints at the top-left corner — off center,
                      // under the border, out of the circle.
                      child: Container(
                        width: 18,
                        height: 18,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: iconColor,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: EnclavdColors.card, width: 2),
                        ),
                        child: FaIcon(icon, size: 9, color: EnclavdColors.card),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              n.message,
                              style: TextStyle(
                                color: unread
                                    ? EnclavdColors.textPrimary
                                    : EnclavdColors.textSecondary,
                                fontWeight:
                                    unread ? FontWeight.w600 : FontWeight.w400,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _relative(n.createdAt),
                            style: const TextStyle(
                                fontSize: 11,
                                color: EnclavdColors.textSecondary),
                          ),
                        ],
                      ),
                      if (n.isPostAttached && _preview(n).isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.all(8),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: EnclavdColors.cardSecondary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '"${_preview(n)}"',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: EnclavdColors.textSecondary),
                          ),
                        ),
                      if (unread) ...[
                        const SizedBox(height: 6),
                        // Small unread dot — the modern read-state marker
                        // on top of the site's tinted row.
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: EnclavdColors.link,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The site clamps the preview to 50 chars with an ellipsis (and the
  /// content arrives htmlspecialchars-encoded — decode exactly once).
  String _preview(AppNotification n) {
    final decoded = decodeHtmlEntities(n.postPreviewContent).trim();
    if (decoded.isEmpty) return '';
    return decoded.length > 50 ? '${decoded.substring(0, 50)}…' : decoded;
  }

  /// Relative time like the site's EnclavdTime.relative — DB strings are
  /// UTC wall-clock and MUST parse as UTC (parseDbTime).
  String _relative(String dbUtc) {
    final t = parseDbTime(dbUtc);
    if (t == null) return '';
    final diff = DateTime.now().toUtc().difference(t);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    if (diff.inDays < 365) return '${diff.inDays ~/ 30}m';
    return '${diff.inDays ~/ 365}y';
  }
}
