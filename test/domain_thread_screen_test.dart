import 'dart:async';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/domains_service.dart';
import 'package:enclavd/api/posts_service.dart';
import 'package:enclavd/api/social_service.dart';
import 'package:enclavd/screens/domain_thread_screen.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/shimmer.dart';

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

/// Fake domains service serving the OP + breadcrumb.
class _FakeDomains extends DomainsService {
  _FakeDomains(this._detail)
      : super(ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  final DomainThreadDetail _detail;

  @override
  Future<DomainThreadDetail> thread(int postId) async => _detail;
}

/// Fake social service with canned replies + a captured send.
class _FakeSocial extends SocialService {
  _FakeSocial({this.replies = const []})
      : super(ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  final List<Comment> replies;
  final List<int> ascQueries = [];
  final List<String> sent = [];

  @override
  Future<List<Comment>> listComments(int postId, {bool asc = false}) async {
    ascQueries.add(postId);
    expect(asc, isTrue, reason: 'forum replies must be oldest-first');
    return replies;
  }

  @override
  Future<(Comment, int)> createComment(int postId, String content) async {
    sent.add(content);
    final c = Comment(
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
    );
    // The OP declares comment_count 2; the server returns the REAL total
    // after insert (2 + 1). replies.length + 1 would undercount here.
    return (c, 3);
  }

  @override
  Future<int> deleteComment(int commentId, int postId) async => 0;
}

class _FakePosts extends PostsService {
  _FakePosts()
      : super(ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'));
}

Map<String, dynamic> _postJson() => {
      'id': 218,
      'author_id': 1,
      'content': 'The OP of the thread',
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
    };

DomainThreadDetail _detail() => DomainThreadDetail.fromJson({
      'success': true,
      'post': _postJson(),
      'breadcrumb': [
        {'id': 1, 'name': 'General', 'slug': 'general', 'parent': null},
      ],
    });

Comment _reply(int id, String text, {bool own = false}) => Comment(
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
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SoundService.muted = true;
  });

  Widget wrap(Widget child) => MaterialApp(
        theme: buildEnclavdTheme(),
        home: child,
      );

  testWidgets('renders the OP card + replies oldest-first', (tester) async {
    final social = _FakeSocial(replies: [
      _reply(1, 'First reply'),
      _reply(2, 'Second reply'),
    ]);
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: _FakeDomains(_detail()),
      postId: 218,
      social: social,
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));

    // OP content renders as the PostCard.
    expect(find.text('The OP of the thread'), findsOneWidget);
    // Replies header + both replies, oldest first.
    expect(find.text('2 Replies'), findsOneWidget);
    expect(find.text('First reply'), findsOneWidget);
    expect(find.text('Second reply'), findsOneWidget);
    // Reply number gutters #1 #2.
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    // The composer bar is present.
    expect(find.byType(TextField), findsOneWidget);
    expect(social.ascQueries, [218]);
  });

  testWidgets('sending a reply appends it and bumps the count',
      (tester) async {
    final social = _FakeSocial();
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: _FakeDomains(_detail()),
      postId: 218,
      social: social,
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.enterText(find.byType(TextField), 'My new reply');
    await tester.tap(find.byTooltip('Send reply'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(social.sent, ['My new reply']);
    expect(find.text('My new reply'), findsOneWidget);
    // 2 replies on the post → the header bumps to 3.
    expect(find.text('3 Replies'), findsOneWidget);
  });

  testWidgets('empty replies show the forum empty state', (tester) async {
    final social = _FakeSocial();
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: _FakeDomains(_detail()),
      postId: 218,
      social: social,
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('No replies yet'), findsOneWidget);
  });

  testWidgets('deleting an own reply removes it', (tester) async {
    final social = _FakeSocial(replies: [
      _reply(1, 'First reply'),
      _reply(2, 'My own reply', own: true),
    ]);
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: _FakeDomains(_detail()),
      postId: 218,
      social: social,
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));

    // The trash icon appears only on own replies (one).
    final trash = findFa(FontAwesomeIcons.trashCan);
    expect(trash, findsOneWidget);
    await tester.tap(trash);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('My own reply'), findsNothing);
    expect(find.text('First reply'), findsOneWidget);
  });

  testWidgets('missing thread shows the ghost error + retry', (tester) async {
    final failing = _FailingDomains();
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: failing,
      postId: 99999,
      social: _FakeSocial(),
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Thread not found.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('shows shimmer while loading', (tester) async {
    final gate = Completer<void>();
    final gated = _GatedDomains(_detail())..gate = gate;
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: gated,
      postId: 218,
      social: _FakeSocial(),
      posts: _FakePosts(),
    )));
    expect(find.byType(ShimmerBox), findsWidgets);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('The OP of the thread'), findsOneWidget);
  });
}

class _FailingDomains extends DomainsService {
  _FailingDomains()
      : super(
            ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  @override
  Future<DomainThreadDetail> thread(int postId) async {
    throw const ApiException('Thread not found', status: 404);
  }
}

class _GatedDomains extends DomainsService {
  _GatedDomains(this._detail)
      : super(ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  final DomainThreadDetail _detail;
  Completer<void>? gate;

  @override
  Future<DomainThreadDetail> thread(int postId) async {
    final g = gate;
    if (g != null) await g.future;
    return _detail;
  }
}

/// FaIcon converts its FaIconData to a plain IconData for storage — finders
/// must compare code points, never the FaIconData consts (11.x quirk).
Finder findFa(FaIconData icon) => find.byWidgetPredicate((w) =>
    w is FaIcon && w.icon != null && w.icon!.codePoint == icon.codePoint);
