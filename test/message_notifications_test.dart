import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/messages_service.dart';
import 'package:enclavd/services/message_notifications.dart';

class FakeNotifier implements LocalNotifier {
  int initializeCalls = 0;
  int permissionRequests = 0;
  int shown = 0;
  int? lastNotificationId;
  String? lastSender;
  String? lastBody;
  int? lastConversationId;

  @override
  Future<void> initialize() async => initializeCalls++;

  @override
  Future<void> requestPermission() async => permissionRequests++;

  @override
  Future<void> showMessageNotification({
    required int notificationId,
    required String senderName,
    required String message,
    required int conversationId,
  }) async {
    shown++;
    lastNotificationId = notificationId;
    lastSender = senderName;
    lastBody = message;
    lastConversationId = conversationId;
  }
}

class FakeMessages extends MessagesService {
  FakeMessages() : super(_noopClient());

  static ApiClient _noopClient() => ApiClient(
        store: _NoopStore(),
        apiBaseUrl: 'https://example.com',
      );

  List<UnreadMessage> unreadAnswer = [];
  bool failFetch = false;
  final List<String> sentTexts = [];
  int? lastSentConversation;

  @override
  Future<List<UnreadMessage>> unreadMessages() async {
    if (failFetch) throw const ApiException('boom');
    return unreadAnswer;
  }

  @override
  Future<int> send(int conversationId, String text) async {
    sentTexts.add(text);
    lastSentConversation = conversationId;
    return 500 + sentTexts.length;
  }
}

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

UnreadMessage unread({
  required int id,
  required int conv,
  required String sender,
  required String text,
}) =>
    UnreadMessage(
      messageId: id,
      conversationId: conv,
      senderId: 42,
      senderName: sender,
      senderAvatar: '/a.png',
      message: text,
      createdAt: '2026-08-20 10:00:00',
    );

MessageNotifications buildService(FakeNotifier notifier, FakeMessages fake) =>
    MessageNotifications(
      notifier: notifier,
      messagesFactory: () async => fake,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MessageNotifications.instance = null; // test isolation
  });

  test('ping while reading messages in the foreground is suppressed',
      () async {
    final fake = FakeMessages()
      ..unreadAnswer = [unread(id: 100, conv: 5, sender: 'Alice', text: 'hey')];
    final notifier = FakeNotifier();
    final service = buildService(notifier, fake);
    service.setMessagesOpen(true);

    await service.handleUnreadPing();

    expect(notifier.shown, 0, reason: 'user is looking at the thread');
  });

  test('ping while the app is minimized still notifies', () async {
    final fake = FakeMessages()
      ..unreadAnswer = [unread(id: 100, conv: 5, sender: 'Alice', text: 'hey')];
    final notifier = FakeNotifier();
    final service = buildService(notifier, fake);
    service.setMessagesOpen(true);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);

    await service.handleUnreadPing();

    expect(notifier.shown, 1, reason: 'minimized = not reading');
    expect(notifier.lastSender, 'Alice');
    expect(notifier.lastBody, 'hey');
    expect(notifier.lastConversationId, 5);
    expect(notifier.lastNotificationId, 5, reason: 'per-conversation id');
  });

  test('ping on the feed (messages screen closed) notifies', () async {
    final fake = FakeMessages()
      ..unreadAnswer = [unread(id: 100, conv: 5, sender: 'Alice', text: 'hey')];
    final notifier = FakeNotifier();
    final service = buildService(notifier, fake);

    await service.handleUnreadPing();

    expect(notifier.shown, 1);
  });

  test('the same newest message is never re-notified', () async {
    final fake = FakeMessages()
      ..unreadAnswer = [unread(id: 100, conv: 5, sender: 'Alice', text: 'hey')];
    final notifier = FakeNotifier();
    final service = buildService(notifier, fake);

    await service.handleUnreadPing();
    await service.handleUnreadPing(); // same ping again (SSE re-delivery)

    expect(notifier.shown, 1, reason: 'deduped by newest message id');
  });

  test('a newer message notifies again', () async {
    final notifier = FakeNotifier();
    final fake = FakeMessages()
      ..unreadAnswer = [unread(id: 100, conv: 5, sender: 'Alice', text: 'one')];
    final service = buildService(notifier, fake);

    await service.handleUnreadPing();
    fake.unreadAnswer = [
      unread(id: 101, conv: 5, sender: 'Alice', text: 'two'),
      unread(id: 100, conv: 5, sender: 'Alice', text: 'one'),
    ];
    await service.handleUnreadPing();

    expect(notifier.shown, 2, reason: 'new message id = new notification');
    expect(notifier.lastBody, 'two');
  });

  test('the master toggle suppresses everything and persists', () async {
    final fake = FakeMessages()
      ..unreadAnswer = [unread(id: 100, conv: 5, sender: 'Alice', text: 'hey')];
    final notifier = FakeNotifier();
    final service = buildService(notifier, fake);

    await service.setEnabled(false);
    await service.handleUnreadPing();

    expect(notifier.shown, 0, reason: 'toggle off');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(MessageNotifications.enabledPrefsKey), false);

    await service.setEnabled(true);
    expect(notifier.permissionRequests, greaterThanOrEqualTo(1),
        reason: 're-enabling re-arms the permission');
  });

  test('reply action posts the text to the conversation', () async {
    final fake = FakeMessages();
    final notifier = FakeNotifier();
    final service = buildService(notifier, fake);

    await service.handleResponse(const NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      actionId: MessageNotifications.replyActionId,
      input: '  hello bob  ',
      payload: 'c:5',
    ));

    expect(fake.sentTexts, ['hello bob'], reason: 'trimmed reply text');
    expect(fake.lastSentConversation, 5);
  });

  test('reply with empty input or bad payload does nothing', () async {
    final fake = FakeMessages();
    final service = buildService(FakeNotifier(), fake);

    await service.handleResponse(const NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      actionId: MessageNotifications.replyActionId,
      input: '   ',
      payload: 'c:5',
    ));
    await service.handleResponse(const NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      actionId: MessageNotifications.replyActionId,
      input: 'hi',
      payload: 'nope',
    ));
    await service.handleResponse(const NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      actionId: 'some-other-action',
      input: 'hi',
      payload: 'c:5',
    ));

    expect(fake.sentTexts, isEmpty);
  });

  test('a failing unread fetch is silent (no notification, no crash)',
      () async {
    final fake = FakeMessages()..failFetch = true;
    final notifier = FakeNotifier();
    final service = buildService(notifier, fake);

    await service.handleUnreadPing();

    expect(notifier.shown, 0);
  });

  test('the notification payload carries the conversation id', () {
    expect(MessageNotifications.conversationIdFromPayload('c:12'), 12);
    expect(MessageNotifications.conversationIdFromPayload('c:0'), 0);
    expect(MessageNotifications.conversationIdFromPayload(null), isNull);
    expect(MessageNotifications.conversationIdFromPayload('12'), isNull);
    expect(MessageNotifications.conversationIdFromPayload('c:x'), isNull);
  });
}
