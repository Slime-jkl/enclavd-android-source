import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/domains_service.dart';
import 'package:enclavd/screens/domain_category_screen.dart';
import 'package:enclavd/theme/enclavd_theme.dart';

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

/// Fake service with canned thread pages.
class _FakeDomains extends DomainsService {
  _FakeDomains({this.pages})
      : super(ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  final List<DomainThreadPage>? pages;
  Completer<void>? gate;

  @override
  Future<DomainThreadPage> threads(int categoryId,
      {int limit = 20, int offset = 0}) async {
    final g = gate;
    if (g != null) await g.future;
    final all = pages ?? const [];
    final index = offset == 0 ? 0 : 1; // page 0 then page 1
    if (index >= all.length) {
      return DomainThreadPage(
        category: _cat(),
        threads: const [],
        total: 0,
        hasMore: false,
      );
    }
    return all[index];
  }
}

DomainCategory _cat({int id = 3, String name = 'Entertainment'}) =>
    DomainCategory(
      id: id,
      name: name,
      slug: 'entertainment',
      parent: null,
      displayOrder: 1,
      description: 'Movies, music, gaming and more',
      icon: 'fa-masks-theater',
      color: '#f59e0b',
      postCount: 2,
      lastPostAt: '2026-08-12 12:00:00',
      lastPostAuthor: 'Developer',
      lastPostUserId: 1,
    );

Map<String, dynamic> _threadJson({
  int id = 218,
  String content = 'A thread about the new update',
  int commentCount = 3,
  int likeCount = 5,
}) =>
    {
      'id': id,
      'author_id': 1,
      'content': content,
      'created_at': '2026-08-12 10:32:59',
      'feed_score': null,
      'like_count': likeCount,
      'comment_count': commentCount,
      'user_liked': false,
      'warning_count': 0,
      'username': 'Developer',
      'profile_picture_url': '/public/avatars/dev.png',
      'personality_type': 'INTJ',
      'is_active': 'true',
      'rank': 'SysOp',
      'image': null,
      'is_owner': false,
      'domain_slug': 'general',
      'domain_name': 'General',
      'last_reply_at': '2026-08-12 12:00:00',
    };

DomainThreadPage _page(List<Map<String, dynamic>> threads,
        {int total = 1, bool hasMore = false}) =>
    DomainThreadPage.fromJson({
      'success': true,
      'category': {
        'id': 3,
        'name': 'Entertainment',
        'slug': 'entertainment',
        'parent': null,
        'description': 'Movies, music, gaming and more',
        'icon': 'fa-masks-theater',
        'color': '#f59e0b',
      },
      'threads': threads,
      'total': total,
      'has_more': hasMore,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the category header + thread rows', (tester) async {
    final service = _FakeDomains(pages: [
      _page([
        _threadJson(), // id 218: 3 comments, 5 likes
        _threadJson(id: 210, commentCount: 1, likeCount: 2),
      ])
    ]);

    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: DomainCategoryScreen(domains: service, category: _cat()),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    // AppBar title + header block.
    expect(find.text('Entertainment'), findsWidgets);
    expect(find.text('Movies, music, gaming and more'), findsOneWidget);
    // Thread rows: excerpt + author + stats.
    expect(find.text('A thread about the new update'), findsWidgets);
    expect(find.text('Developer'), findsWidgets);
    expect(find.text('3'), findsOneWidget); // comments on 218
    expect(find.text('5'), findsOneWidget); // likes on 218
    expect(find.text('2'), findsOneWidget); // likes on 210
  });

  testWidgets('empty category shows the empty state', (tester) async {
    final service = _FakeDomains(pages: [_page(const [])]);
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: DomainCategoryScreen(domains: service, category: _cat()),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('No discussions in this category yet'), findsOneWidget);
  });

  testWidgets('tapping a thread opens it via the builder seam', (tester) async {
    final service = _FakeDomains(pages: [_page([_threadJson()])]);
    final opened = <int>[];

    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: DomainCategoryScreen(
        domains: service,
        category: _cat(),
        threadBuilder: (thread) {
          opened.add(thread.post.id);
          return const Scaffold(body: Text('THREAD SCREEN'));
        },
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('A thread about the new update'));
    await tester.pumpAndSettle();
    expect(opened, [218]);
    expect(find.text('THREAD SCREEN'), findsOneWidget);
  });

  testWidgets('error on first load shows retry', (tester) async {
    final failing = _FailingDomains();
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: DomainCategoryScreen(domains: failing, category: _cat()),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Failed'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}

class _FailingDomains extends DomainsService {
  _FailingDomains()
      : super(
            ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  @override
  Future<DomainThreadPage> threads(int categoryId,
      {int limit = 20, int offset = 0}) async {
    throw const ApiException('Failed to load discussions.');
  }
}
