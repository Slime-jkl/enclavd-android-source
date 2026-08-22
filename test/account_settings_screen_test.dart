import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/profile_service.dart';
import 'package:enclavd/screens/account_settings_screen.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/utils/user_facing_errors.dart';

class _FakeProfile extends ProfileService {
  _FakeProfile({
    this.account,
    this.updateProfileError,
    this.uploadAvatarError,
  }) : super(ApiClient(
            store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  final AccountSettings? account;
  final Object? updateProfileError;
  final Object? uploadAvatarError;

  @override
  Future<AccountSettings> fetchSelf() async => account!;

  @override
  Future<void> updateProfile({
    required String fullName,
    required String bio,
    String? birthdate,
    String? gender,
    int? geoCountry,
    int? geoRegion,
    int? geoCity,
  }) async {
    if (updateProfileError != null) throw updateProfileError!;
  }

  @override
  Future<String> uploadAvatar(String dataUrl) async {
    if (uploadAvatarError != null) throw uploadAvatarError!;
    return '/public/avatars/new.jpg';
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

const _account = AccountSettings(
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
);

Future<void> _pump(
  WidgetTester tester,
  _FakeProfile fake, {
  Future<XFile?> Function()? avatarPicker,
}) async {
  // Real ApiClient: the geo name lookups hit the test HTTP 400 wall and
  // fail silently (cosmetic), so the form must still render.
  await tester.pumpWidget(MaterialApp(
    theme: buildEnclavdTheme(),
    home: AccountSettingsScreen(
      profile: fake,
      api: ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'),
      avatarPicker: avatarPicker,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Scrolls to the bottom (Save Changes) and taps it.
Future<void> _tapSave(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -1600));
  await tester.pump();
  await tester.tap(find.text('Save Changes'));
  await tester.pump(); // start the save future + the scroll-to-error
  await tester.pump(const Duration(milliseconds: 400)); // finish the scroll
}

void main() {
  testWidgets('renders the edit-profile fields prefilled from self',
      (tester) async {
    final fake = _FakeProfile(account: _account);
    await _pump(tester, fake);

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

  testWidgets('server 4xx on save shows the server message verbatim',
      (tester) async {
    final fake = _FakeProfile(
      account: _account,
      updateProfileError: const ApiException(
          'Invalid file type. Allowed types are JPEG, PNG, GIF, and WebP.',
          status: 400),
    );
    await _pump(tester, fake);
    await _tapSave(tester);

    // The banner is at the top of the list; the save button at the bottom —
    // the scroll-to-error animation brings it into view.
    expect(find.textContaining('Invalid file type'), findsOneWidget,
        reason: '4xx server message is shown as-is');
  });

  testWidgets('server 5xx on save shows the friendly internal-error line',
      (tester) async {
    final fake = _FakeProfile(
      account: _account,
      updateProfileError:
          const ApiException('Internal Server Error', status: 500),
    );
    await _pump(tester, fake);
    await _tapSave(tester);

    expect(find.textContaining(kInternalError), findsOneWidget,
        reason: '5xx maps to the report-it line, not raw server text');
    expect(find.textContaining('Internal Server Error'), findsNothing,
        reason: 'raw 500 text is never shown');
  });

  testWidgets('network failure on save shows the connection message',
      (tester) async {
    final fake = _FakeProfile(
      account: _account,
      updateProfileError: const SocketException('Connection reset by peer'),
    );
    await _pump(tester, fake);
    await _tapSave(tester);

    expect(find.textContaining('Network error'), findsOneWidget,
        reason: 'transport failure gets its own message');
  });

  testWidgets('avatar upload failure is reported separately and keeps the '
      'picked preview', (tester) async {
    final fake = _FakeProfile(
      account: _account,
      uploadAvatarError:
          const ApiException('Internal Server Error', status: 500),
    );
    await _pump(
      tester,
      fake,
      avatarPicker: () async => XFile.fromData(
          base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='),
          mimeType: 'image/jpeg'),
    );

    // Pick an avatar — the button flips to "Replace" while pending.
    await tester.tap(find.text('Change'));
    await tester.pump();
    expect(find.text('Replace'), findsOneWidget, reason: 'preview pending');

    await _tapSave(tester);

    expect(find.textContaining(kInternalError), findsOneWidget,
        reason: 'avatar 5xx maps to the friendly line');
    expect(find.text('Replace'), findsOneWidget,
        reason: 'the picked preview is kept so the user can retry');
  });
}
