import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/messages_service.dart';
import 'package:enclavd/screens/chat_screen.dart';
import 'package:enclavd/services/realtime_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';

/// Memory-backed MessagesService — widget tests run inside the fake-async
/// zone where real sockets never complete, so answers come from memory.
class FakeMessages extends MessagesService {
  FakeMessages() : super(_noopClient());

  static ApiClient _noopClient() => ApiClient(
        store: _NoopStore(),
        apiBaseUrl: 'https://example.com',
      );

  List<ChatMessage> history = [];
  List<Conversation> inbox = [];
  int? lastMarkedRead;
  int nextMessageId = 100;
  final List<String> sentTexts = [];
  int unreadAnswer = 0;

  @override
  Future<List<Conversation>> conversations() async => inbox;

  @override
  Future<List<ChatMessage>> messages(int conversationId) async => history;

  @override
  Future<void> markRead(int conversationId) async {
    lastMarkedRead = conversationId;
  }

  @override
  Future<int> send(int conversationId, String text) async {
    sentTexts.add(text);
    return nextMessageId++;
  }

  @override
  Future<int> unreadCount() async => unreadAnswer;
}

/// Memory-backed RealtimeService: records join/leave/typing frames and lets
/// tests inject server frames via [emit] (the events stream override keeps
/// production code untouched).
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
}) =>
    ChatMessage(
      id: id,
      conversationId: 7,
      senderId: senderId,
      senderName: senderId == 1 ? 'me' : 'Alice',
      message: message,
      isRead: isRead,
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

    // Opening the thread marked the inbound message read.
    expect(fake.lastMarkedRead, 7);
    // And joined the conversation's live room.
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
    // Input cleared immediately (site behavior).
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
    expect(find.text('• online'), findsOneWidget);

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
      // The new inbound message was marked read server-side.
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

      // Inbound typing → indicator appears; stop frame → disappears.
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
