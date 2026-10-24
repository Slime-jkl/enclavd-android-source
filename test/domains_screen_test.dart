import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/domains_service.dart';
import 'package:enclavd/api/feed_service.dart'; // Post
import 'package:enclavd/screens/domains_screen.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/shimmer.dart';

class _FakeDomains extends DomainsService {
  _FakeDomains({this.flat = const [], this.pages = const {}})
      : super(
            ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  final List<DomainCategory> flat;

  /// Feed pages keyed by the filter ('all', or the sorted ids '1,3').
  final Map<String, DomainFeedPage> pages;

  Completer<void>? gate;
  Set<int> lastFeedDomainIds = const {};
  String lastFeedKey = 'all';
  int feedCalls = 0;
  bool failFeed = false;

  @override
  Future<List<DomainCategory>> board() async {
    final g = gate;
    if (g != null) await g.future;
    return flat;
  }

  @override
  Future<DomainFeedPage> feed({
    Set<int> domainIds = const {},
    int limit = 20,
    int offset = 0,
  }) async {
    final g = gate;
    if (g != null) await g.future;
    if (failFeed) throw const ApiException('Network unreachable');
    lastFeedDomainIds = Set<int>.from(domainIds);
    lastFeedKey = _key(domainIds);
    feedCalls++;
    return pages[lastFeedKey] ??
        const DomainFeedPage(threads: [], total: 0, hasMore: false);
  }

  static String _key(Set<int> ids) {
    if (ids.isEmpty) return 'all';
    final sorted = ids.toList()..sort();
    return sorted.join(',');
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

DomainCategory _cat({
  int id = 3,
  String name = 'Entertainment',
  String? parent,
  String icon = 'fa-fire',
  String color = '#f59e0b',
}) =>
    DomainCategory(
      id: id,
      name: name,
      slug: name.toLowerCase().replaceAll(' ', '-'),
      parent: parent == null ? null : int.parse(parent),
      displayOrder: id,
      icon: icon,
      color: color,
      postCount: 0,
    );

Post _post(int id, {String username = 'Developer'}) => Post(
      id: id,
      content: 'Title line\nBody text here',
      createdAt: '2026-08-30 10:00:00',
      feedScore: null,
      likeCount: 1,
      commentCount: 2,
      userLiked: false,
      warningCount: 0,
      username: username,
      profilePictureUrl: '/assets/default-avatar.png',
      personalityType: null,
      isActive: 'true',
      rank: 'Member',
      image: null,
    );

DomainThread _thread(
  int id, {
  String domain = 'General',
  String domainIcon = 'fa-lightbulb',
  String? lastReplyUser,
}) =>
    DomainThread(
      post: _post(id),
      domainSlug: domain.toLowerCase().replaceAll(' ', '-'),
      domainName: domain,
      domainIcon: domainIcon,
      lastReplyAt: lastReplyUser == null ? null : '2026-08-30 11:22:00',
      lastReplyUsername: lastReplyUser,
      lastReplyRank: 'Member',
      lastReplyActive: 'true',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // audioplayers has no platform channel under flutter test; the like
    // sound would throw an unhandled MissingPluginException.
    SoundService.muted = true;
  });

  Widget wrap(Widget child) => MaterialApp(
        theme: buildEnclavdTheme(),
        home: Scaffold(body: child),
      );

  testWidgets('shows skeletons while the board and feed load', (tester) async {
    final gate = Completer<void>();
    final service = _FakeDomains(flat: [_cat(id: 1, name: 'General')])
      ..gate = gate;

    await tester.pumpWidget(wrap(DomainsScreen(domains: service)));
    expect(find.byType(ShimmerBox), findsWidgets);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Latest Posts'), findsOneWidget);
  });

  testWidgets('renders domain chips and feed rows with badges and activity',
      (tester) async {
    final service = _FakeDomains(
      flat: [
        _cat(id: 1, name: 'General', icon: 'fa-lightbulb'),
        _cat(id: 3, name: 'Entertainment', icon: 'fa-fire'),
      ],
      pages: {
        'all': DomainFeedPage(
          threads: [
            _thread(
              218,
              domain: 'General',
              domainIcon: 'fa-lightbulb',
              lastReplyUser: 'Developer',
            ),
          ],
          total: 1,
          hasMore: false,
        ),
      },
    );

    await tester.pumpWidget(wrap(DomainsScreen(domains: service)));
    await tester.pump(const Duration(milliseconds: 50));

    // Chips: All + both domains.
    expect(find.text('All'), findsOneWidget);
    expect(find.text('General'), findsWidgets); // chip + row badge
    expect(find.text('Entertainment'), findsOneWidget);
    // Row: title (first line) + excerpt + last reply with author.
    expect(find.text('Title line'), findsOneWidget);
    expect(find.text('Body text here'), findsOneWidget);
    expect(find.textContaining('Last reply'), findsOneWidget);
    expect(find.textContaining('@Developer'), findsOneWidget);
  });

  testWidgets('selecting a chip filters the feed to that domain',
      (tester) async {
    final service = _FakeDomains(
      flat: [
        _cat(id: 1, name: 'General'),
        _cat(id: 3, name: 'Entertainment'),
      ],
      pages: {
        'all': DomainFeedPage(
          threads: [_thread(218)],
          total: 2,
          hasMore: false,
        ),
        '3': DomainFeedPage(
          threads: [
            _thread(
              188,
              domain: 'Movies & TV',
              domainIcon: 'fa-film',
            ),
          ],
          total: 1,
          hasMore: false,
        ),
      },
    );

    await tester.pumpWidget(wrap(DomainsScreen(domains: service)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Title line'), findsOneWidget);

    await tester.tap(find.text('Entertainment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(service.lastFeedDomainIds, {3});
    expect(find.text('Posts in Entertainment'), findsOneWidget);
    expect(find.text('Title line'), findsOneWidget); // filtered row
  });

  testWidgets('tapping a feed row opens the thread via the builder seam',
      (tester) async {
    final service = _FakeDomains(
      flat: [_cat(id: 1, name: 'General')],
      pages: {
        'all': DomainFeedPage(
          threads: [_thread(218, lastReplyUser: 'Developer')],
          total: 1,
          hasMore: false,
        ),
      },
    );
    final opened = <int>[];

    await tester.pumpWidget(wrap(DomainsScreen(
      domains: service,
      threadBuilder: (thread) {
        opened.add(thread.post.id);
        return const Scaffold(body: Text('THREAD SCREEN'));
      },
    )));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Title line'));
    await tester.pumpAndSettle();
    expect(opened, [218]);
    expect(find.text('THREAD SCREEN'), findsOneWidget);
  });

  testWidgets('subdomains stay collapsed until their domain is picked',
      (tester) async {
    // Wide surface: a domain and its subdomains must share one row.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _FakeDomains(
      flat: [
        _cat(id: 1, name: 'General', icon: 'fa-lightbulb'),
        _cat(id: 3, name: 'Entertainment', icon: 'fa-fire'),
        _cat(id: 5, name: 'Movies', parent: '3', icon: 'fa-film'),
      ],
      pages: {
        'all': DomainFeedPage(
          threads: [_thread(218, domain: 'General')],
          total: 1,
          hasMore: false,
        ),
        '3': DomainFeedPage(
          threads: [_thread(300, domain: 'Music')],
          total: 1,
          hasMore: false,
        ),
        '3,5': DomainFeedPage(
          threads: [_thread(310, domain: 'Cinema')],
          total: 1,
          hasMore: false,
        ),
      },
    );

    await tester.pumpWidget(wrap(DomainsScreen(domains: service)));
    await tester.pump(const Duration(milliseconds: 50));

    // Collapsed: only the root domains are on the row.
    expect(find.text('Entertainment'), findsOneWidget);
    expect(find.text('Movies'), findsNothing);

    await tester.tap(find.text('Entertainment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(service.lastFeedDomainIds, {3});
    expect(find.text('Movies'), findsOneWidget);
    final parentTop = tester.getTopLeft(find.text('Entertainment')).dy;
    final subTop = tester.getTopLeft(find.text('Movies')).dy;
    expect((subTop - parentTop).abs() <= 8, isTrue,
        reason: 'the subdomain unfolds inline, not on a row underneath');
    expect(find.text('Posts in Entertainment'), findsOneWidget);

    // Picking a subdomain ADDS a filter; the domain keeps its subtree.
    await tester.tap(find.text('Movies'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(service.lastFeedDomainIds, {3, 5});
    expect(find.text('Posts in 2 domains'), findsOneWidget);

    // Collapsing the domain drops the subdomain filter with it.
    await tester.tap(find.text('Entertainment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(service.lastFeedDomainIds, isEmpty);
    expect(find.text('Movies'), findsNothing);
  });

  testWidgets('two domains filter the feed together', (tester) async {
    final service = _FakeDomains(
      flat: [
        _cat(id: 1, name: 'General'),
        _cat(id: 3, name: 'Entertainment'),
      ],
      pages: {
        'all': DomainFeedPage(
          threads: [_thread(218, domain: 'Random')],
          total: 9,
          hasMore: false,
        ),
        '1,3': DomainFeedPage(
          threads: [_thread(400, domain: 'Crossover')],
          total: 7,
          hasMore: false,
        ),
      },
    );

    await tester.pumpWidget(wrap(DomainsScreen(domains: service)));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('General'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Entertainment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(service.lastFeedDomainIds, {1, 3});
    expect(service.lastFeedKey, '1,3');
    expect(find.text('Posts in 2 domains'), findsOneWidget);
    expect(find.text('7 total'), findsOneWidget);

    // "All" clears every filter.
    await tester.tap(find.text('All'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(service.lastFeedDomainIds, isEmpty);
    expect(find.text('Latest Posts'), findsOneWidget);
  });

  testWidgets('a failed feed keeps the chips mounted and offers a retry',
      (tester) async {
    final service = _FakeDomains(flat: [_cat(id: 1, name: 'General')])
      ..failFeed = true;

    await tester.pumpWidget(wrap(DomainsScreen(domains: service)));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('General'), findsOneWidget);
    expect(find.text('Network unreachable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('No posts yet'), findsNothing);
  });

  testWidgets('empty feed shows the empty state', (tester) async {
    final service = _FakeDomains(flat: [_cat(id: 1, name: 'General')]);
    await tester.pumpWidget(wrap(DomainsScreen(domains: service)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('No posts yet'), findsOneWidget);
  });
}
