import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/articles_service.dart';
import 'package:enclavd/screens/article_detail_screen.dart';
import 'package:enclavd/screens/profile_screen.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/rank_badge.dart';

/// Fake service: canned article, scripted like toggles.
class _FakeArticles extends ArticlesService {
  _FakeArticles({this.article, this.likeResults = const []})
      : super(ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  Article? article;
  final List<(bool, int)> likeResults;
  int likeCalls = 0;
  bool forceFail = false;

  @override
  Future<Article> fetch(String slug) async {
    final a = article;
    if (a == null) throw const ApiException('Article not found');
    return a;
  }

  @override
  Future<(bool, int)> toggleLike(int articleId) async {
    if (forceFail) throw const ApiException('nope');
    likeCalls++;
    if (likeResults.isEmpty) return (true, 1);
    final i = likeCalls - 1;
    return likeResults[i.clamp(0, likeResults.length - 1)];
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

Article _article({
  bool liked = false,
  int likeCount = 3,
  String title = 'Open Beta is Now Live',
  String content = '<p>We are excited &amp; open.</p>',
}) =>
    Article(
      summary: ArticleSummary(
        id: 19,
        slug: 'open-beta-is-now-live',
        title: title,
        cover: '/public/articles/6a21a3d2311b4.jpg',
        views: 12085,
        publishedDate: '2026-06-04 16:12:02',
        pinned: true,
        authorId: 1,
        authorUsername: 'Developer',
        authorAvatar: '/public/avatars/dev.png',
        personalityType: 'INTJ',
        rank: 'SysOp',
      ),
      content: content,
      tags: const ['beta', 'release'],
      likeCount: likeCount,
      liked: liked,
      related: const [
        ArticleSummary(
          id: 18,
          slug: 'older-post',
          title: 'Older Post',
          cover: '',
          views: 99,
          publishedDate: '2026-05-01 10:00:00',
          pinned: false,
          authorId: 1,
          authorUsername: 'Developer',
          authorAvatar: '/public/avatars/dev.png',
          personalityType: null,
          rank: 'Member',
        ),
      ],
    );

void main() {
  setUp(() => SoundService.muted = true);
  tearDown(() => SoundService.muted = false);

  /// Pumps the detail screen; [onBody] receives the built document HTML the
  /// bodyBuilder stub gets (the WebView is a platform view, absent under
  /// flutter test — the stub replaces it).
  Future<void> pumpDetail(
    WidgetTester tester,
    _FakeArticles service, {
    void Function(String html)? onBody,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: ArticleDetailScreen(
        articles: service,
        slug: 'open-beta-is-now-live',
        bodyBuilder: (html, baseUrl) {
          onBody?.call(html);
          return const SizedBox.shrink();
        },
      ),
    ));
    await tester.pump(); // fetch() resolves
    await tester.pump();
  }

  testWidgets('renders the hero, author row, tags and body document',
      (tester) async {
    String? html;
    await pumpDetail(tester, _FakeArticles(article: _article()),
        onBody: (h) => html = h);

    expect(find.text('Open Beta is Now Live'), findsWidgets,
        reason: 'hero + app bar');
    expect(find.text('Developer'), findsOneWidget);
    expect(find.byType(RankBadge), findsOneWidget,
        reason: 'rank badge sits above the username');
    expect(find.text('INTJ'), findsOneWidget,
        reason: 'personality pill next to the username');
    expect(find.textContaining('Published on'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    expect(find.text('release'), findsOneWidget);
    // The body document carries the content and the related card.
    expect(html, contains('We are excited'));
    expect(html, contains('Continue Reading'));
    expect(html, contains('/article/older-post'));
    expect(html, contains('Older Post'));
    expect(html, contains("url('assets/fonts/Montserrat/"),
        reason: 'the site font is loaded for the body');
    expect(html, contains('EnclavdBridge'),
        reason: 'the auto-height measurement script ships with the doc');
  });

  testWidgets('tapping the author username opens the author profile',
      (tester) async {
    await pumpDetail(tester, _FakeArticles(article: _article()));

    await tester.tap(find.text('Developer'));
    // Bounded pumps, not pumpAndSettle: the profile shows shimmer/spinner
    // (infinite animations), so settle never returns.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // route push
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('like heart reflects the payload and toggles optimistically',
      (tester) async {
    final service = _FakeArticles(
      article: _article(liked: false, likeCount: 3),
      likeResults: const [(true, 4)],
    );
    await pumpDetail(tester, service);

    expect(find.text('3'), findsOneWidget, reason: 'initial like count');
    expect(findFa(FontAwesomeIcons.heart), findsOneWidget,
        reason: 'outline heart when unliked');

    await tester.tap(findFa(FontAwesomeIcons.heart));
    await tester.pump(); // optimistic flip
    await tester.pump(); // toggleLike() resolves
    expect(findFa(FontAwesomeIcons.solidHeart), findsOneWidget,
        reason: 'filled heart after liking');
    expect(find.text('4'), findsOneWidget,
        reason: 'reconciled with the server count');
    expect(service.likeCalls, 1);
  });

  testWidgets('rolls the heart back when the like request fails',
      (tester) async {
    final service = _FakeArticles(article: _article(liked: false, likeCount: 3))
      ..forceFail = true;

    await pumpDetail(tester, service);
    await tester.tap(findFa(FontAwesomeIcons.heart));
    await tester.pump();
    await tester.pump();

    expect(findFa(FontAwesomeIcons.heart), findsOneWidget,
        reason: 'rolled back to the outline heart');
    expect(find.text('3'), findsOneWidget,
        reason: 'count rolled back too');
    expect(find.text('Could not like this article.'), findsOneWidget,
        reason: 'the site-style failure toast shows');
  });

  testWidgets('404 shows the error view with retry', (tester) async {
    final service = _FakeArticles(); // article null → ApiException
    await pumpDetail(tester, service);
    expect(find.text('Article not found'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}

/// FaIcon converts its FaIconData to a plain IconData for storage — finders
/// must compare code points, never the FaIconData consts (11.x quirk).
Finder findFa(FaIconData icon) => find.byWidgetPredicate((w) =>
    w is FaIcon && w.icon != null && w.icon!.codePoint == icon.codePoint);
