import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/auth_service.dart';
import 'package:enclavd/screens/verify_email_screen.dart';

import 'api_client_test.dart' show MemorySessionStore;

class _FakeAuth extends AuthService {
  _FakeAuth()
      : super(
          ApiClient(store: MemorySessionStore(), apiBaseUrl: 'http://127.0.0.1:1'),
          apiBaseUrl: 'http://127.0.0.1:1',
        );

  String? lastEmail;
  ResendResult result = const ResendResult(
    sent: true,
    message: 'A new verification email has been sent. Please check your inbox.',
  );

  @override
  Future<ResendResult> resendVerificationEmail(String email) async {
    lastEmail = email;
    return result;
  }
}

void main() {
  testWidgets(
      'resend button starts unclickable with a 60s cooldown and gains '
      '60 more seconds per try', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(MaterialApp(
      home: VerifyEmailScreen(email: 'new@dev.dev', auth: auth),
    ));
    await tester.pump();

    // Starts disabled with the 60-second cooldown shown on the button.
    final cooling = find.widgetWithText(OutlinedButton, 'Resend email (1:00)');
    expect(cooling, findsOneWidget);
    expect(tester.widget<OutlinedButton>(cooling).onPressed, isNull);

    // After the 60s elapse the button becomes clickable.
    await tester.pump(const Duration(seconds: 60));
    final enabled = find.widgetWithText(OutlinedButton, 'Resend email');
    expect(enabled, findsOneWidget);
    expect(tester.widget<OutlinedButton>(enabled).onPressed, isNotNull);

    // One try: sends to the right address, reports the outcome, and costs
    // another 60 seconds (60 → 120).
    await tester.tap(enabled);
    await tester.pump();
    expect(auth.lastEmail, 'new@dev.dev');
    expect(find.textContaining('A new verification email'), findsOneWidget);

    final reCooling =
        find.widgetWithText(OutlinedButton, 'Resend email (2:00)');
    expect(reCooling, findsOneWidget);
    expect(tester.widget<OutlinedButton>(reCooling).onPressed, isNull);
  });

  testWidgets('resend button hidden when no email was passed', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: VerifyEmailScreen(auth: null),
    ));
    await tester.pump();
    expect(find.byType(OutlinedButton), findsNothing);
  });
}
