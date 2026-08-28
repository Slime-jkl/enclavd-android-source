import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/messages_service.dart';
import 'message_notifications.dart';
import 'notification_source.dart';

/// Messaging source for the background poller (and the live path's shared
/// candidate generator).
///
/// Reads the newest unread messages (GET ?unread=1 - the read-only worker
/// shape; nothing is ever marked read here) and emits ONE candidate per
/// conversation: the newest message of that conversation. The notification
/// id is the conversation id, so a conversation's older notification is
/// replaced instead of stacked. Gated by the master toggle
/// ('message_notifications_enabled') and the chat-open flag (mirrored to
/// prefs by MessageNotifications).
class MessageNotificationSource implements NotificationSource {
  /// [fetcher] exists for tests; the default reads via the context's
  /// session-bearing client (GET ?unread=1).
  MessageNotificationSource(
      {Future<List<UnreadMessage>> Function(ApiClient)? fetcher})
      : _fetcher = fetcher;

  static const String chatOpenPrefsKey = 'messages_screen_open';

  final Future<List<UnreadMessage>> Function(ApiClient)? _fetcher;

  @override
  String get id => 'message';

  @override
  Future<List<NotificationCandidate>> check(SourceContext context) async {
    final prefs = context.prefs;
    if (prefs.getBool(chatOpenPrefsKey) ?? false) {
      debugPrint('source message: chat open, quiet');
      return const []; // user is reading the thread right now
    }
    if (!(prefs.getBool(MessageNotifications.enabledPrefsKey) ?? true)) {
      debugPrint('source message: master toggle off, quiet');
      return const []; // master toggle off
    }
    try {
      final fetcher = _fetcher ??
          (ApiClient api) => MessagesService(api).unreadMessages();
      final unread = await fetcher(context.api);
      debugPrint('source message: fetched ${unread.length} unread');
      return candidatesFrom(unread);
    } catch (e) {
      // A dead session or transient blip is the REST flow's job; the
      // next tick retries. The worker must never crash.
      debugPrint('source message: check failed: $e');
      return const [];
    }
  }

  /// Newest unread message per conversation - a PURE function shared by
  /// the live path (handleUnreadPing) and the background worker so both
  /// agree on identity and dedupe keys. Input is newest-first (the API
  /// contract); ids <= 0 are rejected (legacy publishers emit 0).
  static List<NotificationCandidate> candidatesFrom(
      List<UnreadMessage> unread) {
    final newestPerConversation = <int, UnreadMessage>{};
    for (final m in unread) {
      if (m.messageId <= 0 || m.conversationId <= 0) continue;
      newestPerConversation.putIfAbsent(m.conversationId, () => m);
    }
    return [
      for (final m in newestPerConversation.values)
        NotificationCandidate(
          key: 'message:${m.conversationId}:${m.messageId}',
          notificationId: m.conversationId,
          title: m.senderName,
          body: m.message,
          payload: 'c:${m.conversationId}',
          avatarPath: m.senderAvatar,
        ),
    ];
  }

  /// Mirrors the chat-open state to prefs so the background worker (a
  /// separate isolate that cannot see the in-memory screen state) stays
  /// quiet while the user is reading a thread.
  static Future<void> setChatOpenPrefs(
          SharedPreferences prefs, bool open) =>
      prefs.setBool(chatOpenPrefsKey, open);
}
