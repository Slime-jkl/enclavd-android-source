import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/articles_service.dart';

class _Store implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

/// A summary row exactly as api/v1/articles.php emits it (cover normalized
/// to a root-relative '/public/articles/...' path).
Map<String, dynamic> _summary({
  int id = 19,
  String slug = 'open-beta-is-now-live',
  String title = 'Open Beta is Now Live',
  String cover = '/public/articles/6a21a3d2311b4.jpg',
  int views = 12085,
  String date = '2026-06-04 16:12:02',
  bool pinned = false,
  String? personality = 'INTJ',
  String? rank = 'SysOp',
}) =>
    {
      'id': id,
      'slug': slug,
      'title': title,
      'cover': cover,
      'views': views,
      'published_date': date,
      'pinned': pinned,
      'author_id': 1,
      'username': 'Developer',
      'profile_picture_url': '/public/avatars/dev.png',
      'personality_type': personality,
      'rank': rank,
    };

/// A full article payload (the detail response's `article` object).
Map<String, dynamic> _article({bool liked = false, int likeCount = 3}) => {
      ..._summary(),
      'content': '<p>We are excited to announce &amp; open the beta.</p>',
      'tags': ['beta', 'release'],
      'like_count': likeCount,
      'liked': liked,
      'related': [
        {
          'id': 18,
          'slug': 'older-post',
          'title': 'Older Post',
          'cover': '',
          'views': 99,
          'published_date': '2026-05-01 10:00:00',
          'pinned': false,
          'author_id': 1,
          'username': 'Developer',
          'profile_picture_url': '/public/avatars/dev.png',
          'personality_type': 'INTJ',
          'rank': 'SysOp',
        },
      ],
    };

void main() {
  group('ArticleSummary.fromJson', () {
    test('maps every field', () {
      final a = ArticleSummary.fromJson(_summary());
      expect(a.id, 19);
      expect(a.slug, 'open-beta-is-now-live');
      expect(a.title, 'Open Beta is Now Live');
      expect(a.cover, '/public/articles/6a21a3d2311b4.jpg');
      expect(a.views, 12085);
      expect(a.publishedDate, '2026-06-04 16:12:02');
      expect(a.pinned, isFalse);
      expect(a.authorUsername, 'Developer');
      expect(a.personalityType, 'INTJ');
      expect(a.rank, 'SysOp');
      expect(a.coverUrl('https://enclavd.com'),
          'https://enclavd.com/public/articles/6a21a3d2311b4.jpg');
      expect(a.avatarUrl('https://enclavd.com'),
          'https://enclavd.com/public/avatars/dev.png');
    });

    test('empty cover yields a null URL; null personality tolerated', () {
      final a = ArticleSummary.fromJson(
          _summary(cover: '', personality: null, rank: null));
      expect(a.coverUrl('https://enclavd.com'), isNull);
      expect(a.personalityType, isNull);
      expect(a.rank, 'Member', reason: 'missing rank falls back to Member');
    });
  });

  group('Article.fromJson', () {
    test('maps content, tags, likes and related', () {
      final a = Article.fromJson(_article(liked: true, likeCount: 7));
      expect(a.content, contains('&amp;'),
          reason: 'content stays encoded exactly as stored - render as HTML');
      expect(a.tags, ['beta', 'release']);
      expect(a.likeCount, 7);
      expect(a.liked, isTrue);
      expect(a.related, hasLength(1));
      expect(a.related.first.slug, 'older-post');
      expect(a.related.first.cover, isEmpty);
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

    test('list() parses pinned and regular sections', () async {
      final seen = <String>[];
      await serve((req) async {
        seen.add(req.uri.toString());
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'success': true,
          'pinned': [_summary(id: 20, pinned: true, title: 'Pinned One')],
          'articles': [_summary()],
        }));
        await req.response.close();
      });

      final feed = await ArticlesService(api).list();
      expect(seen, ['/api/v1/articles']);
      expect(feed.pinned, hasLength(1));
      expect(feed.pinned.first.pinned, isTrue);
      expect(feed.pinned.first.title, 'Pinned One');
      expect(feed.articles, hasLength(1));
      expect(feed.articles.first.slug, 'open-beta-is-now-live');
    });

    test('fetch() sends ?slug= and parses the article', () async {
      final seen = <String>[];
      await serve((req) async {
        seen.add(req.uri.toString());
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'success': true, 'article': _article()}));
        await req.response.close();
      });

      final article = await ArticlesService(api).fetch('open-beta-is-now-live');
      expect(seen, ['/api/v1/articles?slug=open-beta-is-now-live']);
      expect(article.summary.title, 'Open Beta is Now Live');
      expect(article.tags, ['beta', 'release']);
    });

    test('toggleLike() POSTs the CSRF-guarded JSON action', () async {
      final requests = <String>[];
      await serve((req) async {
        requests.add('${req.method} ${req.uri.path}');
        if (req.uri.path == '/feed') {
          // The CSRF token lives in the rendered page meta (header.php).
          req.response.write(
              '<html><head><meta name="csrf-token" content="tok123"></head></html>');
        } else if (req.uri.path == '/api/v1/articles') {
          final body = await utf8.decoder.bind(req).join();
          requests.add('body:$body');
          expect(req.headers.value('X-CSRF-Token'), 'tok123');
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(
              {'success': true, 'liked': true, 'like_count': 4}));
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });

      final (liked, count) = await ArticlesService(api).toggleLike(19);
      expect(requests, contains('POST /api/v1/articles'));
      expect(requests,
          contains('body:{"action":"toggle_like","article_id":19}'));
      expect(liked, isTrue);
      expect(count, 4);
    });

    test('latestId() hits ?latest=1 and parses the max id', () async {
      final seen = <String>[];
      await serve((req) async {
        seen.add(req.uri.toString());
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'success': true, 'latest_id': 27}));
        await req.response.close();
      });

      expect(await ArticlesService(api).latestId(), 27);
      expect(seen, ['/api/v1/articles?latest=1']);
    });
  });
}
