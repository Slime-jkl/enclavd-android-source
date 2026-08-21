import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/notifications_service.dart';
import '../utils/html_entities.dart';
import 'notification_source.dart';
import 'social_notifications.dart';

/// Social notification source (likes, comments, mentions, follows) for the
/// background poller AND the live path's shared candidate generator.
///
/// Reads GET /api/v1/notifications?list=1 (the read-only worker shape —
/// nothing is ever marked read here; the user-facing drawer owns that)
/// and emits ONE candidate per UNREAD bundle.
///
/// Dedupe semantics (deliberately per-BUNDLE, not per-post): the bundle id
/// is the newest notification row in the group, so a NEW like on a post you
/// were already notified about is a NEW bundle id → it re-notifies
/// ("Alice liked" then "Alice & 1 other liked") — the same event stream as
/// the badge. Re-fetching the SAME bundle (SSE ping + poll + worker tick)
/// keeps the same key → silent. The Android notification id is the POST id
/// for post-attached types, so the OS replaces that post's notification
/// instead of stacking a new one per actor.
///
/// Gated by the same things as the live path:
///  - the master toggle ('notifications_enabled', Settings), and
///  - the drawer-open flag: while the in-app notification drawer is open
///    in the FOREGROUND app, the worker stays quiet (the user is literally
///    looking at the list). Mirrored to prefs by SocialNotifications.
class SocialNotificationSource implements NotificationSource {
  /// [fetcher] exists for tests; the default reads via the context's
  /// session-bearing client (GET ?list=1).
  SocialNotificationSource(
      {Future<List<AppNotification>> Function(ApiClient)? fetcher})
      : _fetcher = fetcher;

  static const String drawerOpenPrefsKey = 'notifications_screen_open';

  /// Android notification ids are namespaced above the message ids
  /// (conversation ids) so a like and a message never collide on the same
  /// notification id — a collision would make one REPLACE the other.
  static const int notificationIdOffset = 1000000;

  final Future<List<AppNotification>> Function(ApiClient)? _fetcher;

  @override
  String get id => 'post';

  @override
  Future<List<NotificationCandidate>> check(SourceContext context) async {
    final prefs = context.prefs;
    if (prefs.getBool(drawerOpenPrefsKey) ?? false) {
      debugPrint('source post: drawer open, quiet');
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
      // A dead session or transient blip is the app's REST flow's job;
      // the next tick retries. The worker must never crash.
      debugPrint('source post: check failed: $e');
      return const [];
    }
  }

  /// One candidate per UNREAD bundle — a PURE function shared by the live
  /// path (handleNotificationPing) and the background worker so both agree
  /// on identity and dedupe keys. The body is the post preview (decoded,
  /// trimmed) when there is one; the title carries the full "X liked your
  /// post" message.
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
    return decoded.length > 120 ? '${decoded.substring(0, 120)}…' : decoded;
  }

  /// Mirrors the drawer-open state to prefs so the background worker (a
  /// separate isolate that cannot see the in-memory screen state) stays
  /// quiet while the user has the notification drawer on screen.
  static Future<void> setDrawerOpenPrefs(
          SharedPreferences prefs, bool open) =>
      prefs.setBool(drawerOpenPrefsKey, open);
}
