import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/feed_service.dart';
import 'package:enclavd/api/social_service.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/post_card.dart';

Post _post({int id = 1, int likeCount = 0, bool userLiked = false}) =>
    Post.fromJson({
      'id': id,
      'author_id': 2,
      'content': 'hello world',
      'created_at': '2026-08-20 09:00:00',
      'feed_score': 1.5,
      'like_count': likeCount,
      'comment_count': 0,
      'user_liked': userLiked,
      'warning_count': 0,
      'username': 'Dev',
      'profile_picture_url': '/a.png',
      'personality_type': null,
      'is_active': 'true',
      'rank': 'Member',
      'image': null,
      'is_owner': false,
    });

/// SocialService that answers from memory — widget tests run in a
/// fake-async zone where real sockets (the Harness) never complete.
class _FakeSocial extends SocialService {
  _FakeSocial() : super(_noopClient());

  static ApiClient _noopClient() => ApiClient(
        store: _NoopStore(),
        apiBaseUrl: 'https://example.com',
      );

  int toggleCalls = 0;
  bool respondLiked = true;
  int respondCount = 1;

  @override
  Future<LikeResult> toggleLike(int postId) async {
    toggleCalls++;
    return LikeResult(
      action: respondLiked ? 'liked' : 'unliked',
      likeCount: respondCount,
    );
  }

  @override
  Future<List<Liker>> likers(int postId) async => [
        const Liker(
          id: 1,
          username: 'Dev',
          profilePictureUrl: '/a.png',
          personalityType: null,
          rank: 'Member',
          likedAt: 'August 20, 2026 at 9:00 AM',
        ),
      ];
}

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

Finder heart() => find.byKey(const ValueKey('like-heart'));

void main() {
  setUp(() => SoundService.muted = true);
  tearDown(() => SoundService.muted = false);

  Future<_FakeSocial> pumpPost(WidgetTester tester, Post post) async {
    final social = _FakeSocial();
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: Scaffold(
        body: PostCard(
          post: post,
          apiBaseUrl: 'https://example.com',
          social: social,
        ),
      ),
    ));
    return social;
  }

  group('like gestures (site parity)', () {
    testWidgets('tap on an UNLIKED heart does not like — shows the hint',
        (tester) async {
      final social = await pumpPost(tester, _post());

      await tester.tap(heart());
      // The ancestor double-tap recognizer delays single taps ~300ms.
      await tester.pump(const Duration(milliseconds: 400));

      expect(social.toggleCalls, 0,
          reason: 'tapping an unliked heart must not like');
      expect(
          find.text('Drag the heart onto the post to like it'), findsOneWidget,
          reason: 'site tooltip hint');
    });

    testWidgets('tap on a LIKED heart unlikes', (tester) async {
      final social =
          await pumpPost(tester, _post(likeCount: 1, userLiked: true));
      social.respondLiked = false;
      social.respondCount = 0;

      await tester.tap(heart());
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(social.toggleCalls, 1,
          reason: 'tap on a liked heart toggles (unlike)');
    });

    testWidgets(
        'holding the heart shows the drop tray; release without '
        'dropping does not like', (tester) async {
      final social = await pumpPost(tester, _post());

      final g = await tester.startGesture(tester.getCenter(heart()));
      await tester.pump(const Duration(milliseconds: 600)); // long-press
      await tester.pump();

      expect(find.text('Drag the heart here to like'), findsOneWidget,
          reason: 'drop tray appears while the heart is held');

      await g.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(social.toggleCalls, 0,
          reason: 'release without dropping is not a like');
    });

    testWidgets('dragging the heart onto the post likes it', (tester) async {
      final social = await pumpPost(tester, _post());

      final g = await tester.startGesture(tester.getCenter(heart()));
      await tester.pump(const Duration(milliseconds: 600)); // long-press
      await tester.pump();
      // Drag the heart onto the CONTENT text (the DragTarget region).
      final target = tester.getCenter(find.text('hello world'));
      final origin = tester.getCenter(heart());
      await g.moveBy(target - origin);
      await tester.pump();
      await g.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(social.toggleCalls, 1,
          reason: 'dropping the heart on the post likes it');
      expect(find.text('Liked by 1'), findsOneWidget,
          reason: 'optimistic count then reconcile');
    });

    testWidgets('double-tap on the post likes it', (tester) async {
      final social = await pumpPost(tester, _post());

      await tester.tap(find.byType(PostCard));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byType(PostCard));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(social.toggleCalls, 1, reason: 'double-tap likes (like-only)');
    });
  });

  group('liked-by', () {
    testWidgets('"Liked by N" shows when likes exist and opens the sheet',
        (tester) async {
      await pumpPost(tester, _post(likeCount: 3));

      expect(find.text('Liked by 3'), findsOneWidget);

      await tester.tap(find.text('Liked by 3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Dev'), findsWidgets,
          reason: 'likers sheet lists the liker');
    });

    testWidgets('"Liked by" row hidden when there are no likes',
        (tester) async {
      await pumpPost(tester, _post());
      expect(find.textContaining('Liked by'), findsNothing);
    });
  });
}
