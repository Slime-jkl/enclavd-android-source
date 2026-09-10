import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/notifications_service.dart';
import 'package:enclavd/services/message_notifications.dart';
import 'package:enclavd/services/social_notification_source.dart';
import 'package:enclavd/services/social_notifications.dart';

class FakeNotifier implements LocalNotifier {
  int shown = 0;
  int? lastNotificationId;
  String? lastTitle;
  String? lastBody;
  String? lastPayload;
  int permissionRequests = 0;
  final List<int> cancelled = <int>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestPermission() async => permissionRequests++;

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
  }) async {
    shown++;
    lastNotificationId = notificationId;
    lastTitle = title;
    lastBody = body;
    lastPayload = payload;
  }
}

class FakeNotifications extends NotificationsService {
  FakeNotifications() : super(_noopClient());

  static ApiClient _noopClient() => ApiClient(
        store: _NoopStore(),
        apiBaseUrl: 'https://example.com',
      );

  List<AppNotification> answer = [];
  bool failFetch = false;
  int markAllReadCalls = 0;

  @override
  Future<List<AppNotification>> list() async {
    if (failFetch) throw Exception('boom');
    return answer;
  }

  @override
  Future<void> markAllRead() async => markAllReadCalls++;
}

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

AppNotification _bundle(int id) => AppNotification(
      id: id,
      message: 'alice liked your post',
      contentType: 'post-like',
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

SocialNotifications buildService(FakeNotifier notifier, FakeNotifications fake) =>
    SocialNotifications(
      notifier: notifier,
      notificationsFactory: () async => fake,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SocialNotifications.instance = null;
  });

  tearDown(() {
    SocialNotifications.instance = null;
  });

  test('a ping shows each new bundle once, then dedupes', () async {
    final notifier = FakeNotifier();
    final fake = FakeNotifications()
      ..answer = [_bundle(12), _bundle(13)];
    final service = buildService(notifier, fake);
    await service.init();

    await service.handleNotificationPing();
    expect(notifier.shown, 2);
    expect(notifier.lastNotificationId,
        SocialNotificationSource.notificationIdOffset + 5);
    expect(notifier.lastTitle, 'alice liked your post');
    expect(notifier.lastPayload, 'n:13',
        reason: 'the newest bundle: what a swipe reports back');

    // Same bundles again (SSE ping + poll + worker tick): no re-show.
    await service.handleNotificationPing();
    expect(notifier.shown, 2);

    // A NEW bundle on the same post is a new event -> notifies again.
    fake.answer = [_bundle(12), _bundle(13), _bundle(15)];
    await service.handleNotificationPing();
    expect(notifier.shown, 3);
  });

  test('drawer open + app active suppresses the device alert', () async {
    final notifier = FakeNotifier();
    final fake = FakeNotifications()..answer = [_bundle(12)];
    final service = buildService(notifier, fake);
    await service.init();

    service.setDrawerOpen(true);
    await service.handleNotificationPing();
    expect(notifier.shown, 0, reason: 'the user is looking at the drawer');

    service.setDrawerOpen(false);
    await service.handleNotificationPing();
    expect(notifier.shown, 1);
  });

  test('master toggle off suppresses; re-enabling re-arms', () async {
    final notifier = FakeNotifier();
    final fake = FakeNotifications()..answer = [_bundle(12)];
    final service = buildService(notifier, fake);
    await service.init();

    await service.setEnabled(false);
    await service.handleNotificationPing();
    expect(notifier.shown, 0);

    await service.setEnabled(true);
    expect(notifier.permissionRequests, 1,
        reason: 're-enabling re-requests the OS permission');
    await service.handleNotificationPing();
    expect(notifier.shown, 1);
  });

  test('opening the drawer drops the tray copies of the alerts', () async {
    final notifier = FakeNotifier();
    final service = buildService(notifier, FakeNotifications());

    await service.clearTray([_bundle(12), _bundle(13)]);
    expect(notifier.cancelled, [
      SocialNotificationSource.notificationIdOffset + 5,
      SocialNotificationSource.notificationIdOffset + 5,
    ], reason: 'both bundles ride the same post id, so the same tray entry');

    // A standalone follow: its own bundle id, not the post's.
    await service.clearTray([
      const AppNotification(
        id: 21,
        message: 'bob followed you',
        contentType: 'follow',
        contentId: 0,
        commentId: 0,
        isDomain: false,
        fromUserId: 8,
        fromUsername: 'bob',
        fromUserAvatar: '/assets/default-avatar.png',
        actorCount: 1,
        read: true,
        createdAt: '2026-08-21 09:30:00',
        other: '',
        postPreviewContent: '',
        postPreviewImage: '',
      ),
    ]);
    expect(notifier.cancelled.last,
        SocialNotificationSource.notificationIdOffset + 21);
  });

  test('a failed fetch is silent and the next ping retries', () async {
    final notifier = FakeNotifier();
    final fake = FakeNotifications()..failFetch = true;
    final service = buildService(notifier, fake);
    await service.init();

    await service.handleNotificationPing();
    expect(notifier.shown, 0);

    fake
      ..failFetch = false
      ..answer = [_bundle(12)];
    await service.handleNotificationPing();
    expect(notifier.shown, 1);
  });
}
