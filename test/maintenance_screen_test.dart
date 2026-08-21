import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/auth_service.dart';
import 'package:enclavd/api/site_config_service.dart';
import 'package:enclavd/screens/maintenance_screen.dart';

import 'api_client_test.dart' show MemorySessionStore;

class _FakeAuth extends AuthService {
  _FakeAuth()
      : super(
          ApiClient(store: MemorySessionStore(), apiBaseUrl: 'http://127.0.0.1:1'),
          apiBaseUrl: 'http://127.0.0.1:1',
        );

  @override
  Future<CurrentUser?> me() async => const CurrentUser(
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
}

class _FakeConfig extends SiteConfigService {
  _FakeConfig(this._config)
      : super(
          ApiClient(store: MemorySessionStore(), apiBaseUrl: 'http://127.0.0.1:1'),
        );

  SiteConfig _config;

  @override
  Future<SiteConfig> fetch() async => _config;
}

void main() {
  testWidgets('shows reason, estimated end and allowed ranks',
      (tester) async {
    final config = _FakeConfig(
      const SiteConfig(
        isInvitationRequired: false,
        maintenance: MaintenanceConfig(
          enabled: true,
          allowedRanks: ['SysOp', 'Admin', 'Moderator'],
          reason: 'Database upgrade in progress',
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
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: MaintenanceScreen(auth: _FakeAuth(), siteConfig: config),
    ));
    await tester.pump();

    expect(find.text('Maintenance'), findsOneWidget);
    expect(find.textContaining('Database upgrade in progress'), findsOneWidget);
    expect(find.textContaining('In 2 hours'), findsOneWidget);
    expect(find.textContaining('SysOp, Admin, Moderator'), findsOneWidget);
  });

  testWidgets('Check again → feed when maintenance is lifted', (tester) async {
    final config = _FakeConfig(
      const SiteConfig(
        isInvitationRequired: false,
        maintenance: MaintenanceConfig(
          enabled: true,
          allowedRanks: ['SysOp'],
          reason: 'Brief outage',
          estTime: 'Soon',
        ),
        rateLimit: RateLimitConfig(
          enabled: true,
          cooldowns: {},
          captchaAt: 3,
          lockAt: 10,
          lockDuration: 900,
          appliesTo: ['login'],
        ),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      routes: {
        MaintenanceFeedPlaceholder.routeName: (_) =>
            const Scaffold(body: Text('FEED-PLACEHOLDER')),
      },
      home: MaintenanceScreen(auth: _FakeAuth(), siteConfig: config),
    ));
    await tester.pump();

    // Maintenance ends — the next fetch reports it disabled.
    config._config = const SiteConfig(
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

    await tester.ensureVisible(find.text('Check again'));
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();

    expect(find.text('FEED-PLACEHOLDER'), findsOneWidget);
  });
}

class MaintenanceFeedPlaceholder {
  static const routeName = '/feed';
}
