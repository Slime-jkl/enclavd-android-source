// Live end-to-end verification against the dev stack (https://localhost).
// CLI tool: stdout reporting is the point, so print is fine here.
// ignore_for_file: avoid_print
//
// Uses the REAL ApiClient/AuthService/FeedService code paths — the same
// classes the app runs — with an in-memory cookie store and a client that
// tolerates the dev stack's self-signed cert. NOT a unit test: it requires
// the dev stack to be up and a dev account (dev@dev.dev / Enclavd2026!).
//
// Run: flutter pub get && dart run tool/verify_live.dart
//
// Exit 0 = the full login → me → feed → next-page flow works with the
// native client's session handling (cookie jar + UA binding).

import 'dart:io';

import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/auth_service.dart';
import 'package:enclavd/api/feed_service.dart';

class MemStore implements SessionStore {
  List<SessionCookie> cookies = const [];
  @override
  Future<List<SessionCookie>> load() async => cookies;
  @override
  Future<void> save(List<SessionCookie> c) async => cookies = List.of(c);
  @override
  Future<void> clear() async => cookies = [];
}

Future<void> main() async {
  const base = 'https://localhost';
  final store = MemStore();
  final api = ApiClient(
    store: store,
    apiBaseUrl: base,
    httpClientFactory: () {
      final c = HttpClient();
      c.userAgent = 'EnclavdNative/1.0';
      c.connectionTimeout = const Duration(seconds: 15);
      c.badCertificateCallback = (cert, host, port) => true; // dev self-signed
      return c;
    },
  );
  await api.restoreSession();

  final auth = AuthService(api, apiBaseUrl: base);
  final feed = FeedService(api);

  var failures = 0;
  void check(String label, bool ok, [String? detail]) {
    print('${ok ? 'PASS' : 'FAIL'}  $label${detail != null ? ' — $detail' : ''}');
    if (!ok) failures++;
  }

  // ── 1. Login (login_token dance + 302 verdict + cookie capture) ────────
  final token = await auth.fetchLoginToken();
  check('GET /login returns a login_token', token != null && token.isNotEmpty);
  check('session cookie sid captured', api.sessionCookies.any((c) => c.name == 'sid'));

  final login = await auth.login(email: 'dev@dev.dev', password: 'Enclavd2026!');
  check('login succeeds', login.outcome == LoginOutcome.success, login.message);
  check('enclavd_sid session cookie captured',
      api.sessionCookies.any((c) => c.name == 'enclavd_sid'));
  check('jar persisted after login', store.cookies.isNotEmpty);

  // ── 2. /api/v1/me ──────────────────────────────────────────────────────
  final me = await auth.me();
  check('me() returns the user', me != null, me?.username ?? 'null');
  check('me() username matches dev account', me?.username == 'Developer',
      me?.username);

  // ── 3. Feed page 1 + keyset page 2 ─────────────────────────────────────
  final page1 = await feed.firstPage(limit: 3);
  check('feed page 1 returns posts', page1.posts.isNotEmpty,
      '${page1.posts.length} posts, has_more=${page1.hasMore}');
  final p0 = page1.posts.first;
  check('post fields populated', p0.username.isNotEmpty && p0.content.isNotEmpty,
      '#${p0.id} by ${p0.username} rank=${p0.rank}');

  if (page1.hasMore && page1.lastScore != null && page1.lastId != null) {
    final page2 = await feed.nextPage(page1, limit: 3);
    check('feed page 2 via keyset returns posts', page2.posts.isNotEmpty,
        '${page2.posts.length} posts');
    check('page 2 has no overlap with page 1',
        !page2.posts.any((p) => p.id == p0.id));
  } else {
    check('feed page 2 via keyset returns posts', true, 'skipped — no more');
  }

  // ── 4. Media URL resolution ────────────────────────────────────────────
  final avatarUrl = resolveMediaUrl(base, avatarPath: p0.profilePictureUrl);
  check('avatar URL is absolute', avatarUrl.startsWith('https://'));
  if (p0.image != null) {
    final imgUrl = resolveMediaUrl(base, galleryName: p0.image);
    check('gallery URL points at /public/gallery/',
        imgUrl.contains('/public/gallery/'), imgUrl);
  }

  // ── 5. Logout (CSRF fetch + api/v1/auth) ───────────────────────────────
  await auth.logout();
  check('logout clears the local jar', store.cookies.isEmpty);
  final afterLogout = await auth.me();
  check('session is dead after logout', afterLogout == null);

  print(failures == 0
      ? '\nALL LIVE CHECKS PASSED'
      : '\n$failures LIVE CHECK(S) FAILED');
  exit(failures == 0 ? 0 : 1);
}
