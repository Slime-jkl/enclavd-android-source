import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';

/// In-memory store for tests (the real one is SharedPreferences-backed).
class MemorySessionStore implements SessionStore {
  MemorySessionStore([List<SessionCookie>? seed]) : _cookies = seed ?? [];

  List<SessionCookie> _cookies;

  @override
  Future<List<SessionCookie>> load() async => List.of(_cookies);

  @override
  Future<void> save(List<SessionCookie> cookies) async =>
      _cookies = List.of(cookies);

  @override
  Future<void> clear() async => _cookies = [];

  List<SessionCookie> get contents => _cookies;
}

/// Local HTTP server + ApiClient harness. Exercises the REAL socket path:
/// cookie capture, cookie re-send, redirects, form encoding, JSON parsing.
class Harness {
  Harness._(this.server, this.client);

  final HttpServer server;
  final ApiClient client;
  final List<HttpRequest> requests = [];

  /// Starts a server with a handler closure. The closure receives the
  /// request and must respond (write + close).
  static Future<Harness> start(
    Future<void> Function(HttpRequest req) handler, {
    List<SessionCookie> seedCookies = const [],
    SessionStore? store,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final effectiveStore = store ?? MemorySessionStore(seedCookies);
    final api = ApiClient(
      store: effectiveStore,
      apiBaseUrl: 'http://127.0.0.1:${server.port}',
      httpClientFactory: () {
        final c = HttpClient();
        c.userAgent = 'EnclavdNative/1.0';
        return c;
      },
    );
    final harness = Harness._(server, api);
    server.listen((req) async {
      harness.requests.add(req);
      try {
        await handler(req);
      } catch (e) {
        req.response.statusCode = 500;
        req.response.write('handler error: $e');
        await req.response.close();
      }
    });
    return harness;
  }

  static void respond(
    HttpRequest req, {
    int status = 200,
    Map<String, String> headers = const {},
    String body = '',
    String? setCookie,
  }) {
    headers.forEach(req.response.headers.set);
    if (setCookie != null) req.response.headers.set('set-cookie', setCookie);
    req.response.statusCode = status;
    if (body.isNotEmpty) req.response.write(body);
    req.response.close();
  }

  Future<void> close() async {
    await server.close(force: true);
  }
}

void main() {
  test('captures Set-Cookie and re-sends it on the next request', () async {
    final h = await Harness.start((req) async {
      if (req.uri.path == '/login') {
        Harness.respond(
          req,
          setCookie: 'enclavd_sid=abc123; Path=/; HttpOnly; Secure',
          body: '<form><input name="login_token" value="tok1"></form>',
        );
      } else if (req.uri.path == '/me') {
        Harness.respond(req, body: '{"success":true,"user":{"id":1}}');
      } else {
        Harness.respond(req, status: 404);
      }
    });

    final page = await h.client.getPage('/login');
    expect(page.status, 200);
    expect(page.body, contains('tok1'));
    expect(h.client.hasSession, isTrue);
    expect(h.client.sessionCookies.single.name, 'enclavd_sid');
    expect(h.client.sessionCookies.single.value, 'abc123');

    // Second request must carry the cookie back.
    await h.client.getJson('/me');
    final meReq = h.requests.last;
    expect(meReq.headers.value('cookie'), 'enclavd_sid=abc123');

    await h.close();
  });

  test('cookie jar persists and restores via the store', () async {
    final store = MemorySessionStore();
    final h = await Harness.start(
      (req) async {
        Harness.respond(req, setCookie: 'enclavd_sid=xyz; Path=/', body: 'ok');
      },
      store: store,
    );

    await h.client.getPage('/');
    expect(h.client.hasSession, isTrue);
    expect(store.contents.single.value, 'xyz'); // persisted on capture

    // Simulate app restart: a NEW client restored from the same store.
    final api2 = ApiClient(
      store: MemorySessionStore(store.contents),
      apiBaseUrl: 'http://127.0.0.1:${h.server.port}',
      httpClientFactory: () {
        final c = HttpClient();
        c.userAgent = 'EnclavdNative/1.0';
        return c;
      },
    );
    await api2.restoreSession();
    expect(api2.hasSession, isTrue);
    expect(api2.sessionCookies.single.value, 'xyz');

    await h.close();
  });

  test('postForm keeps the 302 Location (auth outcome signal)', () async {
    final h = await Harness.start((req) async {
      if (req.method == 'POST' && req.uri.path == '/auth') {
        Harness.respond(
          req,
          status: 302,
          headers: {'location': '/feed'},
          setCookie: 'enclavd_sid=session1; Path=/',
        );
      } else {
        Harness.respond(req, status: 200, body: '<html>feed</html>');
      }
    });

    final resp = await h.client.postForm('/auth', {
      'email': 'dev@dev.dev',
      'password': 'pw',
      'login_token': 'tok1',
    });

    // The 302 must survive so the caller can read the outcome.
    expect(resp.status, 302);
    expect(resp.location, '/feed');
    expect(h.client.hasSession, isTrue);

    await h.close();
  });

  test('getPage follows same-host redirects (GET /feed → /feed/)', () async {
    final h = await Harness.start((req) async {
      if (req.uri.path == '/feed' && !req.uri.path.endsWith('/')) {
        Harness.respond(req, status: 301, headers: {'location': '/feed/'});
      } else if (req.uri.path == '/feed/') {
        Harness.respond(req,
            body: '<meta name="csrf-token" content="csrf123">');
      } else {
        Harness.respond(req, status: 404);
      }
    });

    final page = await h.client.getPage('/feed');
    expect(page.status, 200);
    expect(page.body, contains('csrf123'));

    await h.close();
  });

  test('getJson throws ApiException with server error message on 4xx/5xx',
      () async {
    final h = await Harness.start((req) async {
      Harness.respond(
        req,
        status: 401,
        body: '{"error":"Not authenticated"}',
      );
    });

    await expectLater(
      h.client.getJson('/api/v1/posts'),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', 'Not authenticated')
          .having((e) => e.status, 'status', 401)),
    );

    await h.close();
  });

  test('getJson parses the feed shape (posts + keyset cursor)', () async {
    final h = await Harness.start((req) async {
      Harness.respond(
        req,
        body: jsonEncode({
          'success': true,
          'posts': [
            {
              'id': 218,
              'content': 'hello',
              'created_at': '2026-08-12 10:32:59',
              'feed_score': -36,
              'like_count': 1,
              'comment_count': 0,
              'user_liked': true,
              'warning_count': 0,
              'username': 'Developer',
              'profile_picture_url': '/public/avatars/a.jpg',
              'personality_type': 'INTJ',
              'is_active': 'true',
              'rank': 'SysOp',
              'image': '7275a6ccb83c90bbf5fd55c92ebcebe4.jpg',
            }
          ],
          'has_more': true,
          'last_score': -5770.9,
          'last_id': 157,
        }),
      );
    });

    final json = await h.client.getJson('/api/v1/posts');
    expect(json['success'], isTrue);
    final post = (json['posts'] as List).first as Map<String, dynamic>;
    expect(post['id'], 218);
    expect(post['user_liked'], isTrue);
    expect(json['last_score'], -5770.9);

    await h.close();
  });

  test('postForm encodes the form body URL-safe', () async {
    String? body;
    final h = await Harness.start((req) async {
      body = await utf8.decoder.bind(req).join();
      Harness.respond(req, status: 302, headers: {'location': '/login'});
    });

    await h.client.postForm('/process_register', {
      'username': 'a b',
      'email': 'x@y.z',
    });
    // Form-urlencoded: space → '+' (PHP urldecode handles it), @ → %40.
    expect(body, 'username=a+b&email=x%40y.z');

    await h.close();
  });
}
