import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/feed_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/post_card.dart';

void main() {
  group('Post.fromJson', () {
    test('maps every api/v1 field', () {
      final post = Post.fromJson({
        'id': 218,
        'content': 'hello world',
        'created_at': '2026-08-12 10:32:59',
        'feed_score': -36,
        'like_count': 3,
        'comment_count': 1,
        'user_liked': true,
        'warning_count': 2,
        'username': 'Developer',
        'profile_picture_url': '/public/avatars/a.jpg',
        'personality_type': 'INTJ',
        'is_active': 'true',
        'rank': 'SysOp',
        'image': 'galleryfile.jpg',
      });
      expect(post.id, 218);
      expect(post.likeCount, 3);
      expect(post.commentCount, 1);
      expect(post.userLiked, isTrue);
      expect(post.warningCount, 2);
      expect(post.personalityType, 'INTJ');
      expect(post.rank, 'SysOp');
      expect(post.image, 'galleryfile.jpg');
      expect(post.isBlocked, isFalse);
    });

    test('nulls and missing keys default safely', () {
      final post = Post.fromJson({'id': 1});
      expect(post.content, '');
      expect(post.likeCount, 0);
      expect(post.userLiked, isFalse);
      expect(post.rank, 'Member');
      expect(post.image, isNull);
      expect(post.profilePictureUrl, '/assets/default-avatar.png');
    });

    test('is_active=false marks the user blocked', () {
      final post = Post.fromJson({'id': 1, 'is_active': 'false'});
      expect(post.isBlocked, isTrue);
    });

    test('content html entities are decoded once (the apostrophe bug)', () {
      final post = Post.fromJson({
        'id': 1,
        'content': "I&#039;m here &amp; it&#039;s fine",
      });
      expect(post.content, "I'm here & it's fine");
      // Never double-decoded.
      final twice = Post.fromJson({'id': 2, 'content': '&amp;lt;'});
      expect(twice.content, '&lt;');
    });
  });

  group('FeedPage.fromJson', () {
    test('parses posts + keyset cursor + has_more', () {
      final page = FeedPage.fromJson({
        'success': true,
        'posts': [
          {'id': 3, 'content': 'a'},
          {'id': 2, 'content': 'b'},
        ],
        'has_more': true,
        'last_score': -5770.9,
        'last_id': 157,
      });
      expect(page.posts.length, 2);
      expect(page.hasMore, isTrue);
      expect(page.lastScore, -5770.9);
      expect(page.lastId, 157);
      expect(page.isEmpty, isFalse);
    });

    test('empty feed parses cleanly', () {
      final page = FeedPage.fromJson(
          {'success': true, 'posts': <dynamic>[], 'has_more': false});
      expect(page.isEmpty, isTrue);
      expect(page.hasMore, isFalse);
      expect(page.lastScore, isNull);
      expect(page.lastId, isNull);
    });

    test('hashtag branch carries total + last_created_at keyset', () {
      final page = FeedPage.fromJson({
        'success': true,
        'posts': [
          {'id': 3, 'content': 'a'},
        ],
        'has_more': true,
        'last_created_at': '2026-08-12 10:32:59',
        'last_id': 3,
        'total': 42,
      });
      expect(page.total, 42);
      expect(page.lastCreatedAt, '2026-08-12 10:32:59');
      expect(page.lastId, 3);
      expect(page.hasMore, isTrue);
    });
  });

  group('relativeTime (format_date port)', () {
    test('just now', () {
      expect(
        relativeTime(
            _iso(DateTime.now().subtract(const Duration(seconds: 20)))),
        'now',
      );
    });

    test('minutes → Xm', () {
      expect(
        relativeTime(_iso(DateTime.now().subtract(const Duration(minutes: 5)))),
        '5m',
      );
    });

    test('hours → Xh', () {
      expect(
        relativeTime(_iso(DateTime.now().subtract(const Duration(hours: 3)))),
        '3h',
      );
    });

    test('days → Xd', () {
      expect(
        relativeTime(_iso(DateTime.now().subtract(const Duration(days: 2)))),
        '2d',
      );
    });

    test('months → Xm (30-day month approximation like PHP diff)', () {
      expect(
        relativeTime(_iso(DateTime.now().subtract(const Duration(days: 60)))),
        '2m',
      );
    });

    test('years → Xy', () {
      expect(
        relativeTime(_iso(DateTime.now().subtract(const Duration(days: 400)))),
        '1y',
      );
    });

    test('future timestamps clamp to now', () {
      expect(
        relativeTime(_iso(DateTime.now().add(const Duration(minutes: 10)))),
        'now',
      );
    });

    test('garbage input returns empty', () {
      expect(relativeTime('not-a-date'), '');
    });
  });

  group('extractYouTubeId (site url_helpers.php port)', () {
    test('watch?v= form', () {
      expect(extractYouTubeId('see https://www.youtube.com/watch?v=dQw4w9WgXcQ now'),
          'dQw4w9WgXcQ');
    });

    test('shorts, youtu.be and embed forms', () {
      expect(extractYouTubeId('https://youtube.com/shorts/dQw4w9WgXcQ'),
          'dQw4w9WgXcQ');
      expect(extractYouTubeId('https://youtu.be/dQw4w9WgXcQ?t=5'),
          'dQw4w9WgXcQ');
      expect(extractYouTubeId('https://www.youtube.com/embed/dQw4w9WgXcQ'),
          'dQw4w9WgXcQ');
    });

    test('no protocol and uppercase host still match (PHP ~i flag)', () {
      expect(extractYouTubeId('www.YOUTUBE.com/watch?v=dQw4w9WgXcQ'),
          'dQw4w9WgXcQ');
    });

    test('first YouTube link wins; others ignored', () {
      expect(
          extractYouTubeId(
              'https://youtu.be/dQw4w9WgXcQ then https://youtu.be/aaaaaaaaaaa'),
          'dQw4w9WgXcQ');
    });

    test('no youtube link → null', () {
      expect(extractYouTubeId('just a normal post'), isNull);
      expect(extractYouTubeId('https://example.com/watch?v=dQw4w9WgXcQ'),
          isNull);
    });
  });

  group('RankColors', () {
    test('known ranks map to their Tailwind colors', () {
      expect(
          RankColors.forRank('SysOp'), const Color(0xFFC084FC)); // purple-400
      expect(RankColors.forRank('Admin'), const Color(0xFFF87171)); // red-400
      expect(
          RankColors.forRank('Officer'), const Color(0xFF60A5FA)); // blue-400
      expect(RankColors.forRank('Founding Member'),
          const Color(0xFFFACC15)); // yellow-400
      expect(RankColors.forRank('Labcoat'), const Color(0xFFFFFFFF));
    });

    test('unknown rank falls back to Member gray', () {
      expect(RankColors.forRank('Nonsense'), const Color(0xFF9CA3AF));
    });
  });

  group('PersonalityColors', () {
    test('archetype groups map to their accent colors', () {
      expect(PersonalityColors.forType('INTJ'),
          const Color(0xFFC026D3)); // fuchsia
      expect(
          PersonalityColors.forType('ENFP'), const Color(0xFFD97706)); // amber
      expect(PersonalityColors.forType('ISFJ'), const Color(0xFFDC2626)); // red
      expect(
          PersonalityColors.forType('ESTP'), const Color(0xFF2563EB)); // blue
    });

    test('case-insensitive + unknown → null', () {
      expect(PersonalityColors.forType('intj'), const Color(0xFFC026D3));
      expect(PersonalityColors.forType(null), isNull);
      expect(PersonalityColors.forType('XXXX'), isNull);
    });
  });
}

String _iso(DateTime dt) => dt.toIso8601String().replaceFirst('T', ' ');
