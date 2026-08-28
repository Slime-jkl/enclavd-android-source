import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/auth_service.dart';
import 'package:enclavd/screens/ban_screen.dart';
import 'package:enclavd/screens/login_screen.dart';

import 'api_client_test.dart' show MemorySessionStore;

class _FakeAuth extends AuthService {
  _FakeAuth({this.user})
      : super(
          ApiClient(store: MemorySessionStore(), apiBaseUrl: 'http://127.0.0.1:1'),
          apiBaseUrl: 'http://127.0.0.1:1',
        );

  final CurrentUser? user;
  var logoutCalls = 0;

  @override
  Future<CurrentUser?> me() async => user;

  @override
  Future<void> logout() async {
    logoutCalls++;
  }
}

void main() {
  testWidgets('shows the ban reason and blocks access', (tester) async {
    final auth = _FakeAuth(
      user: const CurrentUser(
        id: 9,
        username: 'BarredUser',
        profilePictureUrl: '/a.png',
        rank: 'Member',
        personalityType: null,
        prestige: 0,
        isAdmin: false,
        dateCreated: '2025-05-14 00:00:00',
        banned: true,
        blockReason: 'Violated community guidelines',
      ),
    );

    await tester.pumpWidget(MaterialApp(
      routes: {
        LoginScreen.routeName: (_) =>
            const Scaffold(body: Text('LOGIN-PLACEHOLDER')),
      },
      home: BanScreen(auth: auth),
    ));
    await tester.pump();

    expect(find.text('Your account has been banned'), findsOneWidget);
    expect(find.text('Violated community guidelines'), findsOneWidget);

    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();
    expect(auth.logoutCalls, 1);
    expect(find.text('LOGIN-PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('falls back to a generic reason when none is provided',
      (tester) async {
    final auth = _FakeAuth(
      user: const CurrentUser(
        id: 10,
        username: 'x',
        profilePictureUrl: '/a.png',
        rank: 'Member',
        personalityType: null,
        prestige: 0,
        isAdmin: false,
        dateCreated: '2025-05-14 00:00:00',
        banned: true,
        blockReason: '',
      ),
    );

    await tester.pumpWidget(MaterialApp(home: BanScreen(auth: auth)));
    await tester.pump();

    expect(find.text('No reason provided.'), findsOneWidget);
  });
}
