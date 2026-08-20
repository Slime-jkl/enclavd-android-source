import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/social_service.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/enclavd_avatar.dart';
import 'package:enclavd/widgets/likers_sheet.dart';

/// SocialService answering from memory (widget tests run in a fake-async
/// zone where real sockets never complete).
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

  testWidgets('rows render feed-style: rank color, personality pill, '
      'rank badge, personality-bordered circular avatar', (tester) async {
    await pumpSheet(tester);

    // Username carries its rank color (SysOp → purple-400).
    final username = tester.widget<Text>(
        find.text('Slimejkl').first);
    expect(username.style?.color, RankColors.forRank('SysOp'));

    // Personality pill for accounts that have one.
    expect(find.text('INTJ'), findsOneWidget);

    // Rank badge chips (icon + rank name) for every liker.
    expect(find.text('SysOp'), findsOneWidget);
    expect(find.text('Founding Member'), findsOneWidget);
    expect(find.text('vaporycoder'), findsOneWidget);

    // Avatar: the bulletproof circle pattern — a ClipOval inside the
    // ring container, ring colored by personality.
    final avatars = tester.widgetList<EnclavdAvatar>(find.byType(EnclavdAvatar));
    expect(avatars.length, 2);
    final first = avatars.first;
    expect(first.borderColor, PersonalityColors.forType('INTJ'));
    expect(find.byType(ClipOval), findsNWidgets(2),
        reason: 'images clip via ClipOval, never a raw square');
  });
}
