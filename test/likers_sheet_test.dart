import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/social_service.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/enclavd_avatar.dart';
import 'package:enclavd/widgets/likers_sheet.dart';

class _FakeSocial extends SocialService {
  _FakeSocial() : super(_noopClient());

  static ApiClient _noopClient() => ApiClient(
        store: _NoopStore(),
        apiBaseUrl: 'https://example.com',
      );

  @override
  Future<List<Liker>> likers(int postId) async => const [
        Liker(
          id: 1,
          username: 'Slimejkl',
          profilePictureUrl: '/public/avatars/a.jpg',
          personalityType: 'INTJ',
          rank: 'SysOp',
          likedAt: 'August 20, 2026 at 1:43 PM',
        ),
        Liker(
          id: 2,
          username: 'vaporycoder',
          profilePictureUrl: '/a.png',
          personalityType: null,
          rank: 'Founding Member',
          likedAt: 'August 16, 2026 at 5:13 PM',
        ),
      ];
}

class _LongNameSocial extends _FakeSocial {
  @override
  Future<List<Liker>> likers(int postId) async => const [
        Liker(
          id: 3,
          username:
              'a_very_long_username_that_should_truncate_instead_of_pushing',
          profilePictureUrl: '/a.png',
          personalityType: 'ENFP',
          rank: 'Member',
          likedAt: 'August 20, 2026 at 1:43 PM',
        ),
      ];
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

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: Scaffold(
        body: LikersSheet(
          postId: 1,
          social: _FakeSocial(),
          apiBaseUrl: 'https://example.com',
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('rows stack rank over name over personality, with no timestamps',
      (
    tester,
  ) async {
    await pumpSheet(tester);

    // Username carries its rank color (SysOp -> purple-400).
    final username = tester.widget<Text>(find.text('Slimejkl').first);
    expect(username.style?.color, EnclavdPalette.dark.rankName('SysOp'));

    // Personality pill for accounts that have one.
    expect(find.text('INTJ'), findsOneWidget);

    expect(find.text('SysOp'), findsOneWidget);
    expect(find.text('Founding Member'), findsOneWidget);
    expect(find.text('vaporycoder'), findsOneWidget);

    // Avatar: ClipOval inside the ring container, ring colored by rank.
    final avatars =
        tester.widgetList<EnclavdAvatar>(find.byType(EnclavdAvatar));
    expect(avatars.length, 2);
    expect(avatars.first.rank, 'SysOp');
    expect(avatars.last.rank, 'Founding Member');
    expect(find.byType(ClipOval), findsNWidgets(2),
        reason: 'images clip via ClipOval, never a raw square');

    // Layout: rank chip on top, username under it, personality under that.
    final rank = tester.getCenter(find.text('SysOp'));
    final name = tester.getCenter(find.text('Slimejkl').first);
    final personality = tester.getCenter(find.text('INTJ'));
    expect(rank.dy < name.dy, isTrue,
        reason: 'rank badge sits above the username');
    expect((name.dy - personality.dy).abs() < 5, isTrue,
        reason: 'personality badge sits inline, right after the username');
    expect(personality.dx > name.dx, isTrue,
        reason: 'personality badge comes after the name');

    // The list no longer repeats when someone liked the post.
    expect(find.textContaining('at '), findsNothing,
        reason: 'timestamps are gone from the likers list');
  });

  testWidgets('a long name truncates and keeps its personality inline', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            child: LikersSheet(
              postId: 1,
              social: _LongNameSocial(),
              apiBaseUrl: 'https://example.com',
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final name = tester.widget<Text>(
      find.text(
        'a_very_long_username_that_should_truncate_instead_of_pushing',
      ),
    );
    expect(name.overflow, TextOverflow.ellipsis);
    expect(name.maxLines, 1);
    expect(find.text('ENFP'), findsOneWidget,
        reason: 'the personality chip stays visible next to the name');
  });
}
