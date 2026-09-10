import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/notifications_service.dart';
import 'package:enclavd/screens/notifications_screen.dart';
import 'package:enclavd/services/message_notifications.dart';
import 'package:enclavd/services/realtime_service.dart';
import 'package:enclavd/services/social_notification_source.dart';
import 'package:enclavd/services/social_notifications.dart';
import 'package:enclavd/theme/enclavd_theme.dart';

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
  int markAllReadCalls = 0;

  @override
  Future<List<AppNotification>> list() async => answer;

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

AppNotification _bundle(int id) => AppNotification(
      id: id,
      message: 'alice liked your post',
      contentType: 'post-like',
      contentId: 5,
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
}
