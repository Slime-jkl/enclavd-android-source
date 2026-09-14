import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/feed_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/post_card.dart';

Post _post({
  List<String> images = const [],
  String? image,
  String content = 'hello world',
}) =>
    Post.fromJson({
      'id': 1,
      'author_id': 2,
      'content': content,
      'created_at': '2026-08-20 09:00:00',
      'feed_score': 1.5,
      'like_count': 0,
      'comment_count': 0,
      'user_liked': false,
      'warning_count': 0,
      'username': 'Dev',
      'profile_picture_url': '/a.png',
      'is_active': 'true',
      'rank': 'Member',
      'is_owner': false,
      if (image != null) 'image': image,
      if (images.isNotEmpty) 'images': images,
    });

Future<void> _pump(WidgetTester tester, Post post) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildEnclavdTheme(),
    home: Scaffold(
      body: PostCarousel(post: post, apiBaseUrl: 'https://example.com'),
    ),
  ));
  // One frame is enough: network images fail under flutter_test, so the
  // carousel renders its fallback box at the probing height.
  await tester.pump();
}

/// Advances a PageView without pumpAndSettle (the image shimmer animates
/// forever, so settle would time out).
Future<void> _swipe(WidgetTester tester, Finder target, double dx) async {
  await tester.fling(target, Offset(dx, 0), 900);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

Color _dotColor(WidgetTester tester, int index) {
  final container = tester
      .widget<Container>(find.byKey(ValueKey('carousel-dot-$index')));
  return (container.decoration! as BoxDecoration).color!;
}

void main() {
  group('post images payload', () {
    test('images parse in slide order', () {
      final post = Post.fromJson({
        'id': 1,
        'image': 'lead.jpg',
        'images': ['lead.jpg', 'second.jpg', 'third.jpg'],
      });
      expect(post.images, ['lead.jpg', 'second.jpg', 'third.jpg']);
      expect(post.galleryImages.length, 3);
    });

    test('a payload without images falls back to the single image', () {
      final post = Post.fromJson({'id': 1, 'image': 'only.jpg'});
      expect(post.images, ['only.jpg']);
      expect(post.galleryImages, ['only.jpg']);
    });

    test('empty images list falls back to the single image', () {
      final post = Post.fromJson({
        'id': 1,
        'image': 'only.jpg',
        'images': <dynamic>[],
      });
      expect(post.images, ['only.jpg']);
    });

    test('junk entries are dropped and blanks never become slides', () {
      final post = Post.fromJson({
        'id': 1,
        'images': <dynamic>['a.jpg', '', 7, null, 'b.jpg'],
      });
      expect(post.images, ['a.jpg', 'b.jpg']);
    });

    test('a text-only post has no slides', () {
      final post = Post.fromJson({'id': 1});
      expect(post.images, isEmpty);
      expect(post.galleryImages, isEmpty);
    });

    test('galleryImages still honours a directly built post', () {
      const post = Post(
        id: 1,
        content: 'x',
        createdAt: '',
        feedScore: null,
        likeCount: 0,
        commentCount: 0,
        userLiked: false,
        warningCount: 0,
        username: 'Dev',
        profilePictureUrl: '/a.png',
        personalityType: null,
        isActive: 'true',
        rank: 'Member',
        image: 'direct.jpg',
      );
      expect(post.images, isEmpty);
      expect(post.galleryImages, ['direct.jpg']);
    });
  });

  group('PostCarousel', () {
    testWidgets('one image renders the plain image, never a pager',
        (tester) async {
      await _pump(tester, _post(image: 'one.jpg'));

      expect(find.byType(PageView), findsNothing);
      expect(find.byType(PostImage), findsOneWidget);
      expect(find.byKey(const ValueKey('carousel-dot-0')), findsNothing);
    });

    testWidgets('several images render a pager with one dot each',
        (tester) async {
      await _pump(tester, _post(images: ['a.jpg', 'b.jpg', 'c.jpg']));

      expect(find.byType(PageView), findsOneWidget);
      expect(find.byType(PostImage), findsNothing);
      expect(find.byKey(const ValueKey('carousel-dot-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('carousel-dot-3')), findsNothing);
      expect(_dotColor(tester, 0), EnclavdPalette.dark.link);
      expect(_dotColor(tester, 1),
          EnclavdPalette.dark.textSecondary.withValues(alpha: 0.35));
    });

    testWidgets('swiping moves the active dot', (tester) async {
      await _pump(tester, _post(images: ['a.jpg', 'b.jpg', 'c.jpg']));

      await _swipe(tester, find.byType(PageView), -400);

      expect(find.byType(PageView), findsOneWidget,
          reason: 'the carousel itself never leaves the card');
      expect(
        _dotColor(tester, 1),
        EnclavdPalette.dark.link,
        reason: 'the second slide is now the active one',
      );
      expect(_dotColor(tester, 0),
          EnclavdPalette.dark.textSecondary.withValues(alpha: 0.35));
    });

    testWidgets('tapping a dot jumps to that slide', (tester) async {
      await _pump(tester, _post(images: ['a.jpg', 'b.jpg', 'c.jpg']));

      await tester.tap(find.byKey(const ValueKey('carousel-dot-2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));

      expect(_dotColor(tester, 2), EnclavdPalette.dark.link);
      expect(_dotColor(tester, 0),
          EnclavdPalette.dark.textSecondary.withValues(alpha: 0.35));
    });

    testWidgets('the fullscreen viewer opens where the carousel points',
        (tester) async {
      await _pump(tester, _post(images: ['a.jpg', 'b.jpg', 'c.jpg']));

      await _swipe(tester, find.byType(PageView), -400);
      await tester.tap(find.byType(PostCarousel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('2/3'), findsOneWidget,
          reason: 'the viewer opens on the swiped-to slide');
    });

    testWidgets('a single image viewer keeps its chrome-free look',
        (tester) async {
      await _pump(tester, _post(image: 'one.jpg'));

      await tester.tap(find.byType(PostImage));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('/3'), findsNothing);
      expect(find.byType(Dialog), findsOneWidget);
    });
  });
}
