import 'api_client.dart';

/// A conversation in the inbox (GET /api/v1/messages?conversations=1).
///
/// Field contract (port of handlers/messages/get_conversations.php): id,
/// updated_at, participant_id/participants/participant_avatar/
/// participant_personality (the OTHER member(s) — 1-on-1 in practice),
/// last_active, last_message (latest preview, '' when none), unread_count.
class Conversation {
  const Conversation({
    required this.id,
    required this.updatedAt,
    required this.participantId,
    required this.participantName,
    required this.participantAvatar,
    required this.participantPersonality,
    required this.lastActive,
    required this.lastMessage,
    required this.unreadCount,
  });

  final int id;
  final String updatedAt; // DB UTC wall-clock 'YYYY-MM-DD HH:MM:SS'
  final int participantId; // the other member
  final String participantName;
  final String participantAvatar; // root-relative path
  final String? participantPersonality;
  final String lastActive; // DB UTC wall-clock
  final String lastMessage; // latest message preview
  final int unreadCount;

  bool get hasUnread => unreadCount > 0;

  /// The site's presence heuristic (messages.js): anyone whose last_active
  /// is within 5 minutes counts as online. No realtime dependency —
  /// last_active is bumped on every page load by config/init.php.
  bool get isOnline {
    final t = parseDbTime(lastActive);
    if (t == null) return false;
    return DateTime.now().toUtc().difference(t) < const Duration(minutes: 5);
  }

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: (json['id'] as num?)?.toInt() ?? 0,
        updatedAt: json['updated_at'] as String? ?? '',
        participantId: (json['participant_id'] as num?)?.toInt() ?? 0,
        participantName: json['participants'] as String? ?? '',
        participantAvatar: json['participant_avatar'] as String? ??
            '/assets/default-avatar.png',
        participantPersonality: json['participant_personality'] as String?,
        lastActive: json['last_active'] as String? ?? '',
        lastMessage: json['last_message'] as String? ?? '',
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      );
}

/// One message in a thread (GET /api/v1/messages?conversation_id=N).
///
/// Field contract (api/v1/messages.php): id, conversation_id, sender_id,
/// sender_name, message (PLAIN text — messages are stored raw like
/// comments, no HTML encoding), is_read (1/0 ONLY for the viewer's own
/// messages, null for inbound), created_at (DB UTC wall-clock).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  final int id;
  final int conversationId;
  final int senderId;
  final String senderName;
  final String message;
  final bool? isRead; // own: sent(0)/seen(1); inbound: null
  final String createdAt; // DB UTC wall-clock

  bool isFrom(int userId) => senderId == userId;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    // Server sends 0/1 (int); tolerate bool payloads too (tests, proxies).
    final read = json['is_read'];
    final bool? isRead;
    if (read == null) {
      isRead = null;
    } else if (read is bool) {
      isRead = read;
    } else {
      isRead = (read as num) != 0;
    }
    return ChatMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      conversationId: (json['conversation_id'] as num?)?.toInt() ?? 0,
      senderId: (json['sender_id'] as num?)?.toInt() ?? 0,
      senderName: json['sender_name'] as String? ?? '',
      message: json['message'] as String? ?? '',
      isRead: isRead,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

/// MessagesService — the inbox + threads over api/v1 (JSON + CSRF).
///
/// Contracts (verified live against the dev stack, Aug 2026):
///   GET  /api/v1/messages ?conversations=1    → {success, conversations}
///   GET  /api/v1/messages ?conversation_id=N  → {success, messages} —
///        oldest first, read-only (marking read is the caller's POST).
///   GET  /api/v1/messages ?unread_count=1     → {success, unread_count}
///   POST /api/v1/messages {action:'reply', conversation_id, message}
///                                            → {success, message_id}
///   POST /api/v1/messages {action:'start', user_id}
///                                            → {success, conversation_id}
///   POST /api/v1/messages {action:'mark_read', conversation_id}
///                                            → {success}
class MessagesService {
  MessagesService(this._api);

  final ApiClient _api;

  /// The inbox, newest conversation first (server orders by updated_at).
  Future<List<Conversation>> conversations() async {
    final json = await _api.getJson('/api/v1/messages', query: {
      'conversations': '1',
    });
    final raw = json['conversations'] as List<dynamic>? ?? const [];
    return [
      for (final c in raw)
        if (c is Map<String, dynamic>) Conversation.fromJson(c),
    ];
  }

  /// Full history of a conversation, oldest first. Read-only — call
  /// [markRead] when the thread is opened so the sender's receipts flip.
  Future<List<ChatMessage>> messages(int conversationId) async {
    final json = await _api.getJson('/api/v1/messages', query: {
      'conversation_id': '$conversationId',
    });
    final raw = json['messages'] as List<dynamic>? ?? const [];
    return [
      for (final m in raw)
        if (m is Map<String, dynamic>) ChatMessage.fromJson(m),
    ];
  }

  /// Sends a reply in an existing conversation (the site's send_message —
  /// replying also marks inbound messages read server-side).
  Future<int> send(int conversationId, String text) async {
    final json = await _api.postJson('/api/v1/messages', {
      'action': 'reply',
      'conversation_id': conversationId,
      'message': text,
    });
    return (json['message_id'] as num?)?.toInt() ?? 0;
  }

  /// Finds the 1-on-1 conversation with [userId] or creates it.
  Future<int> start(int userId) async {
    final json = await _api.postJson('/api/v1/messages', {
      'action': 'start',
      'user_id': userId,
    });
    return (json['conversation_id'] as num?)?.toInt() ?? 0;
  }

  /// Marks all inbound messages in the conversation as read (fires the
  /// realtime 'read' receipt so the other side's checks flip to seen).
  Future<void> markRead(int conversationId) async {
    await _api.postJson('/api/v1/messages', {
      'action': 'mark_read',
      'conversation_id': conversationId,
    });
  }

  /// Total unread messages across all conversations (header badge).
  Future<int> unreadCount() async {
    final json = await _api.getJson('/api/v1/messages', query: {
      'unread_count': '1',
    });
    return (json['unread_count'] as num?)?.toInt() ?? 0;
  }
}

/// EnclavdTime.parse port (assets/js/time.js): the DB stores every
/// timestamp as a UTC wall-clock string ('YYYY-MM-DD HH:MM:SS') with no
/// zone marker; bare strings must be read as UTC or every value shifts by
/// the device's UTC offset. Strings that carry a zone (date('c')) fall
/// through to the native parser. Returns null on unparseable input.
DateTime? parseDbTime(String input) {
  if (input.isEmpty) return null;
  final s = input.trim();
  if (RegExp(r'^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?$').hasMatch(s)) {
    return DateTime.tryParse('${s.replaceFirst(' ', 'T')}Z')?.toUtc();
  }
  return DateTime.tryParse(s)?.toUtc();
}

/// EnclavdTime.absolute port — a localized absolute timestamp in the
/// viewer's own timezone ('Aug 17, 2026, 8:56 PM'). '' on unparseable.
String formatMessageTime(String dbDateTime) {
  final t = parseDbTime(dbDateTime)?.toLocal();
  if (t == null) return '';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final ampm = t.hour < 12 ? 'AM' : 'PM';
  final mm = t.minute.toString().padLeft(2, '0');
  return '${months[t.month - 1]} ${t.day}, ${t.year}, $h12:$mm $ampm';
}
