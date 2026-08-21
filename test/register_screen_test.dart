import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/site_config_service.dart';
import 'package:enclavd/screens/register_screen.dart';

import 'api_client_test.dart' show MemorySessionStore;

class _FakeConfig extends SiteConfigService {
  _FakeConfig({required this.isInvitationRequired})
      : super(
          ApiClient(store: MemorySessionStore(), apiBaseUrl: 'http://127.0.0.1:1'),
        );

  final bool isInvitationRequired;

  @override
  Future<SiteConfig> fetch() async => SiteConfig(
        isInvitationRequired: isInvitationRequired,
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
}

void main() {
  testWidgets('invitation field shown + required when the site demands it',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RegisterScreen(
          siteConfig: _FakeConfig(isInvitationRequired: true)),
    ));
    await tester.pump();

    expect(find.text('Invitation Code *'), findsOneWidget);

    // Empty invitation must block submit with a clear message.
    await tester.enterText(
        find.byType(TextFormField).at(0), 'newuser'); // username
    await tester.enterText(
        find.byType(TextFormField).at(1), 'new@dev.dev'); // email
    await tester.enterText(find.byType(TextFormField).at(2), 'secret1');
    await tester.enterText(find.byType(TextFormField).at(3), 'secret1');
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Register'));
    await tester.pump();

    expect(find.text('An invitation code is required to join'), findsOneWidget);
  });

  testWidgets('invitation field hidden when no invitation is required',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RegisterScreen(
          siteConfig: _FakeConfig(isInvitationRequired: false)),
    ));
    await tester.pump();

    expect(find.text('Invitation Code *'), findsNothing);
    expect(find.text('Enter your invitation code'), findsNothing);
  });
}
