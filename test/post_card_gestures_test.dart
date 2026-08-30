import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/feed_service.dart';
import 'package:enclavd/api/social_service.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/post_card.dart';

Post _post({
  int id = 1,
  int likeCount = 0,
  bool userLiked = false,
  String content = 'hello world',
  String? image,
}) =>
    Post.fromJson({
      'id': id,
      'author_id': 2,
      'content': content,
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
      'image': image,
      'is_owner': false,
    });

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
    testWidgets('tap on an UNLIKED heart does not like - shows the hint',
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

    testWidgets(
        '"Liked by N" sits INLINE opposite the buttons - same row, right '
        'side (site justify-between)', (tester) async {
      await pumpPost(tester, _post(likeCount: 3));

      final heartCenter = tester.getCenter(heart());
      final likedByCenter = tester.getCenter(find.text('Liked by 3'));

      expect((likedByCenter.dy - heartCenter.dy).abs() < 12, isTrue,
          reason: 'same vertical line as the like/comment buttons (inline, '
              'not a row below them)');
      expect(likedByCenter.dx > heartCenter.dx + 100, isTrue,
          reason: 'on the OPPOSITE end of the row - buttons stay '
              'left-aligned, Liked by goes right');
    });

    testWidgets('"Liked by" row hidden when there are no likes',
        (tester) async {
      await pumpPost(tester, _post());
      expect(find.textContaining('Liked by'), findsNothing);
    });
  });

// The expand hint is uniquely size 13 (FaIconData can't be compared to the
// resolved IconData; the analyzer flags the ==).
Finder expandHint() => find.byWidgetPredicate(
    (w) => w is FaIcon && w.size == 13 && w.color == Colors.white);

  group('save image to device', () {
    testWidgets('long-press on the post image offers Save to device',
        (tester) async {
      await pumpPost(tester, _post(image: 'x.jpg'));

      expect(expandHint(), findsOneWidget,
          reason: 'post image (with the expand hint) is rendered');

      await tester.longPress(expandHint());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Save image to device'), findsOneWidget,
          reason: 'long-press opens the save sheet');
      expect(find.textContaining('Enclavd folder'), findsOneWidget,
          reason: 'sheet explains where the image lands');
    });

    testWidgets('posts without an image have no long-press save',
        (tester) async {
      await pumpPost(tester, _post());
      expect(expandHint(), findsNothing);
    });
  });

  group('youtube embeds', () {
    testWidgets('posts with a YouTube link show the embed card',
        (tester) async {
      // A 16:9 embed needs a phone-sized surface; the default viewport overflows.
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await pumpPost(
          tester, _post(content: 'watch https://youtu.be/dQw4w9WgXcQ here'));

      expect(
          find.byKey(const Key('youtube-play-button')), findsOneWidget,
          reason: 'resting play button on the embed card');
      expect(find.byType(AspectRatio), findsOneWidget,
          reason: '16:9 embed frame');
    });

    testWidgets('posts without a YouTube link have no embed card',
        (tester) async {
      await pumpPost(tester, _post());
      expect(find.byKey(const Key('youtube-play-button')), findsNothing);
    });
  });

  group('domain charted badge', () {
    Post domainPost() => Post.fromJson({
          'id': 7,
          'author_id': 2,
          'content': 'hello domain',
          'created_at': '2026-08-20 09:00:00',
          'feed_score': 1.5,
          'like_count': 0,
          'comment_count': 3,
          'user_liked': false,
          'warning_count': 0,
          'username': 'Dev',
          'profile_picture_url': '/a.png',
          'personality_type': null,
          'is_active': 'true',
          'rank': 'Member',
          'image': null,
          'is_owner': false,
          'has_domain': true,
          'domain_by': 42,
          'promoter_username': 'BigMod',
          'domain_name': 'Music',
          'domain_slug': 'music',
        });

    testWidgets('domain posts show the charted badge + View in Domains row',
        (tester) async {
      await pumpPost(tester, domainPost());

      expect(find.textContaining('charted this to', findRichText: true),
          findsOneWidget,
          reason: 'promotion banner text');
      expect(find.textContaining('@BigMod', findRichText: true),
          findsOneWidget);
      expect(find.text('View in Domains (3 replies)'), findsOneWidget);
    });

    testWidgets('plain posts show neither the badge nor the View row',
        (tester) async {
      await pumpPost(tester, _post());

      expect(find.textContaining('charted this to', findRichText: true),
          findsNothing);
      expect(find.textContaining('View in Domains'), findsNothing);
    });

    testWidgets('domain posts route the comment button to the forum thread',
        (tester) async {
      // _openDomainThread resolves AppServices lazily; with no container
      // it must not crash and must not open inline comments.
      await pumpPost(tester, domainPost());

      await tester.tap(findFa(FontAwesomeIcons.comments));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('View in Domains (3 replies)'), findsOneWidget);
      // Inline comment composer never appears for domain posts.
      expect(find.byType(TextField), findsNothing);
    });
  });
}

/// FaIcon stores FaIconData as plain IconData; finders must compare code points (11.x quirk).
Finder findFa(FaIconData icon) => find.byWidgetPredicate((w) =>
    w is FaIcon && w.icon != null && w.icon!.codePoint == icon.codePoint);
