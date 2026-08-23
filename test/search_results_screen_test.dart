import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/search_service.dart';
import 'package:enclavd/screens/post_detail_screen.dart';
import 'package:enclavd/screens/profile_screen.dart';
import 'package:enclavd/screens/search_results_screen.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/rank_badge.dart';
import 'package:enclavd/widgets/shimmer.dart';

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

ApiClient _noopClient() => ApiClient(
      store: _NoopStore(),
      apiBaseUrl: 'https://example.com',
    );

class _FakeSearch extends SearchService {
  _FakeSearch() : super(_noopClient());

  /// When set, search() waits on this — lets tests observe the shimmer.
  Completer<void>? gate;
  List<SearchResult> results = const [];

  @override
  Future<List<SearchResult>> search(String query) async {
    final g = gate;
    if (g != null) await g.future;
    return results;
  }
}

void main() {
  setUp(() => SoundService.muted = true);
  tearDown(() => SoundService.muted = false);

  final alice = SearchResult.fromJson(const {
    'type': 'user',
    'id': 42,
    'user_id': 42,
    'post_id': 0,
    'username': 'alice',
    'avatar': '/public/avatars/alice.png',
    'rank': 'SysOp',
    'personality_type': 'INTJ',
    'content': 'builder of things',
    'post_content': '',
    'date': '',
    'stats': {'posts': 12},
  });
  final bobPost = SearchResult.fromJson(const {
    'type': 'post',
    'id': 88,
    'user_id': 7,
    'post_id': 0,
    'username': 'bob',
    'avatar': '/public/avatars/bob.png',
    'rank': 'Admin',
    'personality_type': 'INTP',
    'content': 'A post about things',
    'post_content': '',
    'date': 'Aug 20, 2026',
    'stats': {'likes': 3, 'comments': 1},
  });
  final carolComment = SearchResult.fromJson(const {
    'type': 'comment',
    'id': 5,
    'user_id': 9,
    'post_id': 88,
    'username': 'carol',
    'avatar': '/public/avatars/carol.png',
    'rank': 'Member',
    'personality_type': '',
    'content': 'nice post',
    'post_content': 'A post about things',
    'date': 'Aug 21, 2026',
    'stats': <String, dynamic>{},
  });

  Future<void> pumpResults(WidgetTester tester, _FakeSearch search,
      {String query = 'things'}) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: SearchResultsScreen(search: search, query: query),
    ));
    await tester.pump();
  }

  testWidgets('shimmers while the search is in flight', (tester) async {
    final search = _FakeSearch()..gate = Completer<void>();
    await pumpResults(tester, search);

    expect(find.byType(ShimmerBox), findsWidgets,
        reason: 'the page shimmers until the results arrive');
    expect(find.text('alice'), findsNothing);

    search.gate!.complete();
    search.results = [alice];
    await tester.pump();
    await tester.pump();
    expect(find.text('alice'), findsOneWidget);
  });

  testWidgets('groups results into Members / Posts / Comments with rank '
      'colors and personality chips', (tester) async {
    final search = _FakeSearch()..results = [alice, bobPost, carolComment];
    await pumpResults(tester, search);

    expect(find.text('MEMBERS'), findsOneWidget);
    expect(find.text('POSTS'), findsOneWidget);
    expect(find.text('COMMENTS'), findsOneWidget);

    // Usernames present, rank badges shown.
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('carol'), findsOneWidget);
    expect(find.byType(RankBadge), findsNWidgets(3));

    // Personality chips: alice INTJ + bob INTP render; carol has none.
    expect(find.text('INTJ'), findsOneWidget);
    expect(find.text('INTP'), findsOneWidget);

    // Type-specific subtitles.
    expect(find.text('12 posts'), findsOneWidget);
    expect(find.textContaining('A post about things'), findsWidgets);
    expect(find.textContaining('On:'), findsOneWidget);
  });

  testWidgets('user row opens the profile', (tester) async {
    final search = _FakeSearch()..results = [alice];
    await pumpResults(tester, search);

    await tester.tap(find.text('alice'));
    // Bounded pumps, not pumpAndSettle: ProfileScreen shows shimmer /
    // spinner (infinite animations), so settle never returns.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('post and comment rows open the post detail screen',
      (tester) async {
    final search = _FakeSearch()..results = [bobPost, carolComment];
    await pumpResults(tester, search);

    // Post row → PostDetailScreen(postId = the post's own id).
    await tester.tap(find.text('bob'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PostDetailScreen), findsOneWidget);

    // Back, then comment row → PostDetailScreen(postId = parent post id).
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('carol'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PostDetailScreen), findsOneWidget);
  });

  testWidgets('empty state', (tester) async {
    final search = _FakeSearch();
    await pumpResults(tester, search, query: 'nope');
    expect(find.text('No results for "nope"'), findsOneWidget);
  });

  testWidgets('error state shows retry', (tester) async {
    final failing = _FailingSearch();
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: SearchResultsScreen(search: failing, query: 'x'),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Search failed'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}

class _FailingSearch extends SearchService {
  _FailingSearch() : super(_noopClient());

  @override
  Future<List<SearchResult>> search(String query) async =>
      throw Exception('boom');
}