import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/feed_service.dart';
import 'package:enclavd/api/social_service.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/utils/post_list.dart';
import 'package:enclavd/widgets/post_card.dart';

Post _post({
  int id = 1,
  int likeCount = 0,
  bool userLiked = false,
  int commentCount = 0,
}) =>
    Post.fromJson({
      'id': id,
      'author_id': 2,
      'content': 'post $id',
      'created_at': '2026-08-20 09:00:00',
      'feed_score': 1.5,
      'like_count': likeCount,
      'comment_count': commentCount,
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

class _FakeSocial extends SocialService {
  _FakeSocial() : super(ApiClient(store: _NoopStore(), apiBaseUrl: 'https://x'));

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
}

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

/// Stands in for a screen's list: it owns the posts and wires each card the way
/// feed_screen does. [report] is the screen's onPostUpdated (null models a
/// screen that never wired one).
class _ListHost extends StatefulWidget {
  const _ListHost(this.posts, this.social, this.controller, {this.report});

  final List<Post> posts;
  final SocialService social;
  final ScrollController controller;
  final void Function(Post post)? report;

  @override
  State<_ListHost> createState() => _ListHostState();
}

class _ListHostState extends State<_ListHost> {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: widget.controller,
      itemCount: widget.posts.length,
      itemBuilder: (context, i) => PostCard(
        key: ValueKey(widget.posts[i].id),
        post: widget.posts[i],
        apiBaseUrl: 'https://example.com',
        social: widget.social,
        onPostUpdated: widget.report == null
            ? null
            : (post) => setState(() {
                  replacePost(widget.posts, post);
                  widget.report!(post);
                }),
      ),
    );
  }
}

Finder heart(int postId) => find.descendant(
      of: find.byKey(ValueKey(postId)),
      matching: find.byKey(const ValueKey('like-heart')),
    );

void main() {
  setUp(() => SoundService.muted = true);
  tearDown(() => SoundService.muted = false);

  Future<void> pumpList(
    WidgetTester tester,
    List<Post> posts,
    ScrollController controller, {
    void Function(Post post)? report,
    _FakeSocial? social,
  }) async {
    tester.view.physicalSize = const Size(420, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: Scaffold(
        body: _ListHost(posts, social ?? _FakeSocial(), controller,
            report: report),
      ),
    ));
  }

  Future<void> tapLike(WidgetTester tester, int postId) async {
    await tester.tap(heart(postId));
    // The card's double-tap recognizer delays a single tap ~300ms.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  }

  Future<void> scrollTo(WidgetTester tester, ScrollController c, double px) async {
    c.jumpTo(px);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  }

  group('the like a card owns reaches the list that holds the post', () {
    testWidgets('a like survives its card being scrolled out and back',
        (tester) async {
      final posts = [for (var i = 1; i <= 8; i++) _post(id: i)];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpList(tester, posts, controller, report: (_) {});

      await tapLike(tester, 1);
      expect(find.text('Liked by 1'), findsOneWidget);

      // Out of view: ListView drops the element and its State, so the card has
      // to rebuild from the list's copy on the way back.
      await scrollTo(tester, controller, controller.position.maxScrollExtent);
      expect(find.byKey(const ValueKey(1)), findsNothing,
          reason: 'the card really is disposed off screen');

      await scrollTo(tester, controller, 0);
      expect(find.text('Liked by 1'), findsOneWidget,
          reason: 'rebuilt card restores the like');
      expect(tester.widget<FaIcon>(heart(1)).color,
          EnclavdPalette.dark.likeActive);
    });

    testWidgets('a screen that never wires the report loses the like (the '
        'reported bug)', (tester) async {
      final posts = [for (var i = 1; i <= 8; i++) _post(id: i)];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpList(tester, posts, controller);

      await tapLike(tester, 1);
      expect(find.text('Liked by 1'), findsOneWidget);

      await scrollTo(tester, controller, controller.position.maxScrollExtent);
      await scrollTo(tester, controller, 0);

      // Pinned so the guard above cannot pass by construction.
      expect(find.text('Liked by 1'), findsNothing,
          reason: 'without the callback the card reseeds from the load-time '
              'post and the like appears to vanish');
      expect(tester.widget<FaIcon>(heart(1)).color,
          EnclavdPalette.dark.textSecondary);
    });

    testWidgets('an unlike reaches the list too', (tester) async {
      final posts = [_post(id: 1, likeCount: 1, userLiked: true)];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final social = _FakeSocial()
        ..respondLiked = false
        ..respondCount = 0;
      await pumpList(tester, posts, controller, report: (_) {}, social: social);

      await tapLike(tester, 1);
      expect(find.textContaining('Liked by'), findsNothing);

      expect(posts.single.userLiked, isFalse);
      expect(posts.single.likeCount, 0);
    });

    testWidgets('every screen that builds a card wires the report back',
        (tester) async {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.contains('/screens/')) continue;
        final src = f.readAsStringSync();
        if (!RegExp(r'PostCard\(|_ForumPostCard\(').hasMatch(src)) continue;
        if (!src.contains('onPostUpdated')) offenders.add(f.path);
      }
      expect(offenders, isEmpty,
          reason: 'a card built in a list must report its engagement back, or '
              'the like vanishes when the card is disposed');
    });
  });

  group('copyWithEngagement', () {
    test('moves only the engagement fields', () {
      final post = Post.fromJson({
        'id': 7,
        'author_id': 2,
        'content': 'chart this',
        'created_at': '2026-08-20 09:00:00',
        'like_count': 3,
        'comment_count': 4,
        'user_liked': true,
        'ignite_count': 2,
        'user_ignited': true,
        'username': 'Dev',
        'profile_picture_url': '/a.png',
        'is_active': 'true',
        'rank': 'Member',
        'images': ['/a.jpg', '/b.jpg'],
        'is_owner': true,
        'has_domain': true,
        'domain_slug': 'tech',
        'domain_name': 'Tech',
        'domain_by': 9,
        'promoter_username': 'Dev',
        'last_reply_username': 'Ann',
      });

      final bumped = post.copyWithEngagement(commentCount: 5);

      expect(bumped.commentCount, 5);
      expect(bumped.likeCount, 3);
      expect(bumped.userLiked, isTrue);
      expect(bumped.userIgnited, isTrue);
      expect(bumped.igniteCount, 2);
      // The fields the old hand-rolled copy in the thread screen dropped.
      expect(bumped.images, ['/a.jpg', '/b.jpg']);
      expect(bumped.isOwner, isTrue);
      expect(bumped.hasDomain, isTrue);
      expect(bumped.domainSlug, 'tech');
      expect(bumped.domainName, 'Tech');
      expect(bumped.domainBy, 9);
      expect(bumped.promoterUsername, 'Dev');
      expect(bumped.lastReplyUsername, 'Ann');
      expect(bumped.content, 'chart this');
    });
  });

  group('IgniteResult.countAfter', () {
    test('takes the server count when it sent one', () {
      const r = IgniteResult(status: 'ignited', likeCount: 5, igniteCount: 9);
      expect(r.countAfter(3), 9);
    });

    test('a grant with no count adds one', () {
      const r = IgniteResult(status: 'ignited', likeCount: 5);
      expect(r.countAfter(3), 4);
    });

    test('a re-press of an already ignited post does not add', () {
      const r = IgniteResult(status: 'already_ignited', likeCount: 5);
      expect(r.countAfter(4), 4);
    });
  });
}
