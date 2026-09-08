import 'api_client.dart';
import '../utils/db_time.dart';
export '../utils/db_time.dart';

/// A conversation in the inbox (GET /api/v1/messages?conversations=1).
/// Fields: id, updated_at, participant_id/participants/
/// participant_avatar/participant_personality (the OTHER member(s) -
/// 1-on-1 in practice), last_active, last_message ('' when none),
/// unread_count.
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

  /// The site's presence heuristic (messages.js): last_active within 5
  /// minutes = online; bumped on every page load by config/init.php.
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
/// message is PLAIN text (stored raw like comments, no HTML encoding);
/// is_read is 1/0 ONLY for the viewer's own messages, null for inbound.
/// deletedForEveryone tombstones the message (content removed server-side,
/// both sides render a placeholder).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.deletedForEveryone = false,
  });

  final int id;
  final int conversationId;
  final int senderId;
  final String senderName;
  final String message;
  final bool? isRead; // own: sent(0)/seen(1); inbound: null
  final bool deletedForEveryone;
  final String createdAt; // DB UTC wall-clock

  bool isFrom(int userId) => senderId == userId;

  /// Placeholder a tombstone renders; wording mirrors the site.
  String get placeholder =>
      deletedForEveryone ? 'This message was deleted' : '';

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
    final deleted = json['deleted_for_everyone'];
    final bool deletedForEveryone;
    if (deleted is bool) {
      deletedForEveryone = deleted;
    } else {
      deletedForEveryone = (deleted as num?) != null && (deleted as num) != 0;
    }
    return ChatMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      conversationId: (json['conversation_id'] as num?)?.toInt() ?? 0,
      senderId: (json['sender_id'] as num?)?.toInt() ?? 0,
      senderName: json['sender_name'] as String? ?? '',
      message: json['message'] as String? ?? '',
      isRead: isRead,
      deletedForEveryone: deletedForEveryone,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

/// One history window of a thread (GET /api/v1/messages?conversation_id=N).
/// The server returns the NEWEST [limit] messages oldest-first; pass
/// beforeId (the oldest loaded id) to page further back. Block flags
/// describe the block state vs the other participant.
class ThreadPage {
  const ThreadPage({
    required this.messages,
    required this.hasMore,
    required this.blockedByMe,
    required this.blockedByThem,
  });

  final List<ChatMessage> messages; // oldest first
  final bool hasMore;
  final bool blockedByMe;
  final bool blockedByThem;
}

/// Inbox + threads over api/v1 (JSON + CSRF). GET /api/v1/messages with
/// ?conversations=1, ?conversation_id=N (oldest first, read-only),
/// ?unread_count=1 or ?unread=1; POST {action: reply|start|mark_read}.
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

  /// One history window of a conversation, oldest first within the window.
  /// Without [beforeId] the server returns the NEWEST [limit] messages;
  /// pass the oldest loaded message id to page further back. Read-only -
  /// call [markRead] when the thread is opened so the sender's receipts
  /// flip.
  Future<ThreadPage> messages(
    int conversationId, {
    int? beforeId,
    int limit = 30,
  }) async {
    final json = await _api.getJson('/api/v1/messages', query: {
      'conversation_id': '$conversationId',
      if (beforeId != null) 'before_id': '$beforeId',
      'limit': '$limit',
    });
    final raw = json['messages'] as List<dynamic>? ?? const [];
    return ThreadPage(
      messages: [
        for (final m in raw)
          if (m is Map<String, dynamic>) ChatMessage.fromJson(m),
      ],
      hasMore: json['has_more'] as bool? ?? false,
      blockedByMe: json['blocked_by_me'] as bool? ?? false,
      blockedByThem: json['blocked_by_them'] as bool? ?? false,
    );
  }

  /// Deletes a message: scope 'me' hides it from this viewer only
  /// (everyone else keeps their copy); scope 'everyone' removes the
  /// content for all participants (sender-only server-side) and both
  /// sides render a tombstone.
  Future<void> deleteMessage(int messageId, {required String scope}) async {
    await _api.postJson('/api/v1/messages', {
      'action': 'delete_message',
      'message_id': messageId,
      'scope': scope,
    });
  }

  /// Blocks the other participant of [conversationId]. While a block
  /// exists in either direction neither side can send.
  Future<void> block(int conversationId) async {
    await _api.postJson('/api/v1/messages', {
      'action': 'block',
      'conversation_id': conversationId,
    });
  }

  /// Removes a block THIS user placed on the other participant.
  Future<void> unblock(int conversationId) async {
    await _api.postJson('/api/v1/messages', {
      'action': 'unblock',
      'conversation_id': conversationId,
    });
  }

  /// Sends a reply in an existing conversation (the site's send_message;
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

  /// The newest unread messages (the worker shape: GET ?unread=1),
  /// newest first, LIMIT 10. Read-only - nothing is marked read.
  Future<List<UnreadMessage>> unreadMessages() async {
    final json = await _api.getJson('/api/v1/messages', query: {
      'unread': '1',
    });
    final raw = json['messages'] as List<dynamic>? ?? const [];
    return [
      for (final m in raw)
        if (m is Map<String, dynamic>) UnreadMessage.fromJson(m),
    ];
  }
}

/// One unread message (GET /api/v1/messages?unread=1 worker shape) - the
/// payload the notification system renders: who sent it, what they said
/// and which conversation a drawer reply should target.
class UnreadMessage {
  const UnreadMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.message,
    required this.createdAt,
  });

  final int messageId;
  final int conversationId;
  final int senderId;
  final String senderName;
  final String senderAvatar; // root-relative path
  final String message;
  final String createdAt; // DB UTC wall-clock

  factory UnreadMessage.fromJson(Map<String, dynamic> json) => UnreadMessage(
        messageId: (json['message_id'] as num?)?.toInt() ?? 0,
        conversationId: (json['conversation_id'] as num?)?.toInt() ?? 0,
        senderId: (json['sender_id'] as num?)?.toInt() ?? 0,
        senderName: json['sender_name'] as String? ?? '',
        senderAvatar: json['sender_avatar'] as String? ?? '',
        message: json['message'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
      );
}

/// EnclavdTime.absolute port - a localized absolute timestamp in the
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
