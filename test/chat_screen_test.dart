import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/messages_service.dart';
import 'package:enclavd/screens/chat_screen.dart';
import 'package:enclavd/services/realtime_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';

class FakeMessages extends MessagesService {
  FakeMessages() : super(_noopClient());

  static ApiClient _noopClient() => ApiClient(
        store: _NoopStore(),
        apiBaseUrl: 'https://example.com',
      );

  List<ChatMessage> history = [];
  List<Conversation> inbox = [];
  int? lastMarkedRead;
  int markReadCalls = 0;
  int nextMessageId = 100;
  final List<String> sentTexts = [];
  int unreadAnswer = 0;
  bool hasMoreAnswer = false;
  bool blockedByMeAnswer = false;
  bool blockedByThemAnswer = false;
  final List<(int, String)> deletedMessages = [];
  final List<int> blockedConversations = [];
  final List<int> unblockedConversations = [];

  @override
  Future<List<Conversation>> conversations() async => inbox;

  @override
  Future<ThreadPage> messages(
    int conversationId, {
    int? beforeId,
    int limit = 30,
  }) async =>
      ThreadPage(
        messages: history,
        hasMore: hasMoreAnswer,
        blockedByMe: blockedByMeAnswer,
        blockedByThem: blockedByThemAnswer,
      );

  @override
  Future<void> deleteMessage(int messageId, {required String scope}) async {
    deletedMessages.add((messageId, scope));
  }

  @override
  Future<void> block(int conversationId) async {
    blockedConversations.add(conversationId);
  }

  @override
  Future<void> unblock(int conversationId) async {
    unblockedConversations.add(conversationId);
  }

  @override
  Future<void> markRead(int conversationId) async {
    lastMarkedRead = conversationId;
    markReadCalls++;
  }

  @override
  Future<int> send(int conversationId, String text) async {
    sentTexts.add(text);
    return nextMessageId++;
  }

  @override
  Future<int> unreadCount() async => unreadAnswer;
}

class FakeRealtime extends RealtimeService {
  FakeRealtime() : super(_noopClient(), baseUrl: 'https://example.com');

  static ApiClient _noopClient() => ApiClient(
        store: _NoopStore(),
        apiBaseUrl: 'https://example.com',
      );

  final _controller = StreamController<RealtimeEvent>.broadcast();
  final List<int> joined = [];
  final List<int> left = [];
  final List<(int, bool)> typingFrames = [];

  @override
  Stream<RealtimeEvent> get events => _controller.stream;

  @override
  Future<void> connectWs() async {}

  @override
  Future<void> connectSse() async {}

  @override
  void join(int conversationId) => joined.add(conversationId);

  @override
  void leave(int conversationId) => left.add(conversationId);

  @override
  void sendTyping(int conversationId, bool isTyping) =>
      typingFrames.add((conversationId, isTyping));

  void emit(RealtimeEvent event) => _controller.add(event);
}

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

ChatMessage msg({
  required int id,
  required int senderId,
  required String message,
  bool? isRead,
  bool deleted = false,
}) =>
    ChatMessage(
      id: id,
      conversationId: 7,
      senderId: senderId,
      senderName: senderId == 1 ? 'me' : 'Alice',
      message: message,
      isRead: isRead,
      deletedForEveryone: deleted,
      createdAt: '2026-08-20 10:00:00',
    );

Finder receiptIcon(int messageId) =>
    find.byKey(ValueKey('receipt-$messageId'));

void main() {
  Future<(FakeRealtime, FakeMessages)> pumpChat(
      WidgetTester tester, FakeMessages fake) async {
    final realtime = FakeRealtime();
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: ChatScreen(
        conversationId: 7,
        myUserId: 1,
        messages: fake,
        realtime: realtime,
        participantId: 42,
        participantName: 'Alice',
        participantAvatar: '/a.png',
        participantPersonality: 'INTJ',
        participantIsOnline: true,
      ),
    ));
    await tester.pump(); // history future resolves
    return (realtime, fake);
  }

  testWidgets('renders history with sent/received receipts', (tester) async {
    final fake = FakeMessages()
      ..history = [
        msg(id: 1, senderId: 42, message: 'hi there'), // inbound
        msg(id: 2, senderId: 1, message: 'yo', isRead: false), // sent
        msg(id: 3, senderId: 1, message: 'seen ya', isRead: true), // seen
      ];

    final (realtime, _) = await pumpChat(tester, fake);
    await tester.pump();

    expect(find.text('hi there'), findsOneWidget);
    expect(find.text('yo'), findsOneWidget);
    expect(find.text('seen ya'), findsOneWidget);

    // Receipts: single check for sent, double check blue for seen.
    expect(receiptIcon(2), findsOneWidget);
    expect(receiptIcon(3), findsOneWidget);
    final sentReceipt =
        tester.widget<FaIcon>(receiptIcon(2));
    final seenReceipt =
        tester.widget<FaIcon>(receiptIcon(3));
    expect(sentReceipt.icon!.codePoint, FontAwesomeIcons.check.codePoint);
    expect(seenReceipt.icon!.codePoint,
        FontAwesomeIcons.checkDouble.codePoint);

    expect(fake.lastMarkedRead, 7);
    expect(realtime.joined, contains(7));

    await tester.pumpWidget(const SizedBox()); // dispose the poll timer
  });

  testWidgets('tapping a bubble toggles its timestamp', (tester) async {
    final fake = FakeMessages()
      ..history = [msg(id: 1, senderId: 42, message: 'secret')];

    await pumpChat(tester, fake);
    await tester.pump();

    // Timestamps hidden by default (site parity).
    expect(find.textContaining('2026'), findsNothing);

    await tester.tap(find.text('secret'));
    await tester.pump();
    expect(find.textContaining('2026'), findsOneWidget);

    await tester.tap(find.text('secret'));
    await tester.pump();
    expect(find.textContaining('2026'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('send appends the bubble, clears the input and calls the API',
      (tester) async {
    final fake = FakeMessages()..history = [msg(id: 1, senderId: 42, message: 'hi')];

    await pumpChat(tester, fake);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'hello bob');
    await tester.tap(find.byKey(const ValueKey('send-button')));
    await tester.pump(); // send future resolves
    await tester.pump(); // setState frame

    expect(fake.sentTexts, ['hello bob']);
    expect(find.text('hello bob'), findsOneWidget);
    // Regression: the merge must NOT collapse the thread to just the new bubble (vanish/reappear glitch).
    expect(find.text('hi'), findsOneWidget,
        reason: 'history must survive sending');
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, '');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty thread still shows the input bar', (tester) async {
    final fake = FakeMessages();

    await pumpChat(tester, fake);
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Type your message...'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('header shows the participant name and online state',
      (tester) async {
    final fake = FakeMessages()..history = [];

    await pumpChat(tester, fake);
    await tester.pump();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('- online'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tombstone renders a placeholder, no receipt icon',
      (tester) async {
    final fake = FakeMessages()
      ..history = [
        msg(id: 1, senderId: 42, message: 'gone', deleted: true),
        msg(id: 2, senderId: 1, message: 'kept', isRead: false),
      ];

    await pumpChat(tester, fake);
    await tester.pump();

    expect(find.text('This message was deleted'), findsOneWidget);
    expect(find.text('gone'), findsNothing);
    // Tombstones carry no sent/seen receipts.
    expect(receiptIcon(1), findsNothing);
    expect(receiptIcon(2), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('blocked chat shows the banner and disables the composer',
      (tester) async {
    final fake = FakeMessages()
      ..history = [msg(id: 1, senderId: 42, message: 'hi')]
      ..blockedByMeAnswer = true;

    await pumpChat(tester, fake);
    await tester.pump();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('- blocked'), findsOneWidget);
    expect(find.textContaining('You blocked'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('block button flips state via the service', (tester) async {
    final fake = FakeMessages()
      ..history = [msg(id: 1, senderId: 42, message: 'hi')];

    await pumpChat(tester, fake);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('block-button')));
    await tester.pump(); // dialog
    await tester.tap(find.text('OK'));
    await tester.pump(); // block future
    await tester.pump();

    expect(fake.blockedConversations, [7]);
    expect(find.text('- blocked'), findsOneWidget);
    expect(fake.blockedByMeAnswer, isTrue, reason: 'fake flag untouched');
    // UI state comes from the service response, not the fake's answer.

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('delete for me long-press removes the bubble', (tester) async {
    final fake = FakeMessages()
      ..history = [
        msg(id: 1, senderId: 42, message: 'incoming'),
        msg(id: 2, senderId: 1, message: 'mine', isRead: false),
      ];

    await pumpChat(tester, fake);
    await tester.pump();

    await tester.longPress(find.text('mine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete for me'));
    await tester.pumpAndSettle();

    expect(fake.deletedMessages, [(2, 'me')]);
    expect(find.text('mine'), findsNothing);
    expect(find.text('incoming'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  group('live WebSocket frames', () {
    testWidgets('message frame appends a bubble instantly', (tester) async {
      final fake = FakeMessages()
        ..history = [msg(id: 1, senderId: 42, message: 'hi')];
      final (realtime, _) = await pumpChat(tester, fake);
      await tester.pump();

      realtime.emit(const RealtimeEvent(
        type: 'message',
        data: {
          'conversationId': 7,
          'senderId': 42,
          'messageId': 300,
          'message': 'live ping',
          'timestamp': '2026-08-20T10:00:00+00:00',
        },
      ));
      await tester.pump();

      expect(find.text('live ping'), findsOneWidget);
      // Regression: a WS-arriving message must merge into the thread, not replace it.
      expect(find.text('hi'), findsOneWidget,
          reason: 'history must survive a live inbound message');
      expect(fake.lastMarkedRead, 7);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('message frame for another conversation is ignored',
        (tester) async {
      final fake = FakeMessages()
        ..history = [msg(id: 1, senderId: 42, message: 'hi')];
      final (realtime, _) = await pumpChat(tester, fake);
      await tester.pump();

      realtime.emit(const RealtimeEvent(
        type: 'message',
        data: {'conversationId': 99, 'senderId': 42, 'messageId': 301, 'message': 'nope'},
      ));
      await tester.pump();

      expect(find.text('nope'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('messageId 0 (legacy publisher) is ignored, poll reconciles',
        (tester) async {
      final fake = FakeMessages()
        ..history = [msg(id: 1, senderId: 42, message: 'hi')];
      final (realtime, _) = await pumpChat(tester, fake);
      await tester.pump();

      // Old send_message.php fanned out messageId 0; accepting it would collapse the dedupe.
      realtime.emit(const RealtimeEvent(
        type: 'message',
        data: {'conversationId': 7, 'senderId': 42, 'messageId': 0, 'message': 'ghost'},
      ));
      await tester.pump();

      expect(find.text('ghost'), findsNothing);
      // mark-read already ran on load (inbound id 1); the id-0 frame must not add another.
      expect(fake.markReadCalls, 1, reason: 'no mark-read for id 0');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('read frame flips every sent receipt to seen', (tester) async {
      final fake = FakeMessages()
        ..history = [
          msg(id: 1, senderId: 42, message: 'hi'),
          msg(id: 2, senderId: 1, message: 'yo', isRead: false),
          msg(id: 3, senderId: 1, message: 'also yo', isRead: false),
        ];
      final (realtime, _) = await pumpChat(tester, fake);
      await tester.pump();

      realtime.emit(const RealtimeEvent(
        type: 'read',
        data: {'conversationId': 7, 'readerId': 42},
      ));
      await tester.pump();

      final r2 = tester.widget<FaIcon>(receiptIcon(2));
      final r3 = tester.widget<FaIcon>(receiptIcon(3));
      expect(r2.icon!.codePoint, FontAwesomeIcons.checkDouble.codePoint);
      expect(r3.icon!.codePoint, FontAwesomeIcons.checkDouble.codePoint);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('typing frame toggles the indicator; input pings the room',
        (tester) async {
      final fake = FakeMessages()
        ..history = [msg(id: 1, senderId: 42, message: 'hi')];
      final (realtime, _) = await pumpChat(tester, fake);
      await tester.pump();

      realtime.emit(const RealtimeEvent(
          type: 'typing', data: {'conversationId': 7, 'isTyping': true}));
      await tester.pump();
      expect(find.text('Typing...'), findsOneWidget);

      realtime.emit(const RealtimeEvent(
          type: 'typing', data: {'conversationId': 7, 'isTyping': false}));
      await tester.pump();
      expect(find.text('Typing...'), findsNothing);

      // Our own input pings once per burst, stops after 3s (site parity).
      await tester.enterText(find.byType(TextField), 'h');
      expect(realtime.typingFrames, contains((7, true)));
      expect(realtime.typingFrames, isNot(contains((7, false))));

      await tester.pump(const Duration(seconds: 4));
      expect(realtime.typingFrames, contains((7, false)));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('leaving the screen leaves the room', (tester) async {
      final fake = FakeMessages();
      final (realtime, _) = await pumpChat(tester, fake);
      await tester.pump();
      expect(realtime.joined, contains(7));

      await tester.pumpWidget(const SizedBox());
      expect(realtime.left, contains(7));
    });
  });
}
