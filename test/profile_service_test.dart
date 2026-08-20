import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/feed_service.dart';
import 'package:enclavd/api/profile_service.dart';

import 'api_client_test.dart' show Harness;

void main() {
  group('ProfileService.fetchProfile', () {
    test('GETs /api/v1/profile?user_id=N and parses every field', () async {
      String? query;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/api/v1/profile') {
          query = req.uri.query;
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'profile': {
                'id': 7,
                'username': 'Dev',
                'full_name': 'Developer One',
                'profile_picture_url': '/public/avatars/a.jpg',
                'personality_type': 'INTJ',
                'rank': 'SysOp',
                'bio': 'hello world',
                'prestige': 11,
                'date_created': '2024-11-20 21:05:59',
                'is_online': true,
                'is_active': 'true',
                'post_count': 6,
                'warning_count': 1,
                'follower_count': 2,
                'following_count': 15,
                'is_following': false,
                'is_following_you': true,
                'is_own': false,
              },
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final profileService = ProfileService(h.client);
      final p = await profileService.fetchProfile(7);
      expect(query, 'user_id=7');
      expect(p.id, 7);
      expect(p.username, 'Dev');
      expect(p.fullName, 'Developer One');
      expect(p.personalityType, 'INTJ');
      expect(p.rank, 'SysOp');
      expect(p.bio, 'hello world');
      expect(p.prestige, 11);
      expect(p.isOnline, true);
      expect(p.isActive, 'true');
      expect(p.postCount, 6);
      expect(p.warningCount, 1);
      expect(p.followerCount, 2);
      expect(p.followingCount, 15);
      expect(p.isFollowing, false);
      expect(p.isFollowingYou, true);
      expect(p.isOwn, false);
      expect(p.isBlocked, false);

      await h.close();
    });

    test('404 surfaces as ApiException with status 404', () async {
      final h = await Harness.start((req) async {
        Harness.respond(req, status: 404, body: '{"error":"User not found"}');
      });
      await expectLater(
        ProfileService(h.client).fetchProfile(999),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 404)
            .having((e) => e.message, 'message', contains('User not found'))),
      );
      await h.close();
    });
  });

  group('ProfileService.toggleFollow', () {
    test('sends JSON + CSRF, parses followed state + counts', () async {
      String? rawBody;
      String? csrf;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req,
              body: '<meta name="csrf-token" content="tok-follow">');
        } else if (req.uri.path == '/api/v1/profile') {
          rawBody = await utf8.decoder.bind(req).join();
          csrf = req.headers.value('x-csrf-token');
          Harness.respond(req,
              body:
                  '{"success":true,"action":"followed","followers":3,"following":16}');
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final profileService = ProfileService(h.client);
      final r = await profileService.toggleFollow(7);
      expect(r.following, true);
      expect(r.followerCount, 3);
      expect(r.followingCount, 16);
      expect(rawBody, '{"action":"follow","followee_id":7}');
      expect(csrf, 'tok-follow');
      await h.close();
    });

    test('unfollow parses action=unfollowed', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
        } else {
          Harness.respond(req,
              body:
                  '{"success":true,"action":"unfollowed","followers":2,"following":15}');
        }
      });
      final r = await ProfileService(h.client).toggleFollow(7);
      expect(r.following, false);
      expect(r.followerCount, 2);
      await h.close();
    });
  });

  group('FeedService.userPosts', () {
    test('sends user_id + keyset cursor, parses last_created_at', () async {
      String? query;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/api/v1/posts') {
          query = req.uri.query;
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'posts': [
                {
                  'id': 218,
                  'author_id': 1,
                  'content': 'hi',
                  'created_at': '2026-08-12 10:32:59',
                  'feed_score': null,
                  'like_count': 1,
                  'comment_count': 0,
                  'user_liked': true,
                  'warning_count': 0,
                  'username': 'Developer',
                  'profile_picture_url': '/a.png',
                  'personality_type': 'INTJ',
                  'is_active': 'true',
                  'rank': 'SysOp',
                  'image': null,
                },
              ],
              'has_more': true,
              'last_created_at': '2026-08-12 10:32:59',
              'last_id': 218,
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final feedService = FeedService(h.client);
      final page = await feedService.userPosts(1, limit: 10);
      expect(query, 'user_id=1&limit=10');
      expect(page.posts, hasLength(1));
      expect(page.posts.first.authorId, 1);
      expect(page.hasMore, true);
      expect(page.lastCreatedAt, '2026-08-12 10:32:59');
      expect(page.lastId, 218);
      expect(page.lastScore, isNull);

      // Next page carries the cursor.
      await feedService.userPosts(1,
          limit: 10, lastCreatedAt: page.lastCreatedAt, lastId: page.lastId);
      expect(query, contains('user_id=1'));
      expect(query, contains('last_created_at=2026-08-12+10%3A32%3A59'));
      expect(query, contains('last_id=218'));

      await h.close();
    });

    test('newerThan sends after_id (new-posts delta)', () async {
      String? query;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/api/v1/posts') {
          query = req.uri.query;
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'posts': [
                {
                  'id': 219,
                  'author_id': 2,
                  'content': 'new',
                  'created_at': '2026-08-20 09:00:00',
                  'feed_score': 1.5,
                  'like_count': 0,
                  'comment_count': 0,
                  'user_liked': false,
                  'warning_count': 0,
                  'username': 'Other',
                  'profile_picture_url': '/a.png',
                  'personality_type': null,
                  'is_active': 'true',
                  'rank': 'Member',
                  'image': null,
                  'is_owner': false,
                },
              ],
              'has_more': false,
              'last_score': null,
              'last_id': null,
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final page = await FeedService(h.client).newerThan(218, limit: 10);
      expect(query, 'after_id=218&limit=10');
      expect(page.posts, hasLength(1));
      expect(page.posts.first.id, 219);
      expect(page.hasMore, false);
      expect(page.lastScore, isNull);

      await h.close();
    });
  });

  group('formatJoinedDate', () {
    test("ports profile.php's 'M j, Y'", () {
      expect(formatJoinedDate('2024-11-20 21:05:59'), 'Nov 20, 2024');
      expect(formatJoinedDate('2026-01-05 00:00:00'), 'Jan 5, 2026');
      expect(formatJoinedDate('garbage'), '');
    });
  });
}
