import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/activity_service.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/profile_service.dart' show FollowListItem;
import 'package:enclavd/api/social_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/activity_card.dart';
import 'package:enclavd/widgets/post_card.dart';

Map<String, dynamic> _post(int id,
        {String username = 'Writer', String content = 'a post worth reading'}) =>
    {
      'id': id,
      'author_id': 2,
      'content': content,
      'created_at': '2026-09-01 10:00:00',
      'feed_score': null,
      'like_count': 4,
      'comment_count': 2,
      'user_liked': true,
      'warning_count': 0,
      'username': username,
      'profile_picture_url': '/assets/default-avatar.png',
      'personality_type': null,
      'is_active': 'true',
      'rank': 'Member',
      'image': null,
      'is_owner': false,
      'has_domain': false,
      'domain_by': 0,
      'promoter_username': null,
      'domain_name': null,
      'domain_slug': null,
    };

Map<String, dynamic> _user(int id,
        {String username = 'Friend',
        String fullName = '',
        String bio = '',
        String isActive = 'true'}) =>
    {
      'id': id,
      'username': username,
      'full_name': fullName,
      'profile_picture_url': '/assets/default-avatar.png',
      'personality_type': null,
      'rank': 'Member',
      'bio': bio,
      'is_active': isActive,
      'is_online': false,
      'is_following': true,
      'is_following_you': false,
      'is_own': false,
    };

/// A db-format UTC time a fixed number of minutes ago (relative dates:
/// fixed ISO strings go stale and break the suite the next day).
String _minutesAgo([int minutes = 10]) {
  final t = DateTime.now().toUtc().subtract(Duration(minutes: minutes));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

ActivityItem _item(Map<String, dynamic> json) =>
    ActivityItem.fromJson({...json, 'created_at': _minutesAgo()});

Widget _wrap(Widget child) => MaterialApp(
      theme: buildEnclavdTheme(),
      home: Scaffold(body: child),
    );

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

void main() {
  testWidgets('like note reads "You liked" with a relative time',
      (tester) async {
    final item = _item({
      'type': 'like',
      'id': 1,
      'post': _post(5, username: 'Writer'),
    });
    await tester.pumpWidget(_wrap(ActivityNote(item: item)));

    expect(find.text('You liked'), findsOneWidget);
    expect(find.text('10m'), findsOneWidget);
    // The author belongs to the post card below the note, not the note.
    expect(find.textContaining("@Writer's post"), findsNothing);
  });

  testWidgets('comment note reads "You commented"', (tester) async {
    final item = _item({
      'type': 'comment',
      'id': 2,
      'content': 'I agree with this',
      'parent_comment_id': null,
      'post': _post(5),
    });
    await tester.pumpWidget(_wrap(ActivityNote(item: item)));

    expect(find.text('You commented'), findsOneWidget);
  });

  testWidgets('follow note reads "You followed"', (tester) async {
    final item = _item({
      'type': 'follow',
      'id': 7,
      'user': _user(7),
    });
    await tester.pumpWidget(_wrap(ActivityNote(item: item)));

    expect(find.text('You followed'), findsOneWidget);
  });

  testWidgets('follow member card shows the member and opens on tap',
      (tester) async {
    final user = FollowListItem.fromJson(
        _user(7, username: 'Friend', fullName: 'A Friend Indeed'));
    var taps = 0;
    await tester.pumpWidget(_wrap(ActivityFollowCard(
      user: user,
      onTap: () => taps++,
    )));

    expect(find.text('Friend'), findsOneWidget);
    expect(find.text('A Friend Indeed'), findsOneWidget);

    await tester.tap(find.byType(ActivityFollowCard));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('blocked members keep a readable follow card', (tester) async {
    final user = FollowListItem.fromJson(
        _user(9, username: 'Ghost', isActive: 'false'));
    await tester.pumpWidget(_wrap(ActivityFollowCard(
      user: user,
      onTap: () {},
    )));

    expect(find.text('Ghost'), findsOneWidget);
  });

  testWidgets('skeleton builds without errors', (tester) async {
    await tester.pumpWidget(_wrap(const ActivityCardSkeleton()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a like entry composes a note above a real post card',
      (tester) async {
    final item = _item({
      'type': 'like',
      'id': 1,
      'post': _post(5, username: 'Writer', content: 'hello world'),
    });
    // Same stacking ProfileScreen builds for the Activity tab: the note
    // then the normal PostCard (author row + content).
    await tester.pumpWidget(_wrap(Scaffold(
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: ActivityNote(item: item),
              ),
              PostCard(
                key: ValueKey(item.post!.id),
                post: item.post!,
                apiBaseUrl: 'https://example.com',
                social: SocialService(ApiClient(
                  store: _NoopStore(),
                  apiBaseUrl: 'https://example.com',
                )),
              ),
            ],
          ),
        ],
      ),
    )));

    expect(find.text('You liked'), findsOneWidget);
    expect(find.text('Writer'), findsOneWidget); // author row of the card
    expect(find.textContaining('hello world'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
