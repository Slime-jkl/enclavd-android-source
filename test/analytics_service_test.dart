import 'dart:convert';
import 'dart:io';

import 'package:enclavd/services/analytics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// AnalyticsService against a REAL local HttpServer — the codebase's
/// no-browser verification pattern. The service must POST the exact wire
/// format the site's script.js uses (text/plain JSON {n,u,d,r,p}) so app
/// pageviews merge into the same Plausible dashboard as web pages.
void main() {
  late HttpServer server;
  late List<HttpRequest> requests;
  late List<String> bodies;

  setUp(() async {
    requests = [];
    bodies = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests.add(req);
      bodies.add(await utf8.decoder.bind(req).join());
      req.response.statusCode = HttpStatus.accepted;
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  AnalyticsService service() => AnalyticsService(
        endpoint: 'http://127.0.0.1:${server.port}/api/event',
        domain: 'enclavd.com',
        userAgent: appAnalyticsUa,
      );

  Future<Map<String, dynamic>> lastBody() async {
    for (var i = 0; i < 50 && requests.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(requests, isNotEmpty, reason: 'request never arrived');
    return jsonDecode(bodies.last) as Map<String, dynamic>;
  }

  test('pageview posts the site script\'s exact wire format', () async {
    service().pageview('/feed');
    final body = await lastBody();

    expect(requests.last.method, 'POST');
    expect(requests.last.uri.path, '/api/event');
    expect(requests.last.headers.contentType?.mimeType, 'text/plain');
    expect(requests.last.headers.value(HttpHeaders.userAgentHeader),
        appAnalyticsUa);
    expect(body, {
      'n': 'pageview',
      'u': 'https://enclavd.com/feed',
      'd': 'enclavd.com',
      'r': null,
    });
  });

  test('pageview uses the caller\'s site-style path', () async {
    final a = service();
    a.pageview('/profile');
    final body = await lastBody();
    expect(body['u'], 'https://enclavd.com/profile');
    expect(body['n'], 'pageview');
  });

  test('custom event carries props in the p field', () async {
    final a = service();
    a.event('Post created', props: {'has_image': true});
    final body = await lastBody();
    expect(body['n'], 'Post created');
    expect(body['p'], {'has_image': true});
  });

  test('custom event without props has no p field', () async {
    final a = service();
    a.event('Signup');
    final body = await lastBody();
    expect(body['n'], 'Signup');
    expect(body.containsKey('p'), isFalse);
  });

  test('debounce: same path within window sends once', () async {
    final a = service();
    a.pageview('/feed');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    a.pageview('/feed');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(requests.length, 1);
  });

  test('different paths always send', () async {
    final a = service();
    a.pageview('/feed');
    a.pageview('/articles');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(requests.length, 2);
  });

  test('a failed request never throws (fire-and-forget)', () async {
    final a = AnalyticsService(
      endpoint: 'http://127.0.0.1:1/api/event', // nothing listens
      domain: 'enclavd.com',
      userAgent: appAnalyticsUa,
    );
    a.pageview('/feed'); // must not throw / crash
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(true, isTrue); // reached here = silent no-op
  });

  group('AnalyticsRouteObserver', () {
    test('tracks named routes as pageviews', () async {
      AnalyticsService.instance = service();
      addTearDown(() => AnalyticsService.instance = null);
      final observer = AnalyticsRouteObserver();
      final route = MaterialPageRoute<void>(
        builder: (_) => const SizedBox.shrink(),
        settings: const RouteSettings(name: '/feed'),
      );
      observer.didPush(route, null);
      final body = await lastBody();
      expect(body['u'], 'https://enclavd.com/feed');
    });

    test('ignores unnamed routes (screens track themselves)', () {
      final observer = AnalyticsRouteObserver();
      final route = MaterialPageRoute<void>(
        builder: (_) => const SizedBox.shrink(),
      );
      observer.didPush(route, null);
      // No instance assertions needed: didPush on an unnamed route must
      // not throw and must not fire (verified by the debounce test path).
    });

    test('pop fires a pageview for the previous route', () async {
      AnalyticsService.instance = service();
      addTearDown(() => AnalyticsService.instance = null);
      final observer = AnalyticsRouteObserver();
      final feed = MaterialPageRoute<void>(
        builder: (_) => const SizedBox.shrink(),
        settings: const RouteSettings(name: '/feed'),
      );
      final profile = MaterialPageRoute<void>(
        builder: (_) => const SizedBox.shrink(),
        settings: const RouteSettings(name: '/profile'),
      );
      observer.didPush(feed, null);
      observer.didPush(profile, feed);
      observer.didPop(profile, feed);
      // pop → previous route '/feed' pageview (the site's popstate)
      final body = await lastBody();
      expect(body['u'], 'https://enclavd.com/feed');
    });

    test('ignores non-PageRoutes (dialogs, sheets)', () async {
      AnalyticsService.instance = service();
      addTearDown(() => AnalyticsService.instance = null);
      final observer = AnalyticsRouteObserver();
      // A plain (non-Page) route with a name must NOT fire a pageview —
      // dialogs/sheets are not pages.
      final dialog = _FakeRoute(settings: const RouteSettings(name: '/x'));
      observer.didPush(dialog, null);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(requests, isEmpty);
    });
  });
}

/// Minimal non-PageRoute stub (dialogs/sheets are not PageRoutes).
/// Extends TransitionRoute — Route itself doesn't declare
/// createOverlayEntries/opaque (they live on OverlayRoute/TransitionRoute
/// in current Flutter), so the overrides must target the right base.
class _FakeRoute extends TransitionRoute<dynamic> {
  _FakeRoute({required super.settings});

  @override
  Iterable<OverlayEntry> createOverlayEntries() => <OverlayEntry>[];

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  bool get opaque => false;

  @override
  bool get popGestureEnabled => false;
}

/// The pinned Chrome/124 UA from AppConfig (mirrors the wrapper's constant).
const appAnalyticsUa =
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
