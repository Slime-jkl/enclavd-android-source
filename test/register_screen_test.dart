import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/auth_service.dart';
import 'package:enclavd/api/site_config_service.dart';
import 'package:enclavd/screens/register_screen.dart';
import 'package:enclavd/screens/verify_email_screen.dart';

import 'api_client_test.dart' show MemorySessionStore;

class _FakeConfig extends SiteConfigService {
  _FakeConfig({
    required this.isInvitationRequired,
    this.requireEmailVerification = false,
    this.rateStateValue = const RateLimitState(
      blocked: false,
      cooldown: 0,
      needsCaptcha: false,
      captchaOk: false,
      lockRemaining: 0,
    ),
  }) : super(
          ApiClient(store: MemorySessionStore(), apiBaseUrl: 'http://127.0.0.1:1'),
        );

  final bool isInvitationRequired;
  final bool requireEmailVerification;
  final RateLimitState rateStateValue;

  @override
  Future<SiteConfig> fetch() async => SiteConfig(
        isInvitationRequired: isInvitationRequired,
        requireEmailVerification: requireEmailVerification,
        maintenance: const MaintenanceConfig(
          enabled: false,
          allowedRanks: [],
          reason: '',
          estTime: '',
        ),
        rateLimit: const RateLimitConfig(
          enabled: true,
          cooldowns: {},
          captchaAt: 3,
          lockAt: 10,
          lockDuration: 900,
          appliesTo: ['login'],
        ),
      );

  @override
  Future<RateLimitState> rateState(String context) async => rateStateValue;
}

class _FakeAuth extends AuthService {
  _FakeAuth()
      : super(
          ApiClient(store: MemorySessionStore(), apiBaseUrl: 'http://127.0.0.1:1'),
          apiBaseUrl: 'http://127.0.0.1:1',
        );

  RegisterResult Function() onRegister =
      () => const RegisterResult(submitted: true, message: '');
  String? lastBirthdate;
  String? lastGender;
  String? lastCaptchaAnswer;

  @override
  Future<RegisterResult> register({
    required String username,
    required String email,
    required String password,
    String? invitation,
    bool acceptPrivacy = false,
    bool acceptTerms = false,
    String? birthdate,
    String? gender,
    int? geoCountry,
    int? geoRegion,
    int? geoCity,
    String? captchaAnswer,
  }) async {
    lastBirthdate = birthdate;
    lastGender = gender;
    lastCaptchaAnswer = captchaAnswer;
    return onRegister();
  }
}

Future<void> _fillRequiredFields(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'newuser');
  await tester.enterText(find.byType(TextFormField).at(1), 'new@dev.dev');
  await tester.enterText(find.byType(TextFormField).at(2), 'secret1');
  await tester.enterText(find.byType(TextFormField).at(3), 'secret1');
}

/// Ticks both agreement checkboxes (the client-side submit gate demands
/// them — the server would bounce the same way). Scrolls with a
/// left-margin drag first (a center drag would be claimed by the text
/// fields) so the tiles sit at a settled, stable position.
Future<void> _checkAgreements(WidgetTester tester) async {
  await tester.dragFrom(const Offset(8, 500), const Offset(0, -500));
  await tester.pumpAndSettle();
  for (var i = 0; i < 2; i++) {
    await tester.tap(find.descendant(
      of: find.byType(CheckboxListTile).at(i),
      matching: find.byType(Checkbox),
    ));
    await tester.pump();
  }
}

Future<void> _scrollToAndTapRegister(WidgetTester tester) async {
  await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Register'));
  await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('invitation field shown + required when the site demands it',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RegisterScreen(
          auth: _FakeAuth(),
          siteConfig: _FakeConfig(isInvitationRequired: true)),
    ));
    await tester.pump();

    expect(find.text('Invitation Code *'), findsOneWidget);

    // Empty invitation must block submit with a clear message.
    await _fillRequiredFields(tester);
    await _scrollToAndTapRegister(tester);

    expect(find.text('An invitation code is required to join'), findsOneWidget);
  });

  testWidgets('invitation field hidden when no invitation is required',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RegisterScreen(
          auth: _FakeAuth(),
          siteConfig: _FakeConfig(isInvitationRequired: false)),
    ));
    await tester.pump();

    expect(find.text('Invitation Code *'), findsNothing);
    expect(find.text('Enter your invitation code'), findsNothing);
  });

  testWidgets('password fields have visibility toggles', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RegisterScreen(
          auth: _FakeAuth(),
          siteConfig: _FakeConfig(isInvitationRequired: false)),
    ));
    await tester.pump();

    // Both password fields start obscured.
    EditableText pwText(int index) => tester.widget<EditableText>(
        find.descendant(
            of: find.byType(TextFormField).at(index),
            matching: find.byType(EditableText)));
    expect(pwText(2).obscureText, isTrue);
    expect(pwText(3).obscureText, isTrue);

    // Toggle the first one — its text becomes visible.
    await tester.tap(find.byTooltip('Show password').first);
    await tester.pump();
    expect(pwText(2).obscureText, isFalse);
    expect(pwText(3).obscureText, isTrue, reason: 'other field untouched');
  });

  testWidgets(
      'email verification on → verify-email screen after register, '
      '"I have confirmed" goes to login', (tester) async {
    await tester.pumpWidget(MaterialApp(
      routes: {
        VerifyEmailScreen.routeName: (_) => const VerifyEmailScreen(),
        LoginPlaceholder.routeName: (_) =>
            const Scaffold(body: Text('LOGIN-PLACEHOLDER')),
      },
      home: RegisterScreen(
          auth: _FakeAuth(),
          siteConfig: _FakeConfig(
              isInvitationRequired: false, requireEmailVerification: true)),
    ));
    await tester.pump();

    await _fillRequiredFields(tester);
    await _checkAgreements(tester);
    await _scrollToAndTapRegister(tester);

    expect(find.text('Verify your email'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'I have confirmed'));
    await tester.pumpAndSettle();
    expect(find.text('LOGIN-PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('email verification off → straight to login after register',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      routes: {
        LoginPlaceholder.routeName: (_) =>
            const Scaffold(body: Text('LOGIN-PLACEHOLDER')),
      },
      home: RegisterScreen(
          auth: _FakeAuth(),
          siteConfig: _FakeConfig(
              isInvitationRequired: false, requireEmailVerification: false)),
    ));
    await tester.pump();

    await _fillRequiredFields(tester);
    await _checkAgreements(tester);
    await _scrollToAndTapRegister(tester);

    expect(find.text('LOGIN-PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('server rejection (e.g. email already registered) shows the '
      'error banner and stays on the form', (tester) async {
    final auth = _FakeAuth()
      ..onRegister = () => const RegisterResult(
          submitted: false, message: '* Email already registered');
    await tester.pumpWidget(MaterialApp(
      home: RegisterScreen(
          auth: auth,
          siteConfig: _FakeConfig(isInvitationRequired: false)),
    ));
    await tester.pump();

    await _fillRequiredFields(tester);
    await _checkAgreements(tester);
    await _scrollToAndTapRegister(tester);

    expect(find.text('* Email already registered'), findsOneWidget);
    expect(find.text('Verify your email'), findsNothing);
  });

  testWidgets('server field error attaches to its input and clears on edit',
      (tester) async {
    final auth = _FakeAuth()
      ..onRegister = () => const RegisterResult(
          submitted: false,
          message: 'Email already registered',
          fieldErrors: {'email': 'Email already registered'});
    await tester.pumpWidget(MaterialApp(
      home: RegisterScreen(
          auth: auth,
          siteConfig: _FakeConfig(isInvitationRequired: false)),
    ));
    await tester.pump();

    await _fillRequiredFields(tester);
    await _checkAgreements(tester);
    await _scrollToAndTapRegister(tester);

    // Field-level error — exactly once (the banner stays hidden when the
    // error belongs to a field).
    expect(find.text('Email already registered'), findsOneWidget);

    // Editing the field clears its server error.
    await tester.enterText(
        find.byType(TextFormField).at(1), 'changed@dev.dev');
    await tester.pump();
    expect(find.text('Email already registered'), findsNothing);
  });

  testWidgets('unchecked agreement boxes block submit with a clear message',
      (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(MaterialApp(
      home: RegisterScreen(
          auth: auth,
          siteConfig: _FakeConfig(isInvitationRequired: false)),
    ));
    await tester.pump();

    await _fillRequiredFields(tester);
    await _scrollToAndTapRegister(tester);

    expect(find.text('You must accept the Privacy Policy'), findsOneWidget);
  });

  testWidgets('captcha question shows when the limiter demands it; answer '
      'rides the submit', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(MaterialApp(
      home: RegisterScreen(
        auth: auth,
        siteConfig: _FakeConfig(
          isInvitationRequired: false,
          rateStateValue: const RateLimitState(
            blocked: false,
            cooldown: 0,
            needsCaptcha: true,
            captchaOk: false,
            lockRemaining: 0,
            captchaQuestion: 'What is 2+2?',
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('What is 2+2?'), findsOneWidget);

    await _fillRequiredFields(tester);
    await _checkAgreements(tester);
    await tester.ensureVisible(find.byType(TextFormField).at(4));
    await tester.enterText(find.byType(TextFormField).at(4), '4');
    await tester.pump();
    await _scrollToAndTapRegister(tester);

    expect(auth.lastCaptchaAnswer, '4');
  });
}

// Route-name stand-in for the login target (the real LoginScreen needs
// more scaffolding than a test wants).
class LoginPlaceholder {
  static const routeName = '/login';
}
