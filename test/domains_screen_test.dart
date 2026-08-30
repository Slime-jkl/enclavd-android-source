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
      : super(ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  final List<DomainCategory> flat;

  /// Feed pages keyed by the selected domain id (null = All).
  final Map<int?, DomainFeedPage> pages;

  Completer<void>? gate;
  int? lastFeedDomainId;
  int feedCalls = 0;

  @override
  Future<List<DomainCategory>> board() async {
    final g = gate;
    if (g != null) await g.future;
    return flat;
  }

  @override
  Future<DomainFeedPage> feed({
    int? domainId,
    int limit = 20,
    int offset = 0,
  }) async {
    final g = gate;
    if (g != null) await g.future;
    lastFeedDomainId = domainId;
    feedCalls++;
    return pages[domainId] ??
        const DomainFeedPage(threads: [], total: 0, hasMore: false);
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
      iconCode: 0xf06d,
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
  int? iconCode = 0xf0eb,
  String? lastReplyUser,
}) =>
    DomainThread(
      post: _post(id),
      domainSlug: domain.toLowerCase().replaceAll(' ', '-'),
      domainName: domain,
      domainIcon: domainIcon,
      domainIconCode: iconCode,
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

  testWidgets('shows skeletons while the board and feed load',
      (tester) async {
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
        null: DomainFeedPage(
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
        null: DomainFeedPage(
          threads: [_thread(218)],
          total: 2,
          hasMore: false,
        ),
        3: DomainFeedPage(
          threads: [
            _thread(
              188,
              domain: 'Movies & TV',
              domainIcon: 'fa-film',
              iconCode: 0xf008,
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

    expect(service.lastFeedDomainId, 3);
    expect(find.text('Posts in Entertainment'), findsOneWidget);
    expect(find.text('Title line'), findsOneWidget); // filtered row
  });

  testWidgets('tapping a feed row opens the thread via the builder seam',
      (tester) async {
    final service = _FakeDomains(
      flat: [_cat(id: 1, name: 'General')],
      pages: {
        null: DomainFeedPage(
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

  testWidgets('empty feed shows the empty state', (tester) async {
    final service = _FakeDomains(flat: [_cat(id: 1, name: 'General')]);
    await tester.pumpWidget(wrap(DomainsScreen(domains: service)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('No posts yet'), findsOneWidget);
  });
}
