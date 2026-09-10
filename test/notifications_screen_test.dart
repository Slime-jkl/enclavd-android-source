import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/notifications_service.dart';
import 'package:enclavd/screens/notifications_screen.dart';
import 'package:enclavd/services/message_notifications.dart';
import 'package:enclavd/services/realtime_service.dart';
import 'package:enclavd/services/social_notification_source.dart';
import 'package:enclavd/services/social_notifications.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/enclavd_avatar.dart';

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

ApiClient _client() =>
    ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com');

class _FakeNotifications extends NotificationsService {
  _FakeNotifications() : super(_client());

  List<AppNotification> answer = const [];
  List<AppNotification> older = const [];
  final List<int> beforeIds = <int>[];
  int markAllReadCalls = 0;

  @override
  Future<NotificationPage> fetch({int beforeId = 0, int limit = 20}) async {
    beforeIds.add(beforeId);
    if (beforeId > 0) {
      return NotificationPage(items: older, hasMore: false);
    }
    return NotificationPage(
      items: answer,
      hasMore: older.isNotEmpty,
      lastId: answer.isEmpty ? 0 : answer.last.id,
    );
  }

  @override
  Future<void> markAllRead() async => markAllReadCalls++;
}

class _FakeNotifier implements LocalNotifier {
  final List<int> cancelled = <int>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestPermission() async {}

  @override
  Future<bool> areNotificationsEnabled() async => true;

  @override
  Future<bool> openAppNotificationSettings() async => true;

  @override
  Future<void> cancelNotification(int notificationId) async =>
      cancelled.add(notificationId);

  @override
  Future<String?> launchPayload() async => null;

  @override
  Future<void> showMessageNotification({
    required int notificationId,
    required String senderName,
    required String message,
    required int conversationId,
    String? avatarPath,
  }) async {}

  @override
  Future<void> showSocialNotification({
    required int notificationId,
    required String title,
    required String body,
    required String payload,
  }) async {}
}

AppNotification _bundle(
  int id, {
  String type = 'post-like',
  String message = 'alice liked your post',
}) =>
    AppNotification(
      id: id,
      message: message,
      contentType: type,
      contentId: 5,
      commentId: 0,
      isDomain: false,
      fromUserId: 7,
      fromUsername: 'alice',
      fromUserAvatar: '/public/avatars/alice.png',
      actorCount: 1,
      read: false,
      createdAt: '2026-08-21 09:30:00',
      other: '',
      postPreviewContent: 'preview',
      postPreviewImage: '',
    );

/// FaIcon stores FaIconData as plain IconData; finders must compare code points (11.x quirk).
Finder findFa(FaIconData icon) => find.byWidgetPredicate((w) =>
    w is FaIcon && w.icon != null && w.icon!.codePoint == icon.codePoint);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SocialNotifications.instance = null;
  });

  tearDown(() => SocialNotifications.instance = null);

  testWidgets('opening the drawer drops the tray copies of what it lists',
      (tester) async {
    final notifier = _FakeNotifier();
    SocialNotifications.instance = SocialNotifications(
      notifier: notifier,
      notificationsFactory: () async => _FakeNotifications(),
    );
    final notifications = _FakeNotifications()..answer = [_bundle(12)];

    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(light: false),
      home: NotificationsScreen(
        notifications: notifications,
        realtime: RealtimeService(_client()),
      ),
    ));
    // Bounded pumps: an avatar shimmer may still be animating, and
    // pumpAndSettle never settles while one is on screen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('alice liked your post'), findsOneWidget);
    expect(notifications.markAllReadCalls, 1);
    expect(notifier.cancelled, [
      SocialNotificationSource.notificationIdOffset + 5,
    ], reason: 'the alert sits in the drawer now, so its tray copy goes');
  });

  testWidgets('the row leads with its type icon and keeps the avatar bare',
      (tester) async {
    final notifications = _FakeNotifications()
      ..answer = [
        _bundle(12, type: 'follow', message: 'alice followed you'),
        _bundle(9,
            type: 'comment-mention', message: 'bob mentioned you in a comment'),
      ];

    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(light: false),
      home: NotificationsScreen(
        notifications: notifications,
        realtime: RealtimeService(_client()),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(findFa(FontAwesomeIcons.userPlus), findsOneWidget);
    expect(findFa(FontAwesomeIcons.at), findsOneWidget);
    expect(find.byType(EnclavdAvatar), findsNWidgets(2),
        reason: 'the avatar is the only leading element again');
  });

  testWidgets('reaching the bottom appends the next page', (tester) async {
    final notifications = _FakeNotifications()
      ..answer = [for (var i = 1; i <= 20; i++) _bundle(i)]
      ..older = [
        _bundle(1, type: 'comment-reply', message: 'carol replied to your comment'),
      ];

    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(light: false),
      home: NotificationsScreen(
        notifications: notifications,
        realtime: RealtimeService(_client()),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Page one only: the older notice is not on screen yet.
    expect(notifications.beforeIds, [0]);
    expect(find.text('carol replied to your comment'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(notifications.beforeIds, [0, 20],
        reason: 'the cursor is the oldest bundle of the page before');
    expect(find.text('carol replied to your comment'), findsOneWidget,
        reason: 'paging runs all the way back to the oldest notice');
  });
}
