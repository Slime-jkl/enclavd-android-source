import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/notifications_service.dart';

/// Minimal in-memory session store (no prefs, no binding needed here).
class _Store implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

/// A real-bundle payload exactly as api/v1/notifications.php emits it.
Map<String, dynamic> _bundle({
  int id = 12,
  String type = 'post-like',
  int contentId = 5,
  bool read = false,
  String username = 'alice',
  int actors = 3,
  String preview = 'I&#039;m building a new thing',
  String image = 'gallery-1.jpg',
}) =>
    {
      'id': id,
      'message': actors > 1
          ? '$username & ${actors - 1} others liked your post'
          : '$username liked your post',
      'content_type': type,
      'content_id': contentId,
      'from_user_id': 7,
      'from_username': username,
      'from_user_avatar': '/public/avatars/alice.png',
      'actor_count': actors,
      'read': read,
      'created_at': '2026-08-21 09:30:00',
      'other': null,
      'post_preview': {
        'content': preview,
        'image_url': image,
      },
    };

void main() {
  test('AppNotification.fromJson maps every bundle field', () {
    final n = AppNotification.fromJson(_bundle());
    expect(n.id, 12);
    expect(n.message, 'alice & 2 others liked your post');
    expect(n.contentType, 'post-like');
    expect(n.contentId, 5);
    expect(n.fromUserId, 7);
    expect(n.fromUsername, 'alice');
    expect(n.actorCount, 3);
    expect(n.read, isFalse);
    expect(n.createdAt, '2026-08-21 09:30:00');
    expect(n.postPreviewContent, 'I&#039;m building a new thing');
    expect(n.postPreviewImage, 'gallery-1.jpg');
    expect(n.isPostAttached, isTrue);
    expect(n.groupId, 5, reason: 'post-attached types group by POST id');
    expect(n.avatarUrl('https://enclavd.com'),
        'https://enclavd.com/public/avatars/alice.png');
    expect(n.previewImageUrl('https://enclavd.com'),
        'https://enclavd.com/public/gallery/gallery-1.jpg',
        reason: 'gallery previews are BARE filenames under /public/gallery/');
  });

  test('standalone types group by bundle id and tolerate missing preview', () {
    final json = _bundle(
      type: 'follow',
      contentId: 0,
      actors: 1,
      preview: '',
      image: '',
    )..remove('post_preview');
    final n = AppNotification.fromJson(json);
    expect(n.isPostAttached, isFalse);
    expect(n.groupId, 12, reason: 'standalone types group by bundle id');
    expect(n.previewImageUrl('https://enclavd.com'), isNull);
    expect(n.postPreviewContent, isEmpty);
  });

  test('read flags and numbers parse from mixed types', () {
    final n = AppNotification.fromJson(_bundle(
      id: 3,
      type: 'comment-mention',
      read: true,
      actors: 1,
    ));
    expect(n.read, isTrue);
    expect(n.isPostAttached, isTrue);
    expect(n.groupId, 5);
  });

  group('over a real local socket', () {
    late HttpServer server;
    late ApiClient api;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      api = ApiClient(
        store: _Store(),
        apiBaseUrl: 'http://127.0.0.1:${server.port}',
      );
    });

    tearDown(() => server.close(force: true));

    Future<void> serve(Future<void> Function(HttpRequest req) handler) async {
      server.listen((req) async {
        try {
          await handler(req);
        } catch (e) {
          req.response.statusCode = 500;
          req.response.write('handler error: $e');
          await req.response.close();
        }
      });
    }

    test('list() sends ?list=1 and parses the bundles', () async {
      final seen = <String>[];
      await serve((req) async {
        seen.add(req.uri.toString());
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'success': true,
          'notifications': [_bundle(), _bundle(id: 13, type: 'follow')],
        }));
        await req.response.close();
      });

      final items = await NotificationsService(api).list();
      expect(seen, ['/api/v1/notifications?list=1']);
      expect(items, hasLength(2));
      expect(items.first.message, contains('alice'));
      expect(items.last.contentType, 'follow');
    });

    test('unreadCount() hits the bare endpoint', () async {
      await serve((req) async {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'unread_count': 4}));
        await req.response.close();
      });
      expect(await NotificationsService(api).unreadCount(), 4);
    });

    test('markAllRead() POSTs the CSRF-guarded action', () async {
      final requests = <String>[];
      await serve((req) async {
        requests.add('${req.method} ${req.uri.path}');
        if (req.uri.path == '/feed') {
          // The CSRF token lives in the rendered page meta (header.php).
          req.response.write(
              '<html><head><meta name="csrf-token" content="tok123"></head></html>');
        } else if (req.uri.path == '/api/v1/notifications') {
          final body = await utf8.decoder.bind(req).join();
          requests.add('body:$body');
          expect(req.headers.value('X-CSRF-Token'), 'tok123');
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({'success': true, 'unread_count': 0}));
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });

      await NotificationsService(api).markAllRead();
      expect(requests, contains('POST /api/v1/notifications'));
      expect(requests, contains('body:{"action":"mark_all_read"}'));
    });
  });
}
