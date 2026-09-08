import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/activity_service.dart';

import 'api_client_test.dart' show Harness;

Map<String, dynamic> _post(int id,
        {String username = 'Other',
        String content = 'post text',
        String rank = 'Member'}) =>
    {
      'id': id,
      'author_id': 2,
      'content': content,
      'created_at': '2026-09-01 10:00:00',
      'feed_score': null,
      'like_count': 4,
      'comment_count': 2,
      'user_liked': true,
      'warning_count': 0,
      'username': username,
      'profile_picture_url': '/assets/default-avatar.png',
      'personality_type': null,
      'is_active': 'true',
      'rank': rank,
      'image': null,
      'is_owner': false,
      'has_domain': false,
      'domain_by': 0,
      'promoter_username': null,
      'domain_name': null,
      'domain_slug': null,
    };

void main() {
  group('ActivityService.fetch', () {
    test('GETs /api/v1/activity and parses the three interaction types',
        () async {
      String? query;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/api/v1/activity') {
          query = req.uri.query;
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'has_more': true,
              'activity': [
                {
                  'type': 'like',
                  'id': 617,
                  'created_at': '2026-09-07 16:15:06',
                  'post': _post(125, username: 'Writer', rank: 'Gold'),
                },
                {
                  'type': 'comment',
                  'id': 468,
                  'created_at': '2026-09-07 16:15:05',
                  'content': 'Nice &amp; tidy',
                  'parent_comment_id': null,
                  'post': _post(125, username: 'Writer'),
                },
                {
                  'type': 'follow',
                  'id': 7,
                  'created_at': '2026-09-06 09:00:00',
                  'user': {
                    'id': 7,
                    'username': 'Friend',
                    'full_name': 'A Friend',
                    'profile_picture_url': '/assets/default-avatar.png',
                    'personality_type': null,
                    'rank': 'Member',
                    'bio': '',
                    'is_active': 'true',
                    'is_online': true,
                    'is_following': true,
                    'is_following_you': false,
                    'is_own': false,
                  },
                },
              ],
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final page = await ActivityService(h.client).fetch();
      expect(query, 'limit=20&offset=0');
      expect(page.hasMore, isTrue);
      expect(page.items, hasLength(3));

      final like = page.items[0];
      expect(like.type, ActivityType.like);
      expect(like.id, 617);
      expect(like.post, isNotNull);
      expect(like.post!.username, 'Writer');
      expect(like.post!.likeCount, 4);
      expect(like.user, isNull);
      expect(like.opensPost, isTrue);

      final comment = page.items[1];
      expect(comment.type, ActivityType.comment);
      expect(comment.commentContent, 'Nice & tidy'); // entity-decoded once
      expect(comment.parentCommentId, isNull);
      expect(comment.post!.id, 125);

      final follow = page.items[2];
      expect(follow.type, ActivityType.follow);
      expect(follow.id, 7);
      expect(follow.user, isNotNull);
      expect(follow.user!.username, 'Friend');
      expect(follow.user!.isFollowing, isTrue);
      expect(follow.post, isNull);
      expect(follow.opensPost, isFalse);

      await h.close();
    });

    test('forwards the page cursor and defaults empty responses', () async {
      String? query;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/api/v1/activity') {
          query = req.uri.query;
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'has_more': false,
              'activity': <Object>[],
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final page = await ActivityService(h.client).fetch(limit: 5, offset: 10);
      expect(query, 'limit=5&offset=10');
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);

      await h.close();
    });

    test('unknown type rows default to like', () async {
      final item = ActivityItem.fromJson(const {
        'type': 'mystery',
        'id': 3,
        'created_at': '2026-09-01 09:00:00',
        'post': <String, dynamic>{},
      });
      expect(item.type, ActivityType.like);
      expect(item.id, 3);
    });
  });
}
