import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/notifications_service.dart';
import '../utils/html_entities.dart';
import 'notification_source.dart';
import 'social_notifications.dart';

/// Social notification source (likes, comments, mentions, follows) for the
/// background poller AND the live path's shared candidate generator.
/// Reads GET /api/v1/notifications?list=1 (read-only; the user-facing
/// drawer owns marking read) and emits one candidate per UNREAD bundle.
///
/// Dedupe is deliberately per-BUNDLE: a new like on an already-notified
/// post is a new bundle id, so it re-notifies ("Alice liked" then
/// "Alice & 1 other liked"); re-fetching the SAME bundle keeps the same
/// key and stays silent. The Android notification id is the POST id for
/// post-attached types, so the OS replaces that post's notification
/// instead of stacking one per actor. Gated by the master toggle and the
/// drawer-open flag (mirrored to prefs by SocialNotifications).
class SocialNotificationSource implements NotificationSource {
  /// [fetcher] exists for tests; the default reads via the context's
  /// session-bearing client (GET ?list=1).
  SocialNotificationSource(
      {Future<List<AppNotification>> Function(ApiClient)? fetcher})
      : _fetcher = fetcher;

  static const String drawerOpenPrefsKey = 'notifications_screen_open';

  /// Mirrored by SocialNotifications on every lifecycle change: the
  /// worker is quiet only while the drawer is open AND the app is in the
  /// foreground - minimized must still alert.
  static const String appActivePrefsKey = 'notifications_app_active';

  /// Notification ids are namespaced above the message ids (conversation
  /// ids) so a like and a message never collide on the same id - a
  /// collision would make one REPLACE the other.
  static const int notificationIdOffset = 1000000;

  final Future<List<AppNotification>> Function(ApiClient)? _fetcher;

  @override
  String get id => 'post';

  @override
  Future<List<NotificationCandidate>> check(SourceContext context) async {
    final prefs = context.prefs;
    // Quiet only while the user is literally LOOKING at the drawer (open
    // AND foregrounded); a process killed with the drawer open must not
    // silence the worker.
    final drawerOpen = prefs.getBool(drawerOpenPrefsKey) ?? false;
    final appActive = prefs.getBool(appActivePrefsKey) ?? true;
    if (drawerOpen && appActive) {
      debugPrint('source post: drawer open AND app active, quiet');
      return const []; // the user is looking at the list right now
    }
    if (!(prefs.getBool(SocialNotifications.enabledPrefsKey) ?? true)) {
      debugPrint('source post: master toggle off, quiet');
      return const []; // master toggle off
    }
    try {
      final fetcher =
          _fetcher ?? (ApiClient api) => NotificationsService(api).list();
      final items = await fetcher(context.api);
      debugPrint('source post: fetched ${items.length} bundles');
      return candidatesFrom(items);
    } catch (e) {
      // A dead session or transient blip is the REST flow's job; the
      // next tick retries. The worker must never crash.
      debugPrint('source post: check failed: $e');
      return const [];
    }
  }

  /// One candidate per UNREAD bundle - a PURE function shared by the live
  /// path (handleNotificationPing) and the background worker so both
  /// agree on identity and dedupe keys. The body is the decoded, trimmed
  /// post preview when there is one.
  static List<NotificationCandidate> candidatesFrom(
      List<AppNotification> items) {
    return [
      for (final n in items)
        if (!n.read && n.id > 0)
          NotificationCandidate(
            key: 'post:${n.contentType}:${n.id}',
            notificationId: notificationIdOffset + n.groupId,
            title: n.message,
            body: _previewBody(n.postPreviewContent),
            kind: CandidateKind.social,
          ),
    ];
  }

  static String _previewBody(String raw) {
    final decoded = decodeHtmlEntities(raw).trim();
    if (decoded.isEmpty) return '';
    return decoded.length > 120 ? '${decoded.substring(0, 120)}...' : decoded;
  }

  /// Mirrors the drawer-open state to prefs so the background worker (a
  /// separate isolate that cannot see the in-memory screen state) stays
  /// quiet while the user has the drawer on screen.
  static Future<void> setDrawerOpenPrefs(
          SharedPreferences prefs, bool open) =>
      prefs.setBool(drawerOpenPrefsKey, open);
}
