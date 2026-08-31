import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/auth_service.dart';
import 'package:enclavd/api/social_service.dart';

import 'api_client_test.dart' show Harness;

void main() {
  group('postJson + CSRF', () {
    test('fetches CSRF from /feed meta, sends JSON + X-CSRF-Token header',
        () async {
      String? contentType;
      String? csrfHeader;
      String? rawBody;
      var feedHits = 0;

      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          feedHits++;
          Harness.respond(
            req,
            body: '<meta name="csrf-token" content="tok-123">',
          );
        } else if (req.uri.path == '/api/v1/likes') {
          contentType = req.headers.contentType?.mimeType;
          csrfHeader = req.headers.value('x-csrf-token');
          rawBody = await utf8.decoder.bind(req).join();
          Harness.respond(req,
              status: 200,
              body: '{"success":true,"action":"liked","like_count":5}');
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final json = await h.client.postJson('/api/v1/likes', {'post_id': 42});
      expect(json['action'], 'liked');
      expect(contentType, 'application/json');
      expect(csrfHeader, 'tok-123');
      expect(rawBody, '{"post_id":42}');
      // CSRF fetched exactly once and memoized for the session.
      expect(feedHits, 1);

      await h.client.postJson('/api/v1/likes', {'post_id': 43});
      expect(feedHits, 1);

      await h.close();
    });

    test('403 -> refetches token and retries once', () async {
      var feedHits = 0;
      var posts = 0;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          feedHits++;
          Harness.respond(
            req,
            body: '<meta name="csrf-token" content="fresh-tok">',
          );
        } else if (req.uri.path == '/api/v1/likes') {
          posts++;
          if (posts == 1) {
            // Stale cached token -> 403 (token was rotated server-side).
            Harness.respond(req,
                status: 403, body: '{"error":"Invalid CSRF token"}');
          } else {
            Harness.respond(req,
                status: 200,
                body: '{"success":true,"action":"unliked","like_count":4}');
          }
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final json = await h.client.postJson('/api/v1/likes', {'post_id': 1});
      expect(json['action'], 'unliked');
      expect(posts, 2); // original + one retry
      expect(feedHits, 2); // first fetch + refetch after 403

      await h.close();
    });

    test('non-2xx surfaces the server error message', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="tok">');
        } else {
          Harness.respond(req,
              status: 422,
              body: '{"error":"Only prior commenters can be mentioned"}');
        }
      });

      await expectLater(
        h.client.postJson('/api/v1/comments', {'action': 'create'}),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message',
                'Only prior commenters can be mentioned')
            .having((e) => e.status, 'status', 422)),
      );

      await h.close();
    });

    test('clearSession drops the memoized CSRF token', () async {
      final h = await Harness.start((req) async {
        Harness.respond(req, body: '<meta name="csrf-token" content="tok-1">');
      });

      await h.client.getPage('/feed'); // warms the token cache
      // After clear, the next postJson must refetch (no stale token reuse).
      var fetched = 0;
      final h2 = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          fetched++;
          Harness.respond(req,
              body: '<meta name="csrf-token" content="tok-2">');
        } else {
          Harness.respond(req, status: 200, body: '{"ok":true}');
        }
      });

      await h.client.clearSession();
      await h2.client.postJson('/api/v1/whatever', {});
      expect(fetched, 1);

      await h.close();
      await h2.close();
    });
  });

  group('SocialService', () {
    test('toggleLike parses the server response', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
        } else if (req.uri.path == '/api/v1/likes') {
          Harness.respond(req,
              status: 200,
              body: '{"success":true,"action":"unliked","like_count":3}');
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final social = SocialService(h.client);
      final result = await social.toggleLike(99);
      expect(result.liked, isFalse);
      expect(result.action, 'unliked');
      expect(result.likeCount, 3);

      await h.close();
    });

    test('listComments parses a page (comments + total + has_more)', () async {
      final h = await Harness.start((req) async {
        Harness.respond(
          req,
          body: jsonEncode({
            'success': true,
            'comments': [
              {
                'id': 5,
                'post_id': 10,
                'user_id': 2,
                'username': 'ana',
                'profile_picture_url': '/public/avatars/a.jpg',
                'personality_type': 'ENFP',
                'name_color': 'text-amber-600',
                'warning_count': 0,
                'has_warnings': false,
                'created_at': '5m',
                'edited': false,
                'content': 'hello there',
                'is_owner': true,
                'can_moderate': false,
              }
            ],
            'total': 17,
            'has_more': true,
          }),
        );
      });

      final social = SocialService(h.client);
      // Default page = 10 newest-first (the app's load-more seam).
      final page = await social.listComments(10);
      expect(page.comments.length, 1);
      expect(page.total, 17, reason: 'total is the FULL count, not the page');
      expect(page.hasMore, isTrue);
      final c = page.comments.first;
      expect(c.id, 5);
      expect(c.username, 'ana');
      expect(c.content, 'hello there');
      expect(c.createdAt, '5m'); // server already relative-formats
      expect(c.isOwner, isTrue);
      final q = h.requests.last.uri.queryParameters;
      expect(q['limit'], '10');
      expect(q.containsKey('offset'), isFalse);

      await h.close();
    });

    test('listComments forwards asc/limit/offset to the server', () async {
      final h = await Harness.start((req) async {
        Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'comments': <dynamic>[],
              'total': 0,
              'has_more': false,
            }));
      });

      final social = SocialService(h.client);
      final page = await social.listComments(10, asc: true, offset: 20);
      expect(page.comments, isEmpty);
      final q = h.requests.last.uri.queryParameters;
      expect(q['order'], 'asc');
      expect(q['limit'], '10');
      expect(q['offset'], '20');

      await h.close();
    });

    test('createComment returns the comment + new count', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
        } else if (req.uri.path == '/api/v1/comments') {
          Harness.respond(
            req,
            status: 200,
            body: jsonEncode({
              'success': true,
              'message': 'Comment added',
              'comment': {
                'id': 8,
                'post_id': 10,
                'user_id': 1,
                'username': 'me',
                'profile_picture_url': '/assets/default-avatar.png',
                'personality_type': null,
                'name_color': 'text-gray-400',
                'created_at': 'now',
                'content': 'my comment',
                'is_owner': true,
              },
              'comment_count': 4,
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final social = SocialService(h.client);
      final (comment, count) = await social.createComment(10, 'my comment');
      expect(comment.id, 8);
      expect(comment.content, 'my comment');
      expect(count, 4);

      await h.close();
    });

    test('deleteComment returns the new count', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
        } else if (req.uri.path == '/api/v1/comments') {
          Harness.respond(req,
              status: 200, body: '{"success":true,"comment_count":2}');
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final social = SocialService(h.client);
      expect(await social.deleteComment(8, 10), 2);

      await h.close();
    });
  });

  group('SocialService.likers', () {
    test('GETs /api/v1/likes?post_id=N and parses raw liker fields', () async {
      String? query;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/api/v1/likes') {
          query = req.uri.query;
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'likers': [
                {
                  'id': 1,
                  'username': 'Developer',
                  'profile_picture_url': '/public/avatars/a.jpg',
                  'personality_type': 'INTJ',
                  'rank': 'SysOp',
                  'liked_at': 'August 12, 2026 at 10:32 AM',
                },
              ],
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final likers = await SocialService(h.client).likers(42);
      expect(query, 'post_id=42');
      expect(likers, hasLength(1));
      final l = likers.first;
      expect(l.id, 1);
      expect(l.username, 'Developer');
      expect(l.personalityType, 'INTJ');
      expect(l.rank, 'SysOp');
      expect(l.likedAt, 'August 12, 2026 at 10:32 AM');

      await h.close();
    });
  });

  group('SocialService.followSuggestions', () {
    test('GETs /api/v1/suggestions and parses the row fields', () async {
      final h = await Harness.start((req) async {
        Harness.respond(
          req,
          body: jsonEncode({
            'success': true,
            'suggestions': [
              {
                'id': 7,
                'username': 'newbie',
                'profile_picture_url': '/public/avatars/b.jpg',
                'personality_type': 'ENFP',
                'rank': 'Member',
                'is_active': 'true',
                'mutual_count': 3,
                'you_follow': false,
                'they_follow': true,
              },
            ],
          }),
        );
      });

      final list = await SocialService(h.client).followSuggestions();
      expect(list, hasLength(1));
      final s = list.first;
      expect(s.id, 7);
      expect(s.username, 'newbie');
      expect(s.personalityType, 'ENFP');
      expect(s.rank, 'Member');
      expect(s.mutualCount, 3);
      expect(s.youFollow, isFalse);
      expect(s.theyFollow, isTrue);
      expect(s.followLabel, 'Follow Back');

      await h.close();
    });
  });

  group('AuthService.logout (JSON contract)', () {
    test('sends JSON body + CSRF header to /api/v1/auth (not a form)',
        () async {
      String? contentType;
      String? csrfHeader;
      String? rawBody;

      final store = MemorySessionStoreSeed();
      final h = await Harness.start(
        (req) async {
          if (req.uri.path == '/feed') {
            Harness.respond(req, body: '<meta name="csrf-token" content="ct">');
          } else if (req.uri.path == '/api/v1/auth') {
            contentType = req.headers.contentType?.mimeType;
            csrfHeader = req.headers.value('x-csrf-token');
            rawBody = await utf8.decoder.bind(req).join();
            Harness.respond(req, status: 200, body: '{"success":true}');
          } else {
            Harness.respond(req, status: 404);
          }
        },
        store: store,
      );

      final auth = AuthService(h.client, apiBaseUrl: h.client.apiBaseUrl);
      await auth.logout();

      expect(contentType, 'application/json');
      expect(csrfHeader, 'ct');
      expect(rawBody, '{"action":"logout"}');
      expect(store.cleared, isTrue);

      await h.close();
    });
  });

  group('Liker.fromJson (raw fields + prod HTML fallbacks)', () {
    test('raw fields win when present', () {
      final l = Liker.fromJson({
        'id': 1,
        'username': 'Slimejkl',
        'profile_picture_url': '/a.jpg',
        'personality_type': 'INTJ',
        'rank': 'SysOp',
        'liked_at': 'August 20, 2026 at 1:43 PM',
      });
      expect(l.personalityType, 'INTJ');
      expect(l.rank, 'SysOp');
    });

    test('prod payload (no raw fields) parses personality from the badge HTML',
        () {
      // The exact shape prod returns today (older likes.php): HTML
      // personality_badge + rank_styles, no raw personality_type/rank.
      final l = Liker.fromJson({
        'id': 1,
        'username': 'Slimejkl',
        'profile_picture_url': '/public/avatars/a.jpg',
        'personality_badge':
            '<span class="inline-flex items-center px-2 py-0.75 text-[0.7rem] rounded-full font-medium text-fuchsia-600">INTJ</span>',
        'liked_at': 'August 20, 2026 at 1:43 PM',
        'rank_styles': {
          'badge':
              '<a class="inline-flex items-center px-1 py-0.5 rounded text-xs font-medium whitespace-nowrap bg-purple-700 text-gray-950 border border-purple-500 hover:opacity-80 transition-opacity"><i class="fas fa-code"></i>SysOp</a>',
          'name_color': 'text-purple-400 hover:text-purple-300',
        },
      });
      expect(l.personalityType, 'INTJ');
      expect(l.rank, 'SysOp');
    });

    test('Founding Member (two-word rank) parses from the badge HTML', () {
      final l = Liker.fromJson({
        'id': 22,
        'username': 'vaporycoder',
        'personality_badge':
            '<span class="... text-amber-600">INFJ</span>',
        'rank_styles': {
          'badge':
              '<a class="..."><i class="fas fa-crown"></i>Founding Member</a>',
        },
      });
      expect(l.personalityType, 'INFJ');
      expect(l.rank, 'Founding Member');
    });

    test('missing personality/rank HTML falls back to defaults', () {
      final l = Liker.fromJson({'id': 3, 'username': 'nobody'});
      expect(l.personalityType, isNull);
      expect(l.rank, 'Member');
      expect(l.profilePictureUrl, '/assets/default-avatar.png');
    });
  });
}

class MemorySessionStoreSeed implements SessionStore {
  List<SessionCookie> cookies = [
    const SessionCookie(name: 'enclavd_sid', value: 'x'),
    const SessionCookie(name: 'sid', value: 'y'),
  ];
  bool cleared = false;

  @override
  Future<List<SessionCookie>> load() async => cookies;

  @override
  Future<void> save(List<SessionCookie> c) async => cookies = List.of(c);

  @override
  Future<void> clear() async {
    cleared = true;
    cookies = [];
  }
}
