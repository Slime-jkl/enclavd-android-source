import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/profile_service.dart';
import 'package:enclavd/screens/account_settings_screen.dart';
import 'package:enclavd/theme/enclavd_theme.dart';

class _FakeProfile extends ProfileService {
  _FakeProfile({this.account})
      : super(ApiClient(
            store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  final AccountSettings? account;

  @override
  Future<AccountSettings> fetchSelf() async => account!;
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
  testWidgets('renders the edit-profile fields prefilled from self',
      (tester) async {
    final fake = _FakeProfile(
      account: const AccountSettings(
        id: 1,
        username: 'Developer',
        email: 'dev@dev.dev',
        fullName: 'Dev One',
        profilePictureUrl: '/public/avatars/a.jpg',
        personalityType: 'INTJ',
        rank: 'SysOp',
        bio: 'hello world',
        birthdate: '1995-01-18',
        gender: 'MALE',
        geoCountry: 230,
        geoRegion: 3665,
        geoCity: 2790421,
      ),
    );
    // Real ApiClient: the geo name lookups hit the test HTTP 400 wall and
    // fail silently (cosmetic), so the form must still render.
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: AccountSettingsScreen(
        profile: fake,
        api: ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Account settings'), findsOneWidget, reason: 'appbar');
    expect(find.text('Profile Picture'), findsOneWidget,
        reason: 'avatar row is first');
    expect(find.text('dev@dev.dev'), findsOneWidget, reason: 'read-only email');
    expect(find.text('Dev One'), findsOneWidget, reason: 'full name');
    expect(find.text('hello world'), findsOneWidget, reason: 'bio');

    // Birthdate / gender / buttons sit below the fold — scroll down.
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(find.text('1995-01-18'), findsOneWidget, reason: 'birthdate');
    expect(find.text('Male'), findsOneWidget, reason: 'gender value');
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
  });
}
