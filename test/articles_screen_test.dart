import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/articles_service.dart';
import 'package:enclavd/screens/articles_screen.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/pinned_badge.dart';
import 'package:enclavd/widgets/shimmer.dart';

/// Fake service with canned list responses (no sockets under flutter test).
class _FakeArticles extends ArticlesService {
  _FakeArticles({this.feed})
      : super(ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  final ArticlesFeed? feed;

  /// When set, list() waits on this — lets tests observe the loading state.
  Completer<void>? gate;

  @override
  Future<ArticlesFeed> list() async {
    final g = gate;
    if (g != null) await g.future;
    return feed ?? const ArticlesFeed(pinned: [], articles: []);
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

ArticleSummary _article({
  int id = 1,
  String slug = 'open-beta',
  String title = 'Open Beta is Now Live',
  String cover = '/public/articles/a.jpg',
  int views = 12085,
  bool pinned = false,
}) =>
    ArticleSummary(
      id: id,
      slug: slug,
      title: title,
      cover: cover,
      views: views,
      publishedDate: '2026-06-04 16:12:02',
      pinned: pinned,
      authorId: 1,
      authorUsername: 'Developer',
      authorAvatar: '/public/avatars/dev.png',
      personalityType: 'INTJ',
      rank: 'SysOp',
    );

void main() {
  setUp(() => SoundService.muted = true);
  tearDown(() => SoundService.muted = false);

  Future<void> pumpScreen(WidgetTester tester, ArticlesScreen screen) async {
    // ArticlesScreen is the shell's tab body (no own Scaffold) — wrap it.
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: Scaffold(body: screen),
    ));
    await tester.pump(); // list() resolves
    await tester.pump();
  }

  testWidgets('renders pinned and latest sections with card meta', (tester) async {
    final feed = ArticlesFeed(
      pinned: [_article(id: 20, slug: 'pinned-one', title: 'Pinned One', pinned: true)],
      articles: [_article(title: 'Open Beta is Now Live')],
    );
    await pumpScreen(
        tester, ArticlesScreen(articles: _FakeArticles(feed: feed)));

    expect(find.text('PINNED'), findsNWidgets(2),
        reason: 'the section label and the pinned card\'s fire chip');
    expect(find.text('LATEST'), findsOneWidget);
    expect(find.text('Pinned One'), findsOneWidget);
    expect(find.text('Open Beta is Now Live'), findsOneWidget);
    expect(find.byType(PinnedBadge), findsOneWidget,
        reason: 'only the pinned card carries the fire chip');
    // Card meta: author, date, comma-formatted views.
    expect(find.text('Developer'), findsNWidgets(2));
    expect(find.text('Jun 4, 2026'), findsNWidgets(2));
    expect(find.text('12,085'), findsNWidgets(2));
  });

  testWidgets('tapping a card opens the detail via the seam', (tester) async {
    final opened = <String>[];
    final feed = ArticlesFeed(
      pinned: const [],
      articles: [_article(slug: 'open-beta', title: 'Open Beta is Now Live')],
    );
    await pumpScreen(
      tester,
      ArticlesScreen(
        articles: _FakeArticles(feed: feed),
        detailBuilder: (slug) {
          opened.add(slug);
          return const Scaffold(body: Text('detail'));
        },
      ),
    );

    await tester.tap(find.text('Open Beta is Now Live'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // route push
    expect(opened, ['open-beta']);
    expect(find.text('detail'), findsOneWidget);
  });

  testWidgets('empty feed shows the empty state', (tester) async {
    await pumpScreen(tester, ArticlesScreen(articles: _FakeArticles()));
    expect(find.text('No articles yet'), findsOneWidget);
    expect(find.text('PINNED'), findsNothing);
    expect(find.text('LATEST'), findsNothing);
  });

  testWidgets('shimmers while loading, then the sections appear', (tester) async {
    final auth = _FakeArticles()..gate = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: Scaffold(body: ArticlesScreen(articles: auth)),
    ));
    await tester.pump();

    expect(find.byType(ShimmerBox), findsWidgets,
        reason: 'skeleton cards shimmer while list() is pending');
    expect(find.text('PINNED'), findsNothing);

    auth.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(ShimmerBox), findsNothing);
    expect(find.text('No articles yet'), findsOneWidget);
  });

  testWidgets('load failure shows the error view with a working retry',
      (tester) async {
    final failing = _FailingArticles();
    await pumpScreen(tester, ArticlesScreen(articles: failing));
    expect(find.text('boom'), findsOneWidget);

    // Retry succeeds: the service flips to a good feed.
    failing.feed = const ArticlesFeed(pinned: [], articles: []);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(find.text('No articles yet'), findsOneWidget);
  });

  testWidgets('a successful load advances the seen-id badge baseline',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final feed = ArticlesFeed(
      pinned: [_article(id: 27, slug: 'pinned', pinned: true)],
      articles: [_article(id: 19, title: 'Older')],
    );
    await pumpScreen(tester, ArticlesScreen(articles: _FakeArticles(feed: feed)));
    await tester.pump(); // flush the unawaited prefs write

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(ArticlesService.seenIdPrefKey), 27,
        reason: 'max id across pinned + regular becomes the new baseline');
  });

  testWidgets('a failed load leaves the badge baseline untouched',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpScreen(tester, ArticlesScreen(articles: _FailingArticles()));
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(ArticlesService.seenIdPrefKey), isNull,
        reason: 'nothing was seen — the dot stays armed for next launch');
  });
}

class _FailingArticles extends ArticlesService {
  _FailingArticles()
      : super(ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  ArticlesFeed? feed;

  @override
  Future<ArticlesFeed> list() async {
    final f = feed;
    if (f == null) throw const ApiException('boom');
    return f;
  }
}
