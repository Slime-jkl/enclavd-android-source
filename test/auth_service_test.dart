import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/auth_service.dart';
import 'package:enclavd/api/site_config_service.dart';

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

    test('failure: 302 back to /login (RELATIVE Location, as the server '
        'sends) → flash message parsed from the page', () async {
      var loginHits = 0;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/auth' && req.method == 'POST') {
          Harness.respond(req, status: 302, headers: {'location': 'login'});
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

    test('captcha_answer rides the POST when the limiter demands it',
        () async {
      String? body;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/login' && req.method == 'GET') {
          Harness.respond(
            req,
            body:
                '<form><input type="hidden" name="login_token" value="tok-abc"></form>',
          );
        } else if (req.uri.path == '/auth' && req.method == 'POST') {
          body = await utf8.decoder.bind(req).join();
          Harness.respond(
            req,
            status: 302,
            headers: {'location': '/feed'},
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final service = AuthService(h.client, apiBaseUrl: h.client.apiBaseUrl);
      final result = await service.login(
        email: 'dev@dev.dev',
        password: 'pw',
        captchaAnswer: '4',
      );

      expect(result.outcome, LoginOutcome.success);
      expect(body, contains('captcha_answer=4'));

      // Not demanded → no field at all.
      body = null;
      await service.login(email: 'dev@dev.dev', password: 'pw');
      expect(body, isNot(contains('captcha_answer')));

      await h.close();
    });
  });

  group('AuthService.register', () {
    test('success via api/v1/register → submitted + verification flag', () async {
      Map<String, dynamic>? jsonBody;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          // CSRF meta for the pre-auth token scrape.
          Harness.respond(req,
              body: '<meta name="csrf-token" content="csrf123">');
        } else if (req.uri.path == '/api/v1/register') {
          jsonBody = jsonDecode(await utf8.decoder.bind(req).join())
              as Map<String, dynamic>;
          Harness.respond(
            req,
            body: jsonEncode({
              'success': true,
              'requires_email_verification': true,
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final service = AuthService(h.client, apiBaseUrl: h.client.apiBaseUrl);
      final result = await service.register(
        username: 'newuser',
        email: 'new@dev.dev',
        password: 'secret1',
        acceptPrivacy: true,
        acceptTerms: true,
        birthdate: '1990-05-14',
        gender: 'MALE',
        geoCountry: 4,
        geoCity: 91,
      );

      expect(result.submitted, isTrue);
      expect(result.requiresEmailVerification, isTrue);
      expect(jsonBody, isNotNull);
      expect(jsonBody!['username'], 'newuser');
      expect(jsonBody!['email'], 'new@dev.dev');
      expect(jsonBody!['password_confirm'], 'secret1');
      expect(jsonBody!['privacy_policy'], isTrue);
      expect(jsonBody!['terms'], isTrue);
      expect(jsonBody!['birthdate'], '1990-05-14');
      expect(jsonBody!['gender'], 'MALE');
      expect(jsonBody!['geo_country'], 4);
      expect(jsonBody!['geo_city'], 91);

      await h.close();
    });

    test('422 with fields → per-field errors surface', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req,
              body: '<meta name="csrf-token" content="csrf123">');
        } else if (req.uri.path == '/api/v1/register') {
          Harness.respond(
            req,
            status: 422,
            body: jsonEncode({
              'error': 'Email already registered',
              'fields': {'email': 'Email already registered'},
            }),
          );
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final service = AuthService(h.client, apiBaseUrl: h.client.apiBaseUrl);
      final result = await service.register(
        username: 'newuser',
        email: 'taken@dev.dev',
        password: 'secret1',
      );

      expect(result.submitted, isFalse);
      expect(result.message, 'Email already registered');
      expect(result.fieldErrors['email'], 'Email already registered');
      expect(result.fieldErrors, isNotEmpty);

      await h.close();
    });

    test(
        'deploy skew: api/v1/register 404 → legacy /process_register 302 '
        'to RELATIVE "login" → success', () async {
      var legacyHits = 0;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req,
              body: '<meta name="csrf-token" content="csrf123">');
        } else if (req.uri.path == '/api/v1/register') {
          Harness.respond(req, status: 404, body: '<html>not found</html>');
        } else if (req.uri.path == '/process_register') {
          legacyHits++;
          // The REAL server sends a RELATIVE Location ("login").
          Harness.respond(req, status: 302, headers: {'location': 'login'});
        } else {
          Harness.respond(req, status: 404);
        }
      });

      final service = AuthService(h.client, apiBaseUrl: h.client.apiBaseUrl);
      final result = await service.register(
        username: 'newuser',
        email: 'new@dev.dev',
        password: 'secret1',
        acceptPrivacy: true,
        acceptTerms: true,
      );

      expect(legacyHits, 1);
      expect(result.submitted, isTrue,
          reason: 'relative "login" must be recognized as success');

      await h.close();
    });

    test(
        'legacy failure: 302 back to RELATIVE "register" → validation '
        'errors parsed from the flash page', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req,
              body: '<meta name="csrf-token" content="csrf123">');
        } else if (req.uri.path == '/api/v1/register') {
          Harness.respond(req, status: 404, body: '<html>not found</html>');
        } else if (req.uri.path == '/process_register') {
          // The REAL server sends a RELATIVE Location ("register").
          Harness.respond(
              req, status: 302, headers: {'location': 'register'});
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
      final result = await service.register(
        username: 'x',
        email: 'bad',
        password: 'pw1',
      );

      expect(result.submitted, isFalse);
      expect(result.message, contains('Username must be between 3-20 characters'));
      expect(result.fieldErrors, isEmpty,
          reason: 'legacy flash errors have no per-field structure');

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
      expect(user.banned, isFalse,
          reason: 'missing is_active defaults to not-banned');
      expect(user.avatarUrl('https://enclavd.com'),
          'https://enclavd.com/public/avatars/a.jpg');

      await h.close();
    });

    test('me() reports a banned account with its reason', () async {
      final h = await Harness.start((req) async {
        Harness.respond(
          req,
          body: jsonEncode({
            'success': true,
            'user': {
              'id': 9,
              'username': 'BarredUser',
              'profile_picture_url': '/assets/default-avatar.png',
              'rank': 'Member',
              'personality_type': null,
              'prestige': 0,
              'is_admin': false,
              'date_created': '2024-11-20 21:05:59',
              'is_active': false,
              'block_reason': 'Violated community guidelines',
            }
          }),
        );
      });

      final service = AuthService(h.client, apiBaseUrl: h.client.apiBaseUrl);
      final user = await service.me();
      expect(user, isNotNull);
      expect(user!.banned, isTrue);
      expect(user.blockReason, 'Violated community guidelines');

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

  group('resolveGate', () {
    const normal = CurrentUser(
      id: 1,
      username: 'u',
      profilePictureUrl: '/a.png',
      rank: 'Member',
      personalityType: null,
      prestige: 0,
      isAdmin: false,
      dateCreated: '2024-11-20 21:05:59',
      banned: false,
      blockReason: '',
    );
    const admin = CurrentUser(
      id: 2,
      username: 'a',
      profilePictureUrl: '/a.png',
      rank: 'SysOp',
      personalityType: null,
      prestige: 0,
      isAdmin: true,
      dateCreated: '2024-11-20 21:05:59',
      banned: false,
      blockReason: '',
    );
    const banned = CurrentUser(
      id: 3,
      username: 'b',
      profilePictureUrl: '/a.png',
      rank: 'Member',
      personalityType: null,
      prestige: 0,
      isAdmin: false,
      dateCreated: '2024-11-20 21:05:59',
      banned: true,
      blockReason: 'Spam',
    );

    Future<Gate> run(CurrentUser user, String configJson) async {
      final h = await Harness.start((req) async {
        expect(req.uri.path, '/api/v1/site_config');
        Harness.respond(req, body: configJson);
      });
      final gate = await resolveGate(user, SiteConfigService(h.client));
      await h.close();
      return gate;
    }

    test('banned user → ban, no config fetch needed', () async {
      final gate = await resolveGate(banned, SiteConfigService(
          ApiClient(store: MemorySessionStore(), apiBaseUrl: 'http://x')));
      expect(gate, Gate.ban);
    });

    test('maintenance on + rank not in the allowed list → maintenance',
        () async {
      final gate = await run(normal,
          '{"success":true,"config":{"maintenance":{"enabled":true,"allowed_ranks":["SysOp","Admin"],"reason":"R","estTime":"T"}}}');
      expect(gate, Gate.maintenance);
    });

    test('maintenance on + allowed rank → feed', () async {
      final gate = await run(admin,
          '{"success":true,"config":{"maintenance":{"enabled":true,"allowed_ranks":["SysOp","Admin"],"reason":"R","estTime":"T"}}}');
      expect(gate, Gate.feed);
    });

    test('maintenance off → feed', () async {
      final gate = await run(normal,
          '{"success":true,"config":{"maintenance":{"enabled":false,"allowed_ranks":[],"reason":"","estTime":""}}}');
      expect(gate, Gate.feed);
    });

    test('config fetch failure → feed (server still enforces)', () async {
      final h = await Harness.start((req) async {
        Harness.respond(req, status: 500, body: '{"error":"boom"}');
      });
      final gate = await resolveGate(normal, SiteConfigService(h.client));
      expect(gate, Gate.feed);
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
