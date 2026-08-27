import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/auth_service.dart';
import 'package:enclavd/screens/profile_screen.dart';
import 'package:enclavd/screens/settings_screen.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/shimmer.dart';
import 'package:enclavd/widgets/user_menu_drawer.dart';

class _FakeAuth extends AuthService {
  _FakeAuth() : super(_noopClient(), apiBaseUrl: 'https://example.com');

  static ApiClient _noopClient() => ApiClient(
        store: _NoopStore(),
        apiBaseUrl: 'https://example.com',
      );

  /// When set, me() waits on this before resolving — lets tests observe
  /// the loading (shimmer) state of the drawer.
  Completer<void>? gate;

  @override
  Future<CurrentUser?> me() async {
    final g = gate;
    if (g != null) await g.future;
    return const CurrentUser(
      id: 1,
      username: 'Slimejkl',
      profilePictureUrl: '/a.png',
      rank: 'SysOp',
      personalityType: 'INTJ',
      prestige: 1234567,
      isAdmin: true,
      dateCreated: '2025-05-14 00:00:00',
      banned: false,
      blockReason: '',
    );
  }
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

    // The grouped layout (sections + sign-out divider) is taller than the
    // 600px test viewport — scroll the drawer's own list to reach the
    // bottom rows, as a real user would.
    Future<void> scrollDrawerToBottom(WidgetTester tester) async {
      await tester.drag(find.byType(ListView), const Offset(0, -250));
      await tester.pump();
    }

    testWidgets('shows the current user; Profile and Control Panel are gone',
        (tester) async {
      await pumpDrawer(tester);

      expect(find.text('Slimejkl'), findsOneWidget);
      expect(find.text('SysOp'), findsOneWidget, reason: 'rank badge');
      expect(find.text('Control Panel'), findsNothing,
          reason: 'admin-only item removed at the user request');
      expect(find.text('Profile'), findsNothing,
          reason: 'Profile item removed at the user request');
      expect(find.text('Account settings'), findsOneWidget);
      expect(find.text('App settings'), findsOneWidget);
      expect(find.text('Quote of the day'), findsOneWidget,
          reason: 'the feature has its own menu entry, not buried in settings');
      expect(find.text('Diary'), findsOneWidget,
          reason: 'the diary has its own menu entry next to the quote');
      await scrollDrawerToBottom(tester);
      expect(find.text('Test Results'), findsOneWidget);
      expect(find.text('Invitations'), findsOneWidget);
      expect(find.text('Legal'), findsOneWidget);
      expect(find.text('Report an issue'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      // The about card (moved from the app settings screen) sits after
      // the menu items — drag a little more to reveal it.
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();
      expect(find.text('ABOUT'), findsOneWidget,
          reason: 'section labels render uppercase');
      expect(find.text('iOS/Android native app'), findsOneWidget);
      expect(find.text('Community Powered'), findsOneWidget);
      expect(find.text('What\'s new'), findsOneWidget);
    });

    testWidgets('Sign out fires the callback', (tester) async {
      var signedOut = false;
      await pumpDrawer(tester, onSignOut: () => signedOut = true);

      await scrollDrawerToBottom(tester);
      await tester.tap(find.text('Sign out'));
      await tester.pump();
      expect(signedOut, isTrue);
    });

    testWidgets('App settings opens the settings screen', (tester) async {
      await pumpDrawer(tester);

      await tester.tap(find.text('App settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // route push
      await tester.pump();
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('shimmers while the session probe is in flight',
        (tester) async {
      final auth = _FakeAuth()..gate = Completer<void>();
      await tester.pumpWidget(MaterialApp(
        theme: buildEnclavdTheme(),
        home: Scaffold(endDrawer: UserMenuDrawer(auth: auth, onSignOut: () {})),
      ));
      tester.state<ScaffoldState>(find.byType(Scaffold)).openEndDrawer();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // slide in

      // Loading: the menu's skeleton (shimmer rows) is on screen, the
      // real content is not yet.
      expect(find.byType(ShimmerBox), findsWidgets,
          reason: 'skeleton rows shimmer while me() is pending');
      expect(find.text('Slimejkl'), findsNothing,
          reason: 'no real content until the probe resolves');

      // Resolve: the skeleton gives way to the loaded menu. (A lone
      // ShimmerBox may remain — the avatar's own image shimmer, which
      // never loads in tests. The skeleton had 10+; the loaded state is
      // proven by the real content appearing.)
      auth.gate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Slimejkl'), findsOneWidget);
      expect(find.text('App settings'), findsOneWidget);
      expect(find.text('ACCOUNT'), findsOneWidget, reason: 'section labels');
      expect(
          find.byWidgetPredicate((w) =>
              w is ShimmerBox && w.width == 130 && w.height == 13),
          findsNothing,
          reason: 'the skeleton menu rows are gone');
    });
  });
}
