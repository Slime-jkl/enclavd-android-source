import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/feed_service.dart';
import 'package:enclavd/api/social_service.dart';
import 'package:enclavd/screens/comments_screen.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/post_card.dart';

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

  testWidgets('shows the post header + nested comments + pinned composer',
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

    // Post context + both comments + the composer.
    expect(find.text('The post content'), findsOneWidget);
    expect(find.text('Root comment'), findsOneWidget);
    expect(find.text('Child reply'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    // Nested row carries the reply-to hint.
    expect(find.text('Replying to @Someone'), findsOneWidget);
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
    // The comment renders as a plain (non-quoted) reply under the root.
    expect(find.textContaining('My comment'), findsOneWidget);
    // Chip cleared; the new nested reply carries the reply-to hint.
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
