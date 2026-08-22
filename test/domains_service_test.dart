import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/domains_service.dart';

/// Minimal in-memory session store (no prefs, no binding needed here).
class _Store implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

/// A flat category row exactly as api/v1/domains.php emits it (the board).
Map<String, dynamic> _category({
  int id = 3,
  String name = 'Entertainment',
  String slug = 'entertainment',
  int? parent,
  int displayOrder = 3,
  String? description = 'Movies, music, gaming and more',
  String icon = 'fa-masks-theater',
  String color = '#f59e0b',
  int postCount = 2,
  String? lastPostAt = '2026-08-12 12:00:00',
  String? lastPostAuthor = 'Developer',
  int? lastPostUserId = 1,
}) =>
    {
      'id': id,
      'name': name,
      'slug': slug,
      'parent': parent,
      'display_order': displayOrder,
      'description': description,
      'icon': icon,
      'color': color,
      'post_count': postCount,
      'last_post_at': lastPostAt,
      'last_post_author': lastPostAuthor,
      'last_post_user_id': lastPostUserId,
    };

/// A thread row (the map_post shape + domain extras) as the API emits it.
Map<String, dynamic> _thread({
  int id = 218,
  int authorId = 1,
  String content = 'Hello **world** &amp; friends',
  String createdAt = '2026-08-12 10:32:59',
  int likeCount = 3,
  int commentCount = 2,
  bool userLiked = false,
  String username = 'Developer',
  String? personality = 'INTJ',
  String rank = 'SysOp',
  String domainSlug = 'general',
  String domainName = 'General',
  String? lastReplyAt = '2026-08-12 12:00:00',
}) =>
    {
      'id': id,
      'author_id': authorId,
      'content': content,
      'created_at': createdAt,
      'feed_score': null,
      'like_count': likeCount,
      'comment_count': commentCount,
      'user_liked': userLiked,
      'warning_count': 0,
      'username': username,
      'profile_picture_url': '/public/avatars/dev.png',
      'personality_type': personality,
      'is_active': 'true',
      'rank': rank,
      'image': null,
      'is_owner': false,
      'domain_slug': domainSlug,
      'domain_name': domainName,
      'last_reply_at': lastReplyAt,
    };

void main() {
  group('DomainCategory.fromJson + buildTree', () {
    test('maps every field', () {
      final c = DomainCategory.fromJson(_category());
      expect(c.id, 3);
      expect(c.name, 'Entertainment');
      expect(c.slug, 'entertainment');
      expect(c.parent, isNull);
      expect(c.displayOrder, 3);
      expect(c.description, 'Movies, music, gaming and more');
      expect(c.icon, 'fa-masks-theater');
      expect(c.color, '#f59e0b');
      expect(c.postCount, 2);
      expect(c.lastPostAt, '2026-08-12 12:00:00');
      expect(c.lastPostAuthor, 'Developer');
      expect(c.lastPostUserId, 1);
      expect(c.isRoot, isTrue);
      expect(c.hasChildren, isFalse);
    });

    test('null parent/description/last-activity tolerated', () {
      final c = DomainCategory.fromJson(_category(
          parent: 3,
          description: null,
          lastPostAt: null,
          lastPostAuthor: null,
          lastPostUserId: null));
      expect(c.parent, 3);
      expect(c.description, isNull);
      expect(c.lastPostAt, isNull);
      expect(c.lastPostAuthor, isNull);
      expect(c.lastPostUserId, isNull);
      expect(c.isRoot, isFalse);
    });

    test('buildTree nests children under roots, orphans promoted', () {
      final flat = [
        DomainCategory.fromJson(_category(id: 3, name: 'Entertainment')),
        DomainCategory.fromJson(_category(
            id: 5, name: 'Movies & TV', parent: 3, slug: 'movies-tv')),
        DomainCategory.fromJson(_category(
            id: 6, name: 'Music', parent: 3, slug: 'music')),
        // Orphan: parent id does not exist → treated as a root.
        DomainCategory.fromJson(_category(
            id: 99, name: 'Orphan', parent: 404, slug: 'orphan')),
      ];
      final roots = DomainCategory.buildTree(flat);
      expect(roots, hasLength(2));
      final entertainment = roots.firstWhere((r) => r.id == 3);
      expect(entertainment.children, hasLength(2));
      expect(entertainment.children.map((c) => c.name),
          containsAll(['Movies & TV', 'Music']));
      expect(roots.any((r) => r.id == 99), isTrue);
    });
  });

  group('DomainThread.fromJson', () {
    test('parses the post + domain context', () {
      final t = DomainThread.fromJson(_thread());
      expect(t.post.id, 218);
      // Content arrives htmlspecialchars-encoded — Post decodes once.
      expect(t.post.content, "Hello **world** & friends");
      expect(t.post.username, 'Developer');
      expect(t.post.rank, 'SysOp');
      expect(t.domainSlug, 'general');
      expect(t.domainName, 'General');
      expect(t.lastReplyAt, '2026-08-12 12:00:00');
    });

    test('null last_reply_at tolerated', () {
      final t = DomainThread.fromJson(_thread(lastReplyAt: null));
      expect(t.lastReplyAt, isNull);
    });
  });

  group('DomainThreadPage.fromJson', () {
    test('parses category + threads + pagination', () {
      final page = DomainThreadPage.fromJson({
        'success': true,
        'category': _category(),
        'threads': [_thread(), _thread(id: 210, commentCount: 0)],
        'total': 12,
        'has_more': true,
      });
      expect(page.category.name, 'Entertainment');
      expect(page.threads, hasLength(2));
      expect(page.total, 12);
      expect(page.hasMore, isTrue);
    });

    test('empty payload yields empty page, hasMore false', () {
      final page = DomainThreadPage.fromJson({
        'success': true,
        'category': _category(),
        'threads': <dynamic>[],
        'total': 0,
        'has_more': false,
      });
      expect(page.threads, isEmpty);
      expect(page.total, 0);
      expect(page.hasMore, isFalse);
      expect(page.category.id, 3);
    });
  });

  group('DomainThreadDetail.fromJson', () {
    test('parses the post + breadcrumb trail', () {
      final detail = DomainThreadDetail.fromJson({
        'success': true,
        'post': _thread(),
        'breadcrumb': [
          {'id': 1, 'name': 'General', 'slug': 'general', 'parent': null},
          {'id': 2, 'name': 'Sub', 'slug': 'sub', 'parent': 1},
        ],
      });
      expect(detail.post.id, 218);
      expect(detail.breadcrumb, hasLength(2));
      expect(detail.breadcrumb.first.name, 'General');
      expect(detail.breadcrumb.last.slug, 'sub');
    });

    test('missing post throws', () {
      expect(
        () => DomainThreadDetail.fromJson({'success': true}),
        throwsA(isA<ApiException>()),
      );
    });
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

    test('board() hits /api/v1/domains and parses flat rows', () async {
      final seen = <String>[];
      await serve((req) async {
        seen.add(req.uri.toString());
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'success': true,
          'domains': [_category(), _category(id: 5, parent: 3)],
        }));
        await req.response.close();
      });

      final domains = await DomainsService(api).board();
      expect(seen, ['/api/v1/domains']);
      expect(domains, hasLength(2));
      expect(domains.first.name, 'Entertainment');
    });

    test('threads() sends category_id/limit/offset and parses the page',
        () async {
      final seen = <String>[];
      await serve((req) async {
        seen.add(req.uri.toString());
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'success': true,
          'category': _category(),
          'threads': [_thread()],
          'total': 1,
          'has_more': false,
        }));
        await req.response.close();
      });

      final page =
          await DomainsService(api).threads(3, limit: 20, offset: 0);
      expect(seen, ['/api/v1/domains?category_id=3&limit=20&offset=0']);
      expect(page.threads, hasLength(1));
      expect(page.threads.first.domainName, 'General');
    });

    test('thread() sends post_id and parses post + breadcrumb', () async {
      final seen = <String>[];
      await serve((req) async {
        seen.add(req.uri.toString());
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'success': true,
          'post': _thread(),
          'breadcrumb': [
            {'id': 1, 'name': 'General', 'slug': 'general', 'parent': null},
          ],
        }));
        await req.response.close();
      });

      final detail = await DomainsService(api).thread(218);
      expect(seen, ['/api/v1/domains?post_id=218']);
      expect(detail.post.id, 218);
      expect(detail.breadcrumb.single.name, 'General');
    });

    test('404 surfaces as ApiException', () async {
      await serve((req) async {
        req.response.statusCode = 404;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'error': 'Thread not found'}));
        await req.response.close();
      });

      expect(
        () => DomainsService(api).thread(99999),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 404)
            .having((e) => e.message, 'message', 'Thread not found')),
      );
    });
  });
}
