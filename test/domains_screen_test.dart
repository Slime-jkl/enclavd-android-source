import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/domains_service.dart';
import 'package:enclavd/screens/domains_screen.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/shimmer.dart';

/// Fake service with canned board responses (no sockets under flutter test).
class _FakeDomains extends DomainsService {
  _FakeDomains({this.flat})
      : super(ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  final List<DomainCategory>? flat;

  /// When set, board() waits on this — lets tests observe the loading state.
  Completer<void>? gate;

  @override
  Future<List<DomainCategory>> board() async {
    final g = gate;
    if (g != null) await g.future;
    return flat ?? const [];
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
  String? description,
  String icon = 'fa-masks-theater',
  String color = '#f59e0b',
  int postCount = 2,
  String? lastPostAt,
  String? lastPostAuthor,
}) =>
    DomainCategory(
      id: id,
      name: name,
      slug: name.toLowerCase().replaceAll(' ', '-'),
      parent: parent == null ? null : int.parse(parent),
      displayOrder: id,
      description: description,
      icon: icon,
      color: color,
      postCount: postCount,
      lastPostAt: lastPostAt,
      lastPostAuthor: lastPostAuthor,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // audioplayers has no platform channel under flutter test — the like
    // sound would throw an unhandled MissingPluginException.
    SoundService.muted = true;
  });

  Widget wrap(Widget child) => MaterialApp(
        theme: buildEnclavdTheme(),
        home: Scaffold(body: child),
      );

  testWidgets('shows skeleton cards while the board loads', (tester) async {
    final gate = Completer<void>();
    final service = _FakeDomains(
        flat: [_cat(id: 1, name: 'General', icon: 'fa-lightbulb')])
      ..gate = gate;

    await tester.pumpWidget(wrap(DomainsScreen(domains: service)));
    expect(find.byType(ShimmerBox), findsWidgets);
    expect(find.text('Domains of Discussion'), findsNothing);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Domains of Discussion'), findsOneWidget);
  });

  testWidgets('renders root categories with children and activity',
      (tester) async {
    final service = _FakeDomains(flat: [
      _cat(
        id: 3,
        name: 'Entertainment',
        description: 'Movies, music, gaming',
        postCount: 5,
        lastPostAt: '2026-08-12 12:00:00',
        lastPostAuthor: 'Developer',
      ),
      _cat(
          id: 5,
          name: 'Movies & TV',
          parent: '3',
          icon: 'fa-film',
          color: '#a78bfa',
          postCount: 1,
          lastPostAt: '2026-08-11 09:00:00',
          lastPostAuthor: 'Cinephile'),
      _cat(
          id: 6,
          name: 'Music',
          parent: '3',
          icon: 'fa-music',
          color: '#ec4899',
          postCount: 2),
    ]);

    await tester.pumpWidget(wrap(DomainsScreen(domains: service)));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Domains of Discussion'), findsOneWidget);
    expect(find.text('Entertainment'), findsOneWidget);
    // Children rows render inside the root card.
    expect(find.text('Movies & TV'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    // Activity line on the child with activity: "Last: Aug 11, 2026 by
    // @Cinephile".
    expect(find.textContaining('Last:'), findsOneWidget);
    expect(find.textContaining('@Cinephile'), findsOneWidget);
    // Post counts.
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('empty board shows the empty state', (tester) async {
    final service = _FakeDomains(flat: const []);
    await tester.pumpWidget(wrap(DomainsScreen(domains: service)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('No domains yet'), findsOneWidget);
  });

  testWidgets('tapping a root category opens it via the builder seam',
      (tester) async {
    final service = _FakeDomains(
        flat: [_cat(id: 1, name: 'General', icon: 'fa-lightbulb')]);
    final opened = <int>[];

    await tester.pumpWidget(wrap(DomainsScreen(
      domains: service,
      categoryBuilder: (category) {
        opened.add(category.id);
        return const Scaffold(body: Text('CATEGORY SCREEN'));
      },
    )));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    expect(opened, [1]);
    expect(find.text('CATEGORY SCREEN'), findsOneWidget);
  });

  testWidgets('tapping a CHILD row opens the CHILD, not the root',
      (tester) async {
    final service = _FakeDomains(flat: [
      _cat(id: 3, name: 'Entertainment'),
      _cat(id: 5, name: 'Movies & TV', parent: '3'),
    ]);
    final opened = <int>[];

    await tester.pumpWidget(wrap(DomainsScreen(
      domains: service,
      categoryBuilder: (category) {
        opened.add(category.id);
        return const Scaffold(body: Text('CATEGORY SCREEN'));
      },
    )));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Movies & TV'));
    await tester.pumpAndSettle();
    expect(opened, [5], reason: 'child taps must open the child category');
  });
}
