import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../api/messages_service.dart'; // parseDbTime (DB UTC wall-clock)
import '../api/notifications_service.dart';
import '../config/app_config.dart';
import '../services/realtime_service.dart';
import '../services/social_notifications.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/error_view.dart';
import '../utils/html_entities.dart';
import '../widgets/enclavd_avatar.dart';
import 'post_detail_screen.dart';
import 'profile_screen.dart';
import '../services/analytics_service.dart';

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
    trackScreen('/notifications');
    // The drawer is open, so the live path must not also pop a notification.
    SocialNotifications.instance?.setDrawerOpen(true);
    _load();
    // The same SSE ping that lights the bell refreshes the open drawer.
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

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _error = null);
    try {
      final items = await widget.notifications.list();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
      // Mark-read is fire-and-forget; the server state catches up.
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
        // The site's /feed/post/<id> permalink as a native screen.
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
return ErrorView(message: _error!, onRetry: _load);
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
                    // Type chip on the avatar corner.
                    Positioned(
                      right: -4,
                      bottom: -4,
                      // alignment REQUIRED: tight constraints otherwise
                      // paint the glyph off-center.
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
                        // Small unread dot on top of the tinted row.
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

  String _preview(AppNotification n) {
    final decoded = decodeHtmlEntities(n.postPreviewContent).trim();
    if (decoded.isEmpty) return '';
    return decoded.length > 50 ? '${decoded.substring(0, 50)}...' : decoded;
  }

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
