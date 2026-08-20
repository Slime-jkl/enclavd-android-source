import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/auth_service.dart';

import 'api_client_test.dart' show Harness, MemorySessionStore;

void main() {
  group('AuthService.login', () {
    test('success: 302 to /feed → LoginOutcome.success, session captured',
        () async {
      var loginPageHits = 0;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/login' && req.method == 'GET') {
          loginPageHits++;
          Harness.respond(
            req,
            body:
                '<form><input type="hidden" name="login_token" value="tok-abc"></form>',
          );
        } else if (req.uri.path == '/auth' && req.method == 'POST') {
          final body = await utf8.decoder.bind(req).join();
          expect(body, contains('email=dev%40dev.dev'));
          expect(body, contains('login_token=tok-abc'));
          Harness.respond(
            req,
            status: 302,
            headers: {'location': '/feed'},
            setCookie: 'enclavd_sid=sess-1; Path=/',
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final service = AuthService(h.client, apiBaseUrl: h.client.apiBaseUrl);
      final result = await service.login(
        email: 'dev@dev.dev',
        password: 'pw',
        rememberMe: true,
      );

      expect(result.outcome, LoginOutcome.success);
      expect(loginPageHits, 1); // token fetched exactly once
      expect(h.client.hasSession, isTrue);
      expect(h.client.sessionCookies.single.value, 'sess-1');

      await h.close();
    });

    test('failure: 302 back to /login → flash message parsed from the page',
        () async {
      var loginHits = 0;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/auth' && req.method == 'POST') {
          Harness.respond(req, status: 302, headers: {'location': '/login'});
        } else if (req.uri.path == '/login') {
          loginHits++;
          if (loginHits == 1) {
            // First GET: the login form with the token.
            Harness.respond(
              req,
              body:
                  '<form><input type="hidden" name="login_token" value="tok-abc"></form>',
            );
          } else {
            // Second GET (after the 302): the flash error renders here.
            Harness.respond(
              req,
              body:
                  '<div class="info-red" id="rl-cooldown-banner"><p>Invalid e-mail or password.</p></div>',
            );
          }
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final service = AuthService(h.client, apiBaseUrl: h.client.apiBaseUrl);
      final result = await service.login(email: 'x@y.z', password: 'wrong');

      expect(result.outcome, LoginOutcome.failure);
      expect(result.message, 'Invalid e-mail or password.');

      await h.close();
    });

    test('missing login_token field → friendly failure, no crash', () async {
      final h = await Harness.start((req) async {
        Harness.respond(req, body: '<html>no form here</html>');
      });

      final service = AuthService(h.client, apiBaseUrl: h.client.apiBaseUrl);
      final result = await service.login(email: 'a@b.c', password: 'pw');

      expect(result.outcome, LoginOutcome.failure);
      expect(result.message, contains('login session'));

      await h.close();
    });
  });

  group('AuthService.register', () {
    test('success: 302 to /login → verification message', () async {
      String? body;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/process_register') {
          body = await utf8.decoder.bind(req).join();
          Harness.respond(req, status: 302, headers: {'location': '/login'});
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final service = AuthService(h.client, apiBaseUrl: h.client.apiBaseUrl);
      final message = await service.register(
        username: 'newuser',
        email: 'new@dev.dev',
        password: 'secret1',
        acceptPrivacy: true,
        acceptTerms: true,
      );

      expect(message, contains('Check your email'));
      expect(body, contains('username=newuser'));
      expect(body, contains('privacy_policy=on'));
      expect(body, contains('terms=on'));

      await h.close();
    });

    test('failure: 302 back to /register → validation errors parsed', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/process_register') {
          Harness.respond(req, status: 302, headers: {'location': '/register'});
        } else if (req.uri.path == '/register') {
          Harness.respond(
            req,
            body:
                '<div class="info-red" id="rl-cooldown-banner">* Username must be between 3-20 characters<br>* Passwords do not match</div>',
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final service = AuthService(h.client, apiBaseUrl: h.client.apiBaseUrl);
      final message = await service.register(
        username: 'x',
        email: 'bad',
        password: 'pw1',
      );

      expect(message, contains('Username must be between 3-20 characters'));

      await h.close();
    });
  });

  group('AuthService.me + logout', () {
    test('me() returns null on 401 (dead session)', () async {
      final h = await Harness.start((req) async {
        Harness.respond(req,
            status: 401, body: '{"error":"Not authenticated"}');
      });

      final service = AuthService(h.client, apiBaseUrl: h.client.apiBaseUrl);
      expect(await service.me(), isNull);

      await h.close();
    });

    test('me() parses the user object on 200', () async {
      final h = await Harness.start((req) async {
        Harness.respond(
          req,
          body: jsonEncode({
            'success': true,
            'user': {
              'id': 1,
              'username': 'Developer',
              'profile_picture_url': '/public/avatars/a.jpg',
              'rank': 'SysOp',
              'personality_type': 'INTJ',
              'prestige': 11,
              'is_admin': true,
              'date_created': '2024-11-20 21:05:59',
            }
          }),
        );
      });

      final service = AuthService(h.client, apiBaseUrl: h.client.apiBaseUrl);
      final user = await service.me();
      expect(user, isNotNull);
      expect(user!.username, 'Developer');
      expect(user.rank, 'SysOp');
      expect(user.isAdmin, isTrue);
      expect(user.avatarUrl('https://enclavd.com'),
          'https://enclavd.com/public/avatars/a.jpg');

      await h.close();
    });

    test('logout clears the local session even if the server call fails',
        () async {
      final store = MemorySessionStore([
        const SessionCookie(name: 'enclavd_sid', value: 'x'),
        const SessionCookie(name: 'sid', value: 'y'),
      ]);
      final h = await Harness.start(
        (req) async {
          if (req.uri.path == '/feed') {
            Harness.respond(
              req,
              body: '<meta name="csrf-token" content="csrf-tok">',
            );
          } else if (req.uri.path == '/api/v1/auth') {
            Harness.respond(req, status: 500, body: '{"error":"boom"}');
          } else {
            Harness.respond(req, status: 404);
          }
        },
        store: store,
      );

      final service = AuthService(h.client, apiBaseUrl: h.client.apiBaseUrl);
      await service.logout();
      expect(store.contents, isEmpty);

      await h.close();
    });
  });

  group('resolveMediaUrl', () {
    test('avatars are root-relative → prefixed with base', () {
      expect(
        resolveMediaUrl('https://enclavd.com',
            avatarPath: '/public/avatars/a.jpg'),
        'https://enclavd.com/public/avatars/a.jpg',
      );
    });

    test('gallery images are bare filenames → /public/gallery/', () {
      expect(
        resolveMediaUrl('https://enclavd.com', galleryName: 'abc.jpg'),
        'https://enclavd.com/public/gallery/abc.jpg',
      );
    });

    test('no image → default avatar', () {
      expect(
        resolveMediaUrl('https://enclavd.com'),
        'https://enclavd.com/assets/default-avatar.png',
      );
    });
  });
}
