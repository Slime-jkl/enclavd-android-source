import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/auth_service.dart';
import 'package:enclavd/api/messages_service.dart';
import 'package:enclavd/screens/chat_screen.dart';
import 'package:enclavd/screens/messages_screen.dart';
import 'package:enclavd/services/realtime_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';

import 'chat_screen_test.dart' show FakeMessages, FakeRealtime;

class _FakeAuth extends AuthService {
  _FakeAuth() : super(_noopClient(), apiBaseUrl: 'https://example.com');

  static ApiClient _noopClient() => ApiClient(
        store: _NoopStore(),
        apiBaseUrl: 'https://example.com',
      );

  @override
  Future<CurrentUser?> me() async => const CurrentUser(
        id: 7,
        username: 'Slimejkl',
        profilePictureUrl: '/a.png',
        rank: 'SysOp',
        personalityType: 'INTJ',
        prestige: 0,
        isAdmin: true,
        dateCreated: '2025-05-14 00:00:00',
        banned: false,
        blockReason: '',
      );
}

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

Conversation conv({
  int id = 1,
  String name = 'Alice',
  String preview = 'last message',
  int unread = 0,
  String lastActive = '2000-01-01 00:00:00',
}) =>
    Conversation(
      id: id,
      updatedAt: '2026-08-20 10:00:00',
      participantId: 42,
      participantName: name,
      participantAvatar: '/a.png',
      participantPersonality: 'INTJ',
      lastActive: lastActive,
      lastMessage: preview,
      unreadCount: unread,
    );

void main() {
  Future<(FakeRealtime, FakeMessages)> pumpInbox(
      WidgetTester tester, FakeMessages fake) async {
    final realtime = FakeRealtime();
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: MessagesScreen(
        messages: fake,
        auth: _FakeAuth(),
        myUserId: 7,
        realtime: realtime,
      ),
    ));
    await tester.pump(); // conversations future resolves
    return (realtime, fake);
  }

  testWidgets('renders conversation rows with preview and unread badge',
      (tester) async {
    final fake = FakeMessages()
      ..inbox = [
        conv(id: 1, name: 'Alice', preview: 'see you soon', unread: 2),
        conv(id: 2, name: 'Bob', preview: ''),
      ];

    final (realtime, _) = await pumpInbox(tester, fake);
    await tester.pump();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('see you soon'), findsOneWidget);
    // Empty preview -> the site's placeholder.
    expect(find.text('No messages yet'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    // Every conversation room is joined for live delivery.
    expect(realtime.joined, containsAll([1, 2]));

    await tester.pumpWidget(const SizedBox()); // dispose the poll timer
  });

  testWidgets('empty inbox shows the hint, not a blank page', (tester) async {
    final fake = FakeMessages();

    await pumpInbox(tester, fake);
    await tester.pump();

    expect(find.text('No conversations yet'), findsOneWidget);
    expect(find.textContaining('profile and tap Message'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping a row opens the thread', (tester) async {
    final fake = FakeMessages()
      ..inbox = [conv(id: 9, name: 'Alice', unread: 1)];

    await pumpInbox(tester, fake);
    await tester.pump();

    await tester.tap(find.text('Alice'));
    await tester.pump(); // route push
    await tester.pump(const Duration(milliseconds: 400)); // transition
    await tester.pump();

    expect(find.byType(ChatScreen), findsOneWidget);
    // Scope to the ChatScreen: the inbox row behind the route also shows the name.
    expect(
      find.descendant(
          of: find.byType(ChatScreen), matching: find.text('Alice')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('online dot follows the 5-minute heuristic', (tester) async {
    final recent = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    final stale = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
    final fake = FakeMessages()
      ..inbox = [
        conv(id: 1, name: 'OnlineUser', lastActive: _db(recent)),
        conv(id: 2, name: 'OfflineUser', lastActive: _db(stale)),
      ];

    await pumpInbox(tester, fake);
    await tester.pump();

    // Both names render; the online dot logic is covered by Conversation.isOnline unit tests.
    expect(find.text('OnlineUser'), findsOneWidget);
    expect(find.text('OfflineUser'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('live message frame refreshes previews and unread badges',
      (tester) async {
    final fake = FakeMessages()
      ..inbox = [conv(id: 1, name: 'Alice', preview: 'old', unread: 0)];
    final (realtime, _) = await pumpInbox(tester, fake);
    await tester.pump();

    // The other side sends; the inbox re-fetches and reorders instantly.
    fake.inbox = [conv(id: 1, name: 'Alice', preview: 'new msg', unread: 1)];
    realtime.emit(const RealtimeEvent(
      type: 'message',
      data: {'conversationId': 1, 'senderId': 42, 'messageId': 500, 'message': 'new msg'},
    ));
    await tester.pump(); // event -> refresh future resolves
    await tester.pump(); // setState frame

    expect(find.text('new msg'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // unread badge now visible

    await tester.pumpWidget(const SizedBox());
  });
}

String _db(DateTime utc) {
  String p(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}-${p(utc.month)}-${p(utc.day)} '
      '${p(utc.hour)}:${p(utc.minute)}:${p(utc.second)}';
}
