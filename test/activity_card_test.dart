import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/activity_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/activity_card.dart';

Map<String, dynamic> _post(int id,
        {String username = 'Writer',
        String content = 'a post worth reading',
        String isActive = 'true'}) =>
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
      'is_active': isActive,
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

Widget _wrap(Widget child) => MaterialApp(
      theme: buildEnclavdTheme(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('like card shows the action, the author and the post preview',
      (tester) async {
    final item = ActivityItem.fromJson({
      'type': 'like',
      'id': 1,
      'created_at': _minutesAgo(),
      'post': _post(5, content: 'hello world'),
    });
    await tester.pumpWidget(_wrap(ActivityCard(item: item, onTap: () {})));

    expect(
        find.textContaining("You liked a post by @Writer's post",
            findRichText: true),
        findsOneWidget);
    // Post preview chip quotes the content.
    expect(find.textContaining('hello world'), findsOneWidget);
    expect(find.text('10m'), findsOneWidget);
  });

  testWidgets('comment card shows what the viewer wrote', (tester) async {
    final item = ActivityItem.fromJson({
      'type': 'comment',
      'id': 2,
      'created_at': _minutesAgo(),
      'content': 'I agree with this',
      'parent_comment_id': null,
      'post': _post(5),
    });
    await tester.pumpWidget(_wrap(ActivityCard(item: item, onTap: () {})));

    expect(
        find.textContaining("You commented on @Writer's post",
            findRichText: true),
        findsOneWidget);
    // The comment text is the card detail (no quotes around your own words).
    expect(find.text('I agree with this'), findsOneWidget);
  });

  testWidgets('follow card names the member and their full name',
      (tester) async {
    final item = ActivityItem.fromJson({
      'type': 'follow',
      'id': 7,
      'created_at': _minutesAgo(),
      'user': _user(7, username: 'Friend', fullName: 'A Friend Indeed'),
    });
    await tester.pumpWidget(_wrap(ActivityCard(item: item, onTap: () {})));

    expect(
        find.textContaining('You followed @Friend', findRichText: true),
        findsOneWidget);
    expect(find.text('A Friend Indeed'), findsOneWidget);
  });

  testWidgets('a blocked author renders without a tap target issue',
      (tester) async {
    final item = ActivityItem.fromJson({
      'type': 'follow',
      'id': 9,
      'created_at': _minutesAgo(),
      'user': _user(9, username: 'Ghost', isActive: 'false'),
    });
    await tester.pumpWidget(_wrap(ActivityCard(item: item, onTap: () {})));

    expect(
        find.textContaining('You followed @Ghost', findRichText: true),
        findsOneWidget);
  });

  testWidgets('tapping the card fires onTap', (tester) async {
    final item = ActivityItem.fromJson({
      'type': 'like',
      'id': 3,
      'created_at': _minutesAgo(),
      'post': _post(5),
    });
    var taps = 0;
    await tester.pumpWidget(
        _wrap(ActivityCard(item: item, onTap: () => taps++)));

    await tester.tap(find.byType(ActivityCard));
    await tester.pump();
    expect(taps, 1);
  });
}
