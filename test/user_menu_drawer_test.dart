import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/auth_service.dart';
import 'package:enclavd/screens/profile_screen.dart';
import 'package:enclavd/screens/settings_screen.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/user_menu_drawer.dart';

class _FakeAuth extends AuthService {
  _FakeAuth() : super(_noopClient(), apiBaseUrl: 'https://example.com');

  static ApiClient _noopClient() => ApiClient(
        store: _NoopStore(),
        apiBaseUrl: 'https://example.com',
      );

  @override
  Future<CurrentUser?> me() async => const CurrentUser(
        id: 1,
        username: 'Slimejkl',
        profilePictureUrl: '/a.png',
        rank: 'SysOp',
        personalityType: 'INTJ',
        prestige: 1234567,
        isAdmin: true,
        dateCreated: '2025-05-14 00:00:00',
      );
}

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

void main() {
  setUp(() => SoundService.muted = true);
  tearDown(() => SoundService.muted = false);

  group('formatPrestige (site number_format dot separators)', () {
    test('thousands use dots, not commas', () {
      expect(formatPrestige(0), '0');
      expect(formatPrestige(999), '999');
      expect(formatPrestige(1000), '1.000');
      expect(formatPrestige(1234567), '1.234.567');
      expect(formatPrestige(1000000), '1.000.000');
    });
  });

  group('UserMenuDrawer', () {
    // Bounded pumps, not pumpAndSettle: the avatar's shimmer and the
    // settings spinner are infinite animations, so settle never returns.
    Future<void> pumpDrawer(WidgetTester tester,
        {VoidCallback? onSignOut}) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildEnclavdTheme(),
        home: Scaffold(
          endDrawer: UserMenuDrawer(
            auth: _FakeAuth(),
            onSignOut: onSignOut ?? () {},
          ),
        ),
      ));
      tester.state<ScaffoldState>(find.byType(Scaffold)).openEndDrawer();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // slide in
      await tester.pump(); // FutureBuilder applies the me() result
    }

    testWidgets('shows the current user with rank badge and admin panel',
        (tester) async {
      await pumpDrawer(tester);

      expect(find.text('Slimejkl'), findsOneWidget);
      expect(find.text('SysOp'), findsOneWidget, reason: 'rank badge');
      expect(find.text('Control Panel'), findsOneWidget,
          reason: 'admin-only item shows for admins');
      expect(find.text('Test Results'), findsOneWidget);
      expect(find.text('Invitations'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Legal'), findsOneWidget);
      expect(find.text('Report an issue'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('Sign out fires the callback', (tester) async {
      var signedOut = false;
      await pumpDrawer(tester, onSignOut: () => signedOut = true);

      await tester.tap(find.text('Sign out'));
      await tester.pump();
      expect(signedOut, isTrue);
    });

    testWidgets('Settings opens the settings screen', (tester) async {
      await pumpDrawer(tester);

      await tester.tap(find.text('Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // route push
      await tester.pump();
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });
}
