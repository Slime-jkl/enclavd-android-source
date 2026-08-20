import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/messages_service.dart';

import 'api_client_test.dart' show Harness;

/// DB UTC wall-clock string for a UTC DateTime.
String db(DateTime utc) {
  String p(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}-${p(utc.month)}-${p(utc.day)} '
      '${p(utc.hour)}:${p(utc.minute)}:${p(utc.second)}';
}

Map<String, dynamic> conversationJson({
  int id = 1,
  String updatedAt = '2026-08-20 10:00:00',
  int participantId = 42,
  String participants = 'Alice',
  String avatar = '/public/avatars/a.jpg',
  String? personality = 'INTJ',
  String lastActive = '2026-08-20 09:59:00',
  String lastMessage = 'hi there',
  int unreadCount = 0,
}) =>
    {
      'id': id,
      'updated_at': updatedAt,
      'participant_id': participantId,
      'participants': participants,
      'participant_avatar': avatar,
      'participant_personality': personality,
      'last_active': lastActive,
      'last_message': lastMessage,
      'unread_count': unreadCount,
    };

Map<String, dynamic> messageJson({
  int id = 1,
  int conversationId = 7,
  int senderId = 42,
  String senderName = 'Alice',
  String message = 'hello',
  bool? isRead,
  String createdAt = '2026-08-20 10:00:00',
}) =>
    {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'sender_name': senderName,
      'message': message,
      'is_read': isRead,
      'created_at': createdAt,
    };

void main() {
  group('Conversation.fromJson', () {
    test('parses the full inbox row', () {
      final c = Conversation.fromJson(conversationJson(unreadCount: 3));
      expect(c.id, 1);
      expect(c.participantId, 42);
      expect(c.participantName, 'Alice');
      expect(c.participantAvatar, '/public/avatars/a.jpg');
      expect(c.participantPersonality, 'INTJ');
      expect(c.lastMessage, 'hi there');
      expect(c.unreadCount, 3);
      expect(c.hasUnread, isTrue);
    });

    test('personality null and empty preview parse safely', () {
      final c = Conversation.fromJson(
          conversationJson(personality: null, lastMessage: ''));
      expect(c.participantPersonality, isNull);
      expect(c.lastMessage, '');
      expect(c.hasUnread, isFalse);
    });

    test('online heuristic: last_active within 5 minutes → online', () {
      final recent = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
      final c = Conversation.fromJson(
          conversationJson(lastActive: db(recent)));
      expect(c.isOnline, isTrue);
    });

    test('stale last_active (6 min) → offline', () {
      final stale = DateTime.now().toUtc().subtract(const Duration(minutes: 6));
      final c =
          Conversation.fromJson(conversationJson(lastActive: db(stale)));
      expect(c.isOnline, isFalse);
    });

    test('missing last_active → offline', () {
      final c = Conversation.fromJson(conversationJson(lastActive: ''));
      expect(c.isOnline, isFalse);
    });
  });

  group('ChatMessage.fromJson', () {
    test('own message: is_read 0 → false, 1 → true', () {
      expect(ChatMessage.fromJson(messageJson(isRead: false)).isRead, isFalse);
      expect(ChatMessage.fromJson(messageJson(isRead: true)).isRead, isTrue);
    });

    test('inbound message: is_read null stays null', () {
      final m = ChatMessage.fromJson(messageJson(senderId: 42, isRead: null));
      expect(m.isRead, isNull);
      expect(m.isFrom(42), isTrue);
      expect(m.isFrom(1), isFalse);
    });
  });

  group('MessagesService (live harness, real sockets)', () {
    test('conversations() GETs ?conversations=1 and parses the list', () async {
      String? query;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/api/v1/messages') {
          query = req.uri.query;
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'conversations': [
                conversationJson(id: 5, unreadCount: 2),
                conversationJson(id: 6, participants: 'Bob',
                    personality: 'ENTP', lastMessage: ''),
              ],
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final conversations = await MessagesService(h.client).conversations();
      expect(query, 'conversations=1');
      expect(conversations, hasLength(2));
      expect(conversations.first.id, 5);
      expect(conversations.first.unreadCount, 2);
      expect(conversations.last.participantName, 'Bob');

      await h.close();
    });

    test('messages() GETs ?conversation_id=N, oldest-first rows', () async {
      String? query;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/api/v1/messages') {
          query = req.uri.query;
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'messages': [
                messageJson(id: 1, senderId: 42, isRead: null),
                messageJson(id: 2, senderId: 7, message: 'reply', isRead: false),
              ],
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final messages = await MessagesService(h.client).messages(7);
      expect(query, 'conversation_id=7');
      expect(messages, hasLength(2));
      expect(messages.first.isRead, isNull);
      expect(messages.last.message, 'reply');
      expect(messages.last.isRead, isFalse);

      await h.close();
    });

    test('send() POSTs the reply JSON + CSRF and returns message_id',
        () async {
      String? rawBody;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
        } else if (req.uri.path == '/api/v1/messages') {
          rawBody = await utf8.decoder.bind(req).join();
          Harness.respond(req,
              status: 200, body: '{"success":true,"message_id":88}');
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final id = await MessagesService(h.client).send(7, 'hello bob');
      expect(id, 88);
      expect(jsonDecode(rawBody!), {
        'action': 'reply',
        'conversation_id': 7,
        'message': 'hello bob',
      });

      await h.close();
    });

    test('start() POSTs user_id and returns the conversation_id', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
        } else if (req.uri.path == '/api/v1/messages') {
          Harness.respond(req,
              status: 200, body: '{"success":true,"conversation_id":12}');
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final id = await MessagesService(h.client).start(42);
      expect(id, 12);

      await h.close();
    });

    test('markRead() POSTs mark_read and tolerates a 401-ish error', () async {
      var posted = false;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
        } else if (req.uri.path == '/api/v1/messages') {
          posted = true;
          Harness.respond(req, status: 200, body: '{"success":true}');
        } else {
          Harness.respond(req, status: 404);
        }
      });

      await MessagesService(h.client).markRead(7);
      expect(posted, isTrue);

      await h.close();
    });

    test('unreadCount() parses the badge number', () async {
      final h = await Harness.start((req) async {
        Harness.respond(req,
            body: '{"success":true,"unread_count":4}');
      });

      final count = await MessagesService(h.client).unreadCount();
      expect(count, 4);

      await h.close();
    });
  });

  group('parseDbTime / formatMessageTime (EnclavdTime ports)', () {
    test('bare DB wall-clock parses as UTC (no local-shift bug)', () {
      final t = parseDbTime('2026-08-20 21:03:45');
      expect(t, isNotNull);
      expect(t!.isUtc, isTrue);
      expect(t.hour, 21);
      expect(t.minute, 3);
    });

    test('T-separated bare string parses the same', () {
      final t = parseDbTime('2026-08-20T21:03:45');
      expect(t, isNotNull);
      expect(t!.hour, 21);
    });

    test('zoned ISO (date("c")) falls through to the native parser', () {
      final t = parseDbTime('2026-08-20T18:56:24+03:00');
      expect(t, isNotNull);
      // 18:56+03:00 == 15:56 UTC.
      expect(t!.hour, 15);
      expect(t.isUtc, isTrue);
    });

    test('unparseable input → null / empty time', () {
      expect(parseDbTime(''), isNull);
      expect(parseDbTime('nonsense'), isNull);
      expect(formatMessageTime(''), '');
    });

    test('formatMessageTime renders a localized absolute timestamp', () {
      final formatted = formatMessageTime('2026-08-20 21:03:45');
      expect(formatted, contains('2026'));
      expect(formatted, contains('Aug'));
      expect(formatted, contains(':'));
    });
  });
}
