import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/notifications_service.dart';
import 'package:enclavd/services/notification_source.dart';
import 'package:enclavd/services/social_notification_source.dart';
import 'package:enclavd/services/social_notifications.dart';

AppNotification _bundle({
  int id = 12,
  String type = 'post-like',
  int contentId = 5,
  bool read = false,
}) =>
    AppNotification(
      id: id,
      message: 'alice liked your post',
      contentType: type,
      contentId: contentId,
      fromUserId: 7,
      fromUsername: 'alice',
      fromUserAvatar: '/public/avatars/alice.png',
      actorCount: 1,
      read: read,
      createdAt: '2026-08-21 09:30:00',
      other: '',
      postPreviewContent: 'I&#039;m building a new thing',
      postPreviewImage: 'gallery-1.jpg',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('candidatesFrom (the shared pure function)', () {
    test('one candidate per unread bundle, read ones skipped', () {
      final items = [
        _bundle(id: 12, type: 'post-like'),
        _bundle(id: 13, type: 'follow'),
        _bundle(id: 14, type: 'post-comment', read: true),
      ];
      final candidates = SocialNotificationSource.candidatesFrom(items);
      expect(candidates, hasLength(2));
      expect(candidates[0].key, 'post:post-like:12');
      expect(candidates[1].key, 'post:follow:13');
    });

    test('kind is social and ids are namespaced above messages', () {
      final candidates =
          SocialNotificationSource.candidatesFrom([_bundle(id: 12)]);
      expect(candidates.single.kind, CandidateKind.social);
      expect(candidates.single.notificationId,
          SocialNotificationSource.notificationIdOffset + 5,
          reason: 'post id, offset past the message/conversation id space');
    });

    test('a NEW bundle on the same post re-notifies (new key)', () {
      // Same post, new actor -> the server emits a NEW bundle (new max id).
      final first = SocialNotificationSource.candidatesFrom([_bundle(id: 12)]);
      final second =
          SocialNotificationSource.candidatesFrom([_bundle(id: 15)]);
      expect(first.single.key, isNot(second.single.key),
          reason: 'a new like is a new event and must notify again');
      expect(first.single.notificationId, second.single.notificationId,
          reason: 'but the OS notification REPLACES the post\'s older one');
    });

    test('body is the decoded preview, trimmed to 120 chars', () {
      final long = _bundle(id: 12).copyWithPreview('x' * 300);
      final candidates = SocialNotificationSource.candidatesFrom([long]);
      expect(candidates.single.body, hasLength(123)); // 120 + "..."
      expect(candidates.single.body, endsWith('...'));

      final plain = _bundle(id: 13).copyWithPreview('plain');
      expect(SocialNotificationSource.candidatesFrom([plain]).single.body,
          'plain');
    });

    test('id <= 0 bundles are rejected (no stable identity)', () {
      expect(SocialNotificationSource.candidatesFrom([_bundle(id: 0)]),
          isEmpty);
    });
  });

  group('check() gating (worker context)', () {
    test('master toggle off -> quiet', () async {
      SharedPreferences.setMockInitialValues(
          {SocialNotifications.enabledPrefsKey: false});
      final prefs = await SharedPreferences.getInstance();
      final source = SocialNotificationSource(
          fetcher: (_) async => [_bundle(id: 12)]);
      final ctx = SourceContext(api: _api(), prefs: prefs);
      expect(await source.check(ctx), isEmpty);
    });

    test('drawer open -> quiet', () async {
      SharedPreferences.setMockInitialValues(
          {SocialNotificationSource.drawerOpenPrefsKey: true});
      final prefs = await SharedPreferences.getInstance();
      final source = SocialNotificationSource(
          fetcher: (_) async => [_bundle(id: 12)]);
      expect(await source.check(SourceContext(api: _api(), prefs: prefs)),
          isEmpty,
          reason: 'open AND app active (default) = the user is looking');
    });

    test('drawer open but app MINIMIZED -> NOT quiet (must still alert)',
        () async {
      SharedPreferences.setMockInitialValues({
        SocialNotificationSource.drawerOpenPrefsKey: true,
        SocialNotificationSource.appActivePrefsKey: false,
      });
      final prefs = await SharedPreferences.getInstance();
      final source = SocialNotificationSource(
          fetcher: (_) async => [_bundle(id: 12)]);
      final candidates =
          await source.check(SourceContext(api: _api(), prefs: prefs));
      expect(candidates, isNotEmpty,
          reason: 'minimized with the drawer open must still notify');
    });

    test('fetcher failure -> quiet, never throws', () async {
      final prefs = await SharedPreferences.getInstance();
      final source = SocialNotificationSource(
          fetcher: (_) async => throw Exception('dead session'));
      expect(await source.check(SourceContext(api: _api(), prefs: prefs)),
          isEmpty);
    });

    test('default path builds candidates from the context client', () async {
      final prefs = await SharedPreferences.getInstance();
      final source = SocialNotificationSource(
          fetcher: (api) async => [_bundle(id: 12)]);
      final ctx = SourceContext(api: _api(), prefs: prefs);
      final candidates = await source.check(ctx);
      expect(candidates.single.key, 'post:post-like:12');
    });
  });
}

ApiClient _api() => ApiClient(
      store: _NoopStore(),
      apiBaseUrl: 'https://example.com',
    );

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

extension on AppNotification {
  AppNotification copyWithPreview(String preview) => AppNotification(
        id: id,
        message: message,
        contentType: contentType,
        contentId: contentId,
        fromUserId: fromUserId,
        fromUsername: fromUsername,
        fromUserAvatar: fromUserAvatar,
        actorCount: actorCount,
        read: read,
        createdAt: createdAt,
        other: other,
        postPreviewContent: preview,
        postPreviewImage: postPreviewImage,
      );
}
