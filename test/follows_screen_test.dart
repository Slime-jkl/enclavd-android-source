import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/profile_service.dart';
import 'package:enclavd/screens/follows_screen.dart';
import 'package:enclavd/theme/enclavd_theme.dart';

FollowListItem _user({
  int id = 1,
  String username = 'User',
  String fullName = '',
  String bio = '',
  String rank = 'Member',
  String? personalityType,
  String isActive = 'true',
  bool isFollowing = false,
  bool isFollowingYou = false,
  bool isOwn = false,
}) =>
    FollowListItem.fromJson({
      'id': id,
      'username': username,
      'full_name': fullName,
      'profile_picture_url': '/a.png',
      'personality_type': personalityType,
      'rank': rank,
      'bio': bio,
      'is_active': isActive,
      'is_online': false,
      'is_following': isFollowing,
      'is_following_you': isFollowingYou,
      'is_own': isOwn,
    });

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

class _FakeProfile extends ProfileService {
  _FakeProfile() : super(_client());

  static ApiClient _client() => ApiClient(
        store: _NoopStore(),
        apiBaseUrl: 'https://example.com',
      );

  List<FollowListItem> followers = [];
  List<FollowListItem> following = [];
  bool failFirstListCall = false;
  int listCalls = 0;
  int toggleCalls = 0;
  bool respondFollowing = true;

  @override
  Future<FollowListPage> listFollows({
    required int userId,
    required FollowListKind kind,
    int limit = 20,
    int offset = 0,
  }) async {
    listCalls++;
    if (failFirstListCall) {
      failFirstListCall = false;
      throw const ApiException('Network down');
    }
    final src = kind == FollowListKind.followers ? followers : following;
    final page = src.skip(offset).take(limit).toList();
    return FollowListPage(
      users: page,
      total: src.length,
      hasMore: offset + page.length < src.length,
    );
  }

  @override
  Future<FollowResult> toggleFollow(int followeeId) async {
    toggleCalls++;
    return FollowResult(
        following: respondFollowing, followerCount: 0, followingCount: 0);
  }
}

Finder _tab(String label) => find.descendant(
    of: find.byType(TabBar), matching: find.text(label));

Finder _rowButton(String label) =>
    find.widgetWithText(TextButton, label);

void main() {
  Future<_FakeProfile> pumpScreen(
    WidgetTester tester,
    _FakeProfile fake, {
    FollowListKind initialTab = FollowListKind.followers,
    bool isOwnList = false,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: FollowsScreen(
        profile: fake,
        userId: 7,
        username: 'Dev',
        initialTab: initialTab,
        isOwnList: isOwnList,
      ),
    ));
    // The fake resolves in a microtask; let the first page render.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return fake;
  }

  group('FollowsScreen', () {
    testWidgets('followers tab renders rows with relation buttons',
        (tester) async {
      final fake = _FakeProfile()
        ..followers = [
          _user(id: 1, username: 'Alice'),
          _user(id: 2, username: 'Bob', isFollowing: true),
          _user(id: 3, username: 'Celine', isFollowingYou: true),
        ];
      await pumpScreen(tester, fake);

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Celine'), findsOneWidget);
      expect(_rowButton('Follow'), findsOneWidget,
          reason: 'not-following row gets a plain Follow');
      expect(_rowButton('Follow Back'), findsOneWidget,
          reason: 'someone who follows you gets Follow Back');
      expect(_rowButton('Following'), findsOneWidget,
          reason: 'already-following row shows the Following state');
    });

    testWidgets('tap Follow toggles the row to Following', (tester) async {
      final fake = _FakeProfile()..followers = [_user(id: 1, username: 'Alice')];
      await pumpScreen(tester, fake);

      await tester.tap(_rowButton('Follow'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(fake.toggleCalls, 1);
      expect(_rowButton('Following'), findsOneWidget,
          reason: 'row state flips after a successful follow');
      expect(_rowButton('Follow'), findsNothing);
    });

    testWidgets('tab switch loads the other list', (tester) async {
      final fake = _FakeProfile()
        ..followers = [_user(id: 1, username: 'Alice')]
        ..following = [_user(id: 2, username: 'Dave')];
      await pumpScreen(tester, fake);
      expect(find.text('Alice'), findsOneWidget);
      expect(fake.listCalls, 1);

      await tester.tap(_tab('Following'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // The target page mounts during the animation; its fetch resolves
      // after it, so one more frame renders the rows.
      await tester.pump();

      expect(find.text('Dave'), findsOneWidget);
      expect(fake.listCalls, 2, reason: 'following tab fetched on demand');
    });

    testWidgets('opens directly on the tapped tab', (tester) async {
      final fake = _FakeProfile()
        ..followers = [_user(id: 1, username: 'Alice')]
        ..following = [_user(id: 2, username: 'Dave')];
      await pumpScreen(tester, fake,
          initialTab: FollowListKind.following);

      expect(find.text('Dave'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      expect(fake.listCalls, 1,
          reason: 'only the requested list is fetched');
    });

    testWidgets('empty list shows the empty state', (tester) async {
      final fake = _FakeProfile();
      await pumpScreen(tester, fake);
      expect(find.text('No followers yet.'), findsOneWidget);
    });

    testWidgets('load failure shows retry which reloads', (tester) async {
      final fake = _FakeProfile()
        ..failFirstListCall = true
        ..followers = [_user(id: 1, username: 'Alice')];
      await pumpScreen(tester, fake);

      expect(find.text('Failed to load followers.'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('unfollow on the own Following list removes the row',
        (tester) async {
      final fake = _FakeProfile()
        ..respondFollowing = false
        ..following = [_user(id: 2, username: 'Dave', isFollowing: true)];
      await pumpScreen(tester, fake,
          initialTab: FollowListKind.following, isOwnList: true);

      await tester.tap(_rowButton('Following'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Dave'), findsNothing,
          reason: 'unfollowed from own list: row no longer belongs');
      expect(find.text('You are not following anyone yet.'), findsOneWidget);
    });

    testWidgets('the viewer\'s own row shows You with no follow button',
        (tester) async {
      final fake = _FakeProfile()
        ..followers = [_user(id: 7, username: 'Dev', isOwn: true)];
      await pumpScreen(tester, fake);

      expect(find.text('You'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing,
          reason: 'self row cannot follow itself');
    });
  });
}
