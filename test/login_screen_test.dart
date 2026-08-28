import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/auth_service.dart';
import 'package:enclavd/api/site_config_service.dart';
import 'package:enclavd/screens/login_screen.dart';

import 'api_client_test.dart' show MemorySessionStore;

class _FakeAuth extends AuthService {
  _FakeAuth()
      : super(
          ApiClient(store: MemorySessionStore(), apiBaseUrl: 'http://127.0.0.1:1'),
          apiBaseUrl: 'http://127.0.0.1:1',
        );

  LoginResult Function() onLogin =
      () => const LoginResult(LoginOutcome.success, '');
  CurrentUser? meUser;
  String? lastCaptchaAnswer;

  @override
  Future<LoginResult> login({
    required String email,
    required String password,
    bool rememberMe = false,
    String? captchaAnswer,
  }) async {
    lastCaptchaAnswer = captchaAnswer;
    return onLogin();
  }

  @override
  Future<CurrentUser?> me() async => meUser;
}

class _FakeConfig extends SiteConfigService {
  _FakeConfig()
      : super(
          ApiClient(store: MemorySessionStore(), apiBaseUrl: 'http://127.0.0.1:1'),
        );

  SiteConfig config = const SiteConfig(
    isInvitationRequired: false,
    maintenance: MaintenanceConfig(
      enabled: false,
      allowedRanks: [],
      reason: '',
      estTime: '',
    ),
    rateLimit: RateLimitConfig(
      enabled: true,
      cooldowns: {},
      captchaAt: 3,
      lockAt: 10,
      lockDuration: 900,
      appliesTo: ['login'],
    ),
  );
  RateLimitState state = const RateLimitState(
    blocked: false,
    cooldown: 0,
    needsCaptcha: false,
    captchaOk: false,
    lockRemaining: 0,
  );

  @override
  Future<SiteConfig> fetch() async => config;

  @override
  Future<RateLimitState> rateState(String context) async => state;
}

const _normal = CurrentUser(
  id: 1,
  username: 'u',
  profilePictureUrl: '/a.png',
  rank: 'Member',
  personalityType: null,
  prestige: 0,
  isAdmin: false,
  dateCreated: '2025-05-14 00:00:00',
  banned: false,
  blockReason: '',
);

const _banned = CurrentUser(
  id: 2,
  username: 'b',
  profilePictureUrl: '/a.png',
  rank: 'Member',
  personalityType: null,
  prestige: 0,
  isAdmin: false,
  dateCreated: '2025-05-14 00:00:00',
  banned: true,
  blockReason: 'Spam',
);

void main() {
  testWidgets('password field has a visibility toggle', (tester) async {
    final auth = _FakeAuth();
    final config = _FakeConfig();

    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(auth: auth, siteConfig: config),
    ));
    await tester.pump();

    EditableText passwordText() => tester.widget<EditableText>(
        find.descendant(
            of: find.byType(TextFormField).at(1),
            matching: find.byType(EditableText)));
    expect(passwordText().obscureText, isTrue);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(passwordText().obscureText, isFalse);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(passwordText().obscureText, isTrue);
  });

  testWidgets('cooldown: countdown banner shown, submit disabled',
      (tester) async {
    final auth = _FakeAuth();
    final config = _FakeConfig()
      ..state = const RateLimitState(
        blocked: false,
        cooldown: 30,
        needsCaptcha: false,
        captchaOk: false,
        lockRemaining: 0,
      );

    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(auth: auth, siteConfig: config),
    ));
    await tester.pump();

    expect(find.textContaining('second(s)'), findsOneWidget);
    final button =
        tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull, reason: 'submit locked during cooldown');
  });

  testWidgets('IP blocked: minutes banner, submit disabled', (tester) async {
    final auth = _FakeAuth();
    final config = _FakeConfig()
      ..state = const RateLimitState(
        blocked: true,
        cooldown: 0,
        needsCaptcha: false,
        captchaOk: false,
        lockRemaining: 900,
      );

    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(auth: auth, siteConfig: config),
    ));
    await tester.pump();

    expect(find.textContaining('minute(s)'), findsOneWidget);
    final button =
        tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets(
      'rate-limited failure: the live countdown replaces the static '
      'flash copy (no double banner)', (tester) async {
    // auth.php appends "Please wait N second(s)..." to the failure flash;
    // that static text renders as a second, frozen red banner beside the countdown.
    final auth = _FakeAuth()
      ..onLogin = () => const LoginResult(
            LoginOutcome.failure,
            'Invalid e-mail or password. Please wait 5 second(s) before '
            'trying again.',
          );
    final config = _FakeConfig()
      ..state = const RateLimitState(
        blocked: false,
        cooldown: 5,
        needsCaptcha: false,
        captchaOk: false,
        lockRemaining: 0,
      );

    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(auth: auth, siteConfig: config),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.c');
    await tester.enterText(find.byType(TextFormField).at(1), 'pw');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pump(); // failure banner frame
    await tester.pump(); // rate state lands

    // Exactly ONE red banner: the live countdown; the frozen flash copy is gone.
    expect(find.textContaining('second(s)'), findsOneWidget);
    expect(find.textContaining('Invalid e-mail or password'), findsNothing);
  });

  testWidgets('non-rate failure keeps the server message banner',
      (tester) async {
    final auth = _FakeAuth()
      ..onLogin = () => const LoginResult(
            LoginOutcome.failure,
            'Invalid e-mail or password.',
          );
    final config = _FakeConfig(); // cooldown 0, no rate banner

    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(auth: auth, siteConfig: config),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.c');
    await tester.enterText(find.byType(TextFormField).at(1), 'pw');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Invalid e-mail or password.'), findsOneWidget);
    expect(find.textContaining('second(s)'), findsNothing);
  });

  testWidgets(
      'captcha required: question shown, answer sent with the login POST',
      (tester) async {
    final auth = _FakeAuth()..meUser = _normal;
    final config = _FakeConfig()
      ..state = const RateLimitState(
        blocked: false,
        cooldown: 0,
        needsCaptcha: true,
        captchaOk: false,
        lockRemaining: 0,
        captchaQuestion: 'How many sides does a triangle have?',
      );

    await tester.pumpWidget(MaterialApp(
      routes: {
        FeedScreenPlaceholder.routeName: (_) =>
            const Scaffold(body: Text('FEED-PLACEHOLDER')),
      },
      home: LoginScreen(auth: auth, siteConfig: config),
    ));
    await tester.pump();

    expect(find.text('How many sides does a triangle have?'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.c');
    await tester.enterText(find.byType(TextFormField).at(1), 'pw');
    await tester.enterText(find.byType(TextFormField).at(2), '3');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(auth.lastCaptchaAnswer, '3');
  });

  testWidgets('captcha required + empty answer -> validation blocks submit',
      (tester) async {
    final auth = _FakeAuth();
    final config = _FakeConfig()
      ..state = const RateLimitState(
        blocked: false,
        cooldown: 0,
        needsCaptcha: true,
        captchaOk: false,
        lockRemaining: 0,
        captchaQuestion: 'What is 5 plus 3?',
      );

    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(auth: auth, siteConfig: config),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.c');
    await tester.enterText(find.byType(TextFormField).at(1), 'pw');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pump();

    expect(find.text('Answer the question above'), findsOneWidget);
    expect(auth.lastCaptchaAnswer, isNull, reason: 'never submitted');
  });

  testWidgets('post-login gate: banned -> ban screen', (tester) async {
    final auth = _FakeAuth()..meUser = _banned;
    final config = _FakeConfig();

    await tester.pumpWidget(MaterialApp(
      routes: {
        BanScreenPlaceholder.routeName: (_) =>
            const Scaffold(body: Text('BAN-PLACEHOLDER')),
      },
      home: LoginScreen(auth: auth, siteConfig: config),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.c');
    await tester.enterText(find.byType(TextFormField).at(1), 'pw');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('BAN-PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('post-login gate: maintenance on + rank not allowed -> '
      'maintenance screen', (tester) async {
    final auth = _FakeAuth()..meUser = _normal;
    final config = _FakeConfig()
      ..config = const SiteConfig(
        isInvitationRequired: false,
        maintenance: MaintenanceConfig(
          enabled: true,
          allowedRanks: ['SysOp', 'Admin'],
          reason: 'DB upgrade',
          estTime: 'In 2 hours',
        ),
        rateLimit: RateLimitConfig(
          enabled: true,
          cooldowns: {},
          captchaAt: 3,
          lockAt: 10,
          lockDuration: 900,
          appliesTo: ['login'],
        ),
      );

    await tester.pumpWidget(MaterialApp(
      routes: {
        MaintenancePlaceholder.routeName: (_) =>
            const Scaffold(body: Text('MAINT-PLACEHOLDER')),
      },
      home: LoginScreen(auth: auth, siteConfig: config),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.c');
    await tester.enterText(find.byType(TextFormField).at(1), 'pw');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('MAINT-PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('post-login gate: maintenance on + allowed rank -> feed',
      (tester) async {
    const admin = CurrentUser(
      id: 3,
      username: 'a',
      profilePictureUrl: '/a.png',
      rank: 'SysOp',
      personalityType: null,
      prestige: 0,
      isAdmin: true,
      dateCreated: '2025-05-14 00:00:00',
      banned: false,
      blockReason: '',
    );
    final auth = _FakeAuth()..meUser = admin;
    final config = _FakeConfig()
      ..config = const SiteConfig(
        isInvitationRequired: false,
        maintenance: MaintenanceConfig(
          enabled: true,
          allowedRanks: ['SysOp', 'Admin'],
          reason: 'DB upgrade',
          estTime: 'In 2 hours',
        ),
        rateLimit: RateLimitConfig(
          enabled: true,
          cooldowns: {},
          captchaAt: 3,
          lockAt: 10,
          lockDuration: 900,
          appliesTo: ['login'],
        ),
      );

    await tester.pumpWidget(MaterialApp(
      routes: {
        FeedScreenPlaceholder.routeName: (_) =>
            const Scaffold(body: Text('FEED-PLACEHOLDER')),
      },
      home: LoginScreen(auth: auth, siteConfig: config),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.c');
    await tester.enterText(find.byType(TextFormField).at(1), 'pw');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('FEED-PLACEHOLDER'), findsOneWidget);
  });
}

// Route-name stand-ins so the login screen's gate navigation has targets.
class FeedScreenPlaceholder {
  static const routeName = '/feed';
}

class BanScreenPlaceholder {
  static const routeName = '/ban';
}

class MaintenancePlaceholder {
  static const routeName = '/maintenance';
}
