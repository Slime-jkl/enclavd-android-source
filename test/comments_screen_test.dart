import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/feed_service.dart';
import 'package:enclavd/api/social_service.dart';
import 'package:enclavd/screens/comments_screen.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/enclavd_avatar.dart';
import 'package:enclavd/widgets/post_card.dart';
import 'package:enclavd/widgets/thread_connector.dart';

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

class _FakeSocial extends SocialService {
  _FakeSocial({this.comments = const []})
      : super(ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  final List<Comment> comments;
  final List<String> sent = [];
  final List<int?> sentParents = [];

  @override
  Future<CommentPage> listComments(int postId,
      {bool asc = false, int limit = SocialService.pageSize, int offset = 0}) async {
    return CommentPage(
      comments: offset == 0 ? comments : const [],
      total: comments.length,
      hasMore: false,
    );
  }

  @override
  Future<(Comment, int)> createComment(int postId, String content,
      {int? parentCommentId}) async {
    sent.add(content);
    sentParents.add(parentCommentId);
    return (
      Comment(
        id: 999,
        postId: postId,
        userId: 1,
        username: 'Me',
        profilePictureUrl: '/public/avatars/me.png',
        personalityType: null,
        nameColor: 'text-gray-400',
        hasWarnings: false,
        createdAt: 'now',
        content: content,
        isOwner: true,
        parentCommentId: parentCommentId,
      ),
      3,
    );
  }

  @override
  Future<int> deleteComment(int commentId, int postId) async => 0;
}

Map<String, dynamic> _postJson() => {
      'id': 218,
      'author_id': 1,
      'content': 'The post content',
      'created_at': '2026-08-12 10:32:59',
      'feed_score': null,
      'like_count': 1,
      'comment_count': 2,
      'user_liked': false,
      'warning_count': 0,
      'username': 'Developer',
      'profile_picture_url': '/public/avatars/dev.png',
      'personality_type': 'INTJ',
      'is_active': 'true',
      'rank': 'SysOp',
      'image': null,
      'is_owner': false,
      'has_domain': false,
    };

Post _post() => Post.fromJson(_postJson());

Comment _comment(int id, String text, {int? parent, bool own = false}) =>
    Comment(
      id: id,
      postId: 218,
      userId: own ? 1 : 2,
      username: own ? 'Me' : 'Someone',
      profilePictureUrl: '/public/avatars/x.png',
      personalityType: null,
      nameColor: 'text-gray-400',
      hasWarnings: false,
      createdAt: '5m',
      content: text,
      isOwner: own,
      parentCommentId: parent,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SoundService.muted = true);
  tearDown(() => SoundService.muted = false);

  Widget wrap(Widget child) => MaterialApp(
        theme: buildEnclavdTheme(),
        home: child,
      );

  testWidgets('nested replies start collapsed behind the count toggle',
      (tester) async {
    final social = _FakeSocial(comments: [
      _comment(1, 'Root comment'),
      _comment(2, 'Child reply', parent: 1),
    ]);
    await tester.pumpWidget(wrap(CommentsScreen(
      post: _post(),
      social: social,
      apiBaseUrl: 'https://example.com',
    )));
    await tester.pump(const Duration(milliseconds: 50));

    // Post context + the root comment + the composer.
    expect(find.text('The post content'), findsOneWidget);
    expect(find.text('Root comment'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    // The nested reply is hidden behind its count toggle by default.
    expect(find.text('Child reply'), findsNothing);
    expect(find.text('1 reply'), findsOneWidget);
    expect(find.text('Replying to @Someone'), findsNothing);

    // Tapping the toggle expands the reply under the root.
    await tester.tap(find.text('1 reply'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Child reply'), findsOneWidget);
    expect(find.text('Replying to @Someone'), findsOneWidget);

    // Tapping again collapses it back behind the toggle.
    await tester.tap(find.text('Hide reply'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Child reply'), findsNothing);
    expect(find.text('1 reply'), findsOneWidget);
    // Short posts render in full: no read-more toggle on the header.
    expect(find.text('Show more'), findsNothing);
  });

  testWidgets('long post content clamps behind a show-more toggle',
      (tester) async {
    final social = _FakeSocial();
    final post = Post.fromJson(_postJson()..['content'] = 'word ' * 200);
    await tester.pumpWidget(wrap(CommentsScreen(
      post: post,
      social: social,
      apiBaseUrl: 'https://example.com',
    )));
    await tester.pump(const Duration(milliseconds: 50));

    // Collapsed by default; expanding reveals the full text, and the
    // toggle flips back so it can be clamped again.
    expect(find.text('Show more'), findsOneWidget);
    await tester.tap(find.text('Show more'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Show less'), findsOneWidget);
    await tester.tap(find.text('Show less'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Show more'), findsOneWidget);
  });

  testWidgets('deleting an own comment asks first, then drops the subtree',
      (tester) async {
    final social = _FakeSocial(comments: [
      _comment(1, 'My comment', own: true),
      _comment(2, 'Child reply', parent: 1),
    ]);
    await tester.pumpWidget(wrap(CommentsScreen(
      post: _post(),
      social: social,
      apiBaseUrl: 'https://example.com',
    )));
    await tester.pump(const Duration(milliseconds: 50));

    // Cancel keeps the thread intact (nested reply still behind its toggle).
    await tester.tap(findFa(FontAwesomeIcons.trashCan));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Delete this comment?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('My comment'), findsOneWidget);
    expect(find.text('1 reply'), findsOneWidget);

    // Confirming removes the comment and its replies together.
    await tester.tap(findFa(FontAwesomeIcons.trashCan));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Delete')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('My comment'), findsNothing);
    expect(find.text('1 reply'), findsNothing);
  });

  testWidgets('nested avatar stays top-aligned so the L hits its center',
      (tester) async {
    // A multi-line reply makes the row tall; the avatar must hug the top
    // (elbowY 20 = 6 pad + 28/2) instead of floating mid-row.
    final long = 'word ' * 40;
    final social = _FakeSocial(comments: [
      _comment(1, 'Root comment'),
      _comment(2, long, parent: 1),
    ]);
    await tester.pumpWidget(wrap(CommentsScreen(
      post: _post(),
      social: social,
      apiBaseUrl: 'https://example.com',
    )));
    await tester.pump(const Duration(milliseconds: 50));

    // The group starts collapsed; open it so the elbow row exists.
    await tester.tap(find.text('1 reply'));
    await tester.pump(const Duration(milliseconds: 50));

    final elbowBox = tester.renderObject<RenderBox>(find.byType(ThreadElbow));
    expect(elbowBox.size.height, greaterThan(100),
        reason: 'multi-line reply must make the row tall');

    // The child avatar is the second x.png one (root first, child after).
    final childAvatar = find.byWidgetPredicate((w) =>
        w is EnclavdAvatar &&
        w.url.contains('x.png') &&
        w.size == 28);
    final avatarBox = tester.renderObject<RenderBox>(childAvatar.last);
    final rowTop = elbowBox.localToGlobal(Offset.zero).dy;
    final avatarTop = avatarBox.localToGlobal(Offset.zero).dy;
    final avatarCenter = avatarBox
        .localToGlobal(Offset(0, avatarBox.size.height / 2))
        .dy;

    expect(avatarBox.size.height, 28);
    expect(avatarTop - rowTop, closeTo(6, 1), reason: 'avatar top pad');
    expect(avatarCenter - rowTop, closeTo(20, 1),
        reason: 'avatar center must sit on the elbow arm (6 + 28/2)');
    expect(avatarCenter - rowTop, lessThan(elbowBox.size.height / 3),
        reason: 'avatar must NOT be vertically centered on tall rows');

    // The rail hangs from the ROOT avatar's middle with air, not glued
    // to its rim: bridge x = the avatar center (14), start a gap below
    // the circle bottom (6 pad + 28 box + 4), and the first child rail
    // picks up at the same x flush below the root row.
    final rail = tester.widget<RailDrop>(find.byType(RailDrop));
    final railBox = tester.renderObject<RenderBox>(find.byType(RailDrop));
    expect(rail.railX, 14, reason: 'bridge drops under the avatar center');
    expect(rail.startY, 38,
        reason: 'bridge starts a gap below the avatar bottom (34 + 4)');
    final rootAvatarBox = tester.renderObject<RenderBox>(childAvatar.first);
    final rootTop = rootAvatarBox.localToGlobal(Offset.zero).dy;
    final railStart = railBox
        .localToGlobal(Offset(0, rail.startY))
        .dy;
    expect(railStart, greaterThan(rootTop + 28),
        reason: 'bridge must clear the avatar, not touch its rim');
    expect(railStart, closeTo(rootTop + 32, 1),
        reason: 'about 4px of air between the avatar bottom and the stem');
    final railX = railBox.localToGlobal(Offset(rail.railX, 0)).dx;
    expect(
        railX,
        closeTo(rootAvatarBox
            .localToGlobal(Offset(rootAvatarBox.size.width / 2, 0))
            .dx, 0.5),
        reason: 'stem passes through the avatar middle, not beside it');
    final elbowX = elbowBox
        .localToGlobal(Offset(elbowBox.size.width / 2, 0))
        .dx;
    expect(elbowX, closeTo(railX, 0.5),
        reason: 'child rail continues the bridge at the same x');
    expect(
        railBox.localToGlobal(Offset(0, railBox.size.height)).dy,
        closeTo(rowTop, 0.5),
        reason: 'bridge bottom must be flush with the first elbow');
  });

  testWidgets('sending arms the parent id and prepends the new comment',
      (tester) async {
    final social = _FakeSocial(comments: [_comment(1, 'Root comment')]);
    await tester.pumpWidget(wrap(CommentsScreen(
      post: _post(),
      social: social,
      apiBaseUrl: 'https://example.com',
    )));
    await tester.pump(const Duration(milliseconds: 50));

    // Reply to the root: the chip appears above the composer.
    await tester.tap(findFa(FontAwesomeIcons.reply).first);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Replying to @Someone'), findsOneWidget); // chip

    // The mention prefill stays in the field; type after it (enterText
    // would REPLACE the whole text).
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '@Someone ');
    field.controller!.text = '${field.controller!.text}My comment';
    await tester.tap(find.byTooltip('Send comment'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(social.sent, ['@Someone My comment']);
    expect(social.sentParents, [1]);
    // The new reply nests under the root, so it starts behind the
    // count toggle; the chip is cleared too.
    expect(find.text('1 reply'), findsOneWidget);
    expect(find.textContaining('My comment'), findsNothing);
    expect(find.text('Replying to @Someone'), findsNothing);

    // Expanding shows the plain (non-quoted) reply under the root with
    // its reply-to hint.
    await tester.tap(find.text('1 reply'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('My comment'), findsOneWidget);
    expect(find.text('Replying to @Someone'), findsOneWidget);
  });

  testWidgets('back button closes the screen and returns the count',
      (tester) async {
    final social = _FakeSocial(comments: [_comment(1, 'Root comment')]);
    int? popped;
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<int>(
                  CommentsScreen.route(
                    post: _post(),
                    social: social,
                    apiBaseUrl: 'https://example.com',
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    // Zoom route (340ms) + the async comment load; fixed pumps, no
    // pumpAndSettle (network-image shimmers never settle in tests).
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CommentsScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CommentsScreen), findsNothing);
    expect(popped, 1); // the loaded total (1 comment)
  });

  testWidgets('post card comment tap opens the full-screen comments',
      (tester) async {
    final social = _FakeSocial(comments: [_comment(1, 'Root comment')]);
    await tester.pumpWidget(wrap(Scaffold(
      body: PostCard(
        post: _post(),
        apiBaseUrl: 'https://example.com',
        social: social,
      ),
    )));

    await tester.tap(findFa(FontAwesomeIcons.comments).first);
    // Double-tap detector delays the tap ~300ms, then the zoom route.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CommentsScreen), findsOneWidget);
    expect(find.text('Root comment'), findsOneWidget);
  });
}

/// FaIcon stores FaIconData as plain IconData; finders must compare code points (11.x quirk).
Finder findFa(FaIconData icon) => find.byWidgetPredicate((w) =>
    w is FaIcon && w.icon != null && w.icon!.codePoint == icon.codePoint);
