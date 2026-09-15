import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/feed_service.dart';
import 'package:enclavd/api/notifications_service.dart';
import 'package:enclavd/api/social_service.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/ignite_button.dart';
import 'package:enclavd/widgets/ignite_flame.dart';
import 'package:enclavd/widgets/likers_sheet.dart';
import 'package:enclavd/widgets/post_card.dart';

const _limitCopy =
    'You can ignite only one post each day, you already ignited one today.';

Post _post({bool userIgnited = false, int likeCount = 0}) => Post.fromJson({
      'id': 1,
      'author_id': 2,
      'content': 'hello world',
      'created_at': '2026-08-20 09:00:00',
      'feed_score': 1.5,
      'like_count': likeCount,
      'comment_count': 0,
      'user_liked': false,
      'user_ignited': userIgnited,
      'warning_count': 0,
      'username': 'Dev',
      'profile_picture_url': '/a.png',
      'personality_type': null,
      'is_active': 'true',
      'rank': 'Member',
      'image': null,
      'is_owner': false,
    });

class _FakeSocial extends SocialService {
  _FakeSocial({
    this.result = const IgniteResult(status: 'ignited', likeCount: 5),
  }) : super(_noopClient());

  static ApiClient _noopClient() => ApiClient(
        store: _NoopStore(),
        apiBaseUrl: 'https://example.com',
      );

  final IgniteResult result;
  int igniteCalls = 0;

  @override
  Future<IgniteResult> ignite(int postId) async {
    igniteCalls++;
    return result;
  }

  @override
  Future<List<Liker>> likers(int postId) async => const [
        Liker(
          id: 1,
          username: 'Igniter',
          profilePictureUrl: '/a.png',
          personalityType: null,
          rank: 'Member',
          likedAt: 'September 15, 2026 at 11:25 PM',
          ignited: true,
        ),
        Liker(
          id: 2,
          username: 'PlainLiker',
          profilePictureUrl: '/b.png',
          personalityType: null,
          rank: 'Member',
          likedAt: 'September 15, 2026 at 10:00 PM',
        ),
      ];
}

/// Holds the ignite request open, so a double press can be driven while one
/// is in flight.
class _SlowSocial extends _FakeSocial {
  final Completer<IgniteResult> _gate = Completer<IgniteResult>();

  @override
  Future<IgniteResult> ignite(int postId) {
    igniteCalls++;
    return _gate.future;
  }

  void release() =>
      _gate.complete(const IgniteResult(status: 'ignited', likeCount: 2));
}

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

Finder _fire() => find.byKey(const ValueKey('ignite-fire'));
Finder _flame() => find.byKey(const ValueKey('ignite-flame'));

void main() {
  setUp(() => SoundService.muted = true);
  tearDown(() => SoundService.muted = false);

  group('ignite model', () {
    test('Post reads user_ignited, defaults false', () {
      expect(_post(userIgnited: true).userIgnited, isTrue);
      expect(_post().userIgnited, isFalse);
    });

    test('Liker reads ignited, defaults false', () {
      final igniter = Liker.fromJson(const {'id': 4, 'ignited': true});
      final plain = Liker.fromJson(const {'id': 5});
      expect(igniter.ignited, isTrue);
      expect(plain.ignited, isFalse, reason: 'older payloads omit the flag');
    });

    test('IgniteResult maps every status', () {
      expect(IgniteResult.fromJson(const {'status': 'ignited'}).granted, isTrue);
      expect(
          IgniteResult.fromJson(const {'status': 'already_ignited'})
              .alreadyIgnited,
          isTrue);
      final limited = IgniteResult.fromJson(
          const {'status': 'limit_reached', 'message': _limitCopy});
      expect(limited.limitReached, isTrue);
      expect(limited.message, _limitCopy);

      // An unexpected body must never read as a limit.
      final junk = IgniteResult.fromJson(const {'error': 'nope'});
      expect(junk.limitReached, isFalse);
      expect(junk.granted, isFalse);
      expect(junk.alreadyIgnited, isFalse);
    });

    test('post-super-like threads through the notification router', () {
      final n = AppNotification.fromJson(const {
        'id': 9,
        'message': 'Igniter ignited your post',
        'content_type': 'post-super-like',
        'content_id': 42,
      });
      expect(n.isPostAttached, isTrue);
      expect(n.tapTarget, NotificationTarget.post);
      expect(n.groupId, 42, reason: 'a later notice for the post replaces it');
      expect(n.hasComment, isFalse);
    });
  });

  group('card ignite', () {
    Future<_FakeSocial> pumpCard(
      WidgetTester tester, {
      Post? post,
      IgniteResult? result,
    }) async {
      final social = _FakeSocial(
        result: result ?? const IgniteResult(status: 'ignited', likeCount: 5),
      );
      await tester.pumpWidget(MaterialApp(
        theme: buildEnclavdTheme(),
        home: Scaffold(
          body: PostCard(
            post: post ?? _post(),
            apiBaseUrl: 'https://example.com',
            social: social,
          ),
        ),
      ));
      return social;
    }

    // The card's ancestor double-tap recognizer delays single taps ~300ms.
    Future<void> tapFire(WidgetTester tester) async {
      await tester.tap(_fire());
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
    }

    testWidgets('a granted ignite lights the fire and takes the count',
        (tester) async {
      final social = await pumpCard(tester);
      expect(_fire(), findsOneWidget);
      expect(_flame(), findsNothing);

      await tapFire(tester);

      expect(social.igniteCalls, 1);
      expect(_flame(), findsOneWidget, reason: 'the fire stays lit');
      expect(_fire(), findsNothing);
      expect(find.text('5'), findsOneWidget,
          reason: 'the ignite carries the like, server count wins');
      expect(find.text(_limitCopy), findsNothing);
    });

    testWidgets('the spent day explains itself and stays unlit',
        (tester) async {
      await pumpCard(
        tester,
        result: const IgniteResult(status: 'limit_reached', message: _limitCopy),
      );

      await tapFire(tester);

      expect(find.text(_limitCopy), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
      expect(_flame(), findsNothing, reason: 'nothing was granted');

      await tester.tap(find.text('Got it'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(_limitCopy), findsNothing);
    });

    testWidgets('pressing an already ignited post only relights it',
        (tester) async {
      await pumpCard(
        tester,
        result: const IgniteResult(status: 'already_ignited', likeCount: 5),
      );

      await tapFire(tester);

      expect(_flame(), findsOneWidget);
      expect(find.text(_limitCopy), findsNothing);
    });

    testWidgets('a server-side ignite renders lit on first paint',
        (tester) async {
      await pumpCard(tester, post: _post(userIgnited: true, likeCount: 3));
      expect(_flame(), findsOneWidget);
      expect(_fire(), findsNothing);
    });
  });

  group('ignite control', () {
    Future<_FakeSocial> pumpButton(
      WidgetTester tester, {
      _FakeSocial? social,
      bool ignited = false,
      void Function(IgniteResult result)? onResult,
    }) async {
      final fake = social ??
          _FakeSocial(
            result: const IgniteResult(status: 'ignited', likeCount: 4),
          );
      await tester.pumpWidget(MaterialApp(
        theme: buildEnclavdTheme(),
        home: Scaffold(
          body: Center(
            child: IgniteButton(
              postId: 1,
              ignited: ignited,
              social: fake,
              onResult: onResult,
            ),
          ),
        ),
      ));
      return fake;
    }

    testWidgets('a granted press lights up and reports the result',
        (tester) async {
      IgniteResult? reported;
      final social = await pumpButton(tester, onResult: (r) => reported = r);

      await tester.tap(_fire());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(social.igniteCalls, 1);
      expect(_flame(), findsOneWidget);
      expect(reported?.granted, isTrue);
      expect(reported?.likeCount, 4);
    });

    testWidgets('the limit stays unlit, explains itself and reports nothing',
        (tester) async {
      var reported = false;
      await pumpButton(
        tester,
        social: _FakeSocial(
          result: const IgniteResult(status: 'limit_reached', message: _limitCopy),
        ),
        onResult: (_) => reported = true,
      );

      await tester.tap(_fire());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(_limitCopy), findsOneWidget);
      expect(_flame(), findsNothing);
      expect(reported, isFalse,
          reason: 'a limit is not a grant, the card must not celebrate it');
    });

    testWidgets('a press in flight swallows the second one', (tester) async {
      final social = _SlowSocial();
      await pumpButton(tester, social: social);

      await tester.tap(_fire());
      await tester.pump();
      await tester.tap(_fire());
      await tester.pump();

      expect(social.igniteCalls, 1, reason: 'one day, one ignite');
      social.release();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_flame(), findsOneWidget);
    });

    testWidgets('an already ignited post lights without a dialog',
        (tester) async {
      await pumpButton(
        tester,
        social: _FakeSocial(
          result: const IgniteResult(status: 'already_ignited', likeCount: 4),
        ),
      );

      await tester.tap(_fire());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(_flame(), findsOneWidget);
      expect(find.text('Got it'), findsNothing);
    });
  });

  group('likers sheet', () {
    testWidgets('only the igniters carry the fire', (tester) async {
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

      expect(find.text('Igniter'), findsOneWidget);
      expect(find.text('PlainLiker'), findsOneWidget);
      expect(find.byType(IgniteFlame), findsOneWidget,
          reason: 'one flame, on the igniter only');

      final flame = tester.widget<IgniteFlame>(find.byType(IgniteFlame));
      expect(flame.size, 20);
      // Right of the name/rank: the row's flame comes after the rank badge.
      final rowBox = tester.getRect(find.text('Igniter'));
      final flameBox = tester.getRect(find.byType(IgniteFlame));
      expect(flameBox.left, greaterThan(rowBox.right));
    });
  });
}
