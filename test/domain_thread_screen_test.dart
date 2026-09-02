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
import 'package:enclavd/widgets/enclavd_avatar.dart';
import 'package:enclavd/widgets/comment_quote_card.dart';
import 'package:enclavd/widgets/post_card.dart'; // PostCard (must be ABSENT)
import 'package:enclavd/widgets/shimmer.dart';

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

class _FakeDomains extends DomainsService {
  _FakeDomains(this._detail)
      : super(ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  final DomainThreadDetail _detail;

  @override
  Future<DomainThreadDetail> thread(int postId) async => _detail;
}

class _FakeSocial extends SocialService {
  _FakeSocial({this.replies = const []})
      : super(ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  final List<Comment> replies;

  /// Page numbers asked for; 0 = the newest page.
  final List<int> pageRequests = [];
  final List<String> sent = [];
  final List<int?> sentParents = [];

  @override
  Future<ForumReplyPage> forumRepliesPage(int postId,
      {int page = 0, int perPage = 20}) async {
    pageRequests.add(page);
    final total = replies.length;
    final pages = total > 0 ? (total + perPage - 1) ~/ perPage : 1;
    final index = page > 0 ? page - 1 : pages - 1;
    final start = index * perPage;
    final slice = start >= total
        ? const <Comment>[]
        : replies.sublist(start, (start + perPage).clamp(0, total));
    return ForumReplyPage(
      comments: slice,
      total: total,
      page: index + 1,
      pages: pages,
      hasMore: index + 1 < pages,
    );
  }

  @override
  Future<(Comment, int)> createComment(int postId, String content,
      {int? parentCommentId}) async {
    sent.add(content);
    sentParents.add(parentCommentId);
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
      parentCommentId: parentCommentId,
    );
    // OP declared 2 comments; the server returns the real total after insert (2 + 1).
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

Comment _reply(int id, String text,
        {bool own = false, String rank = 'Member', int? parent}) =>
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
      rank: rank,
      parentCommentId: parent,
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

  testWidgets('renders the OP card + single-page replies', (tester) async {
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

    expect(find.text('The OP of the thread'), findsOneWidget);
    expect(find.text('2 Replies'), findsOneWidget);
    expect(find.text('First reply'), findsOneWidget);
    expect(find.text('Second reply'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    // Composer is hidden until the Reply button reveals it.
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byKey(const Key('replyToggle')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(TextField), findsOneWidget);
    // The thread opens on the newest page (0 = last); 2 rows fit one.
    expect(social.pageRequests, [0]);
    // Single-page threads skip the pager bars.
    expect(find.textContaining('Page '), findsNothing);
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

    await tester.tap(find.byKey(const Key('replyToggle')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField), 'My new reply');
    await tester.tap(find.byTooltip('Send reply'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(social.sent, ['My new reply']);
    expect(find.text('My new reply'), findsOneWidget);
    // 2 replies on the post -> the header bumps to 3.
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

  testWidgets('deleting an own reply asks first, then removes it', (tester) async {
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

    // Cancel keeps the reply.
    await tester.tap(trash);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Delete this reply?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('My own reply'), findsOneWidget);

    // Confirming removes it. The row itself labels Delete too, so pick
    // the dialog's own action button.
    await tester.tap(trash);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Delete')));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('My own reply'), findsNothing);
    expect(find.text('First reply'), findsOneWidget);
  });

  testWidgets('a quoted reply renders flat with its context inline',
      (tester) async {
    const quoted = '@Someone wrote: "First reply"\n\nAgreed!';
    final social = _FakeSocial(replies: [
      _reply(1, 'First reply'),
      _reply(2, quoted, parent: 1),
    ]);
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: _FakeDomains(_detail()),
      postId: 218,
      social: social,
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));

    // Both rows are full cards in the flat list; no nesting affordances.
    // 'First reply' appears twice: the original card + its preview in
    // the quote card.
    expect(find.text('First reply'), findsNWidgets(2));
    expect(find.text('Agreed!'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.byType(CommentQuoteCard), findsOneWidget);
    // The quote header is the only "Replying to" text (no hint lines).
    expect(find.text('Replying to @Someone'), findsOneWidget);
    expect(find.text('1 reply'), findsNothing);
    expect(find.text('Hide replies'), findsNothing);

    // Both replies use the same full-size card layout.
    final avatars = tester
        .widgetList<EnclavdAvatar>(find.byType(EnclavdAvatar))
        .where((w) => w.url.contains('x.png'))
        .toList();
    expect(avatars, hasLength(2));
    expect(avatars.every((w) => w.size == 48), isTrue,
        reason: 'flat replies are full-size cards, not nested rows');
  });

  testWidgets('long replies collapse with a read-more toggle', (tester) async {
    final long = 'word ' * 120; // 600 chars, over the 200 limit
    final social = _FakeSocial(replies: [_reply(1, long)]);
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: _FakeDomains(_detail()),
      postId: 218,
      social: social,
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));

    // Collapsed: preview (word-boundary cut <= 200) + Read more.
    expect(find.text('Read more'), findsOneWidget);
    expect(find.text(long), findsNothing);

    // The long preview wraps below the viewport; scroll the toggle on screen first.
    await tester.ensureVisible(find.text('Read more'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Read more'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Show less'), findsOneWidget);
    expect(find.text(long), findsOneWidget);
  });

  testWidgets('only one long reply is expanded at a time', (tester) async {
    final long1 = 'first ' * 60; // 360 chars, over the 200 limit
    final long2 = 'second ' * 60; // 420 chars, over the 200 limit
    final social = _FakeSocial(replies: [_reply(1, long1), _reply(2, long2)]);
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: _FakeDomains(_detail()),
      postId: 218,
      social: social,
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Read more'), findsNWidgets(2));

    // Expand the first; the second stays collapsed.
    await tester.ensureVisible(find.text('Read more').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Read more').first);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Show less'), findsOneWidget);
    expect(find.text(long1), findsOneWidget);
    expect(find.text(long2), findsNothing);

    await tester.ensureVisible(find.text('Read more'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Read more'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Show less'), findsOneWidget);
    expect(find.text(long1), findsNothing);
    expect(find.text(long2), findsOneWidget);
  });

  testWidgets('opens on the newest page and pages back through replies',
      (tester) async {
    // Tall viewport: a full 20-card page must render without lazy
    // disposal, so every row and both pager bars stay findable.
    tester.view.physicalSize = const Size(800, 3800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 45 replies -> 3 pages (20/20/5); the thread must open showing the
    // LAST page (newest replies).
    final social = _FakeSocial(replies: [
      for (var n = 1; n <= 45; n++) _reply(n, 'Reply $n'),
    ]);
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: _FakeDomains(_detail()),
      postId: 218,
      social: social,
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));

    // Newest page 3: rows #41..#45; pager bars top and bottom.
    expect(social.pageRequests, [0], reason: 'open must fetch the last page');
    expect(find.text('Reply 41'), findsOneWidget);
    expect(find.text('Reply 45'), findsOneWidget);
    expect(find.text('Reply 1'), findsNothing);
    expect(find.text('#41'), findsOneWidget);
    expect(find.text('#45'), findsOneWidget);
    expect(find.text('Page 3 of 3'), findsNWidgets(2));

    // Prev walks to page 2 (#21..), then page 1 (#1..#20).
    await tester.tap(find.byTooltip('Older replies').first);
    await tester.pump(const Duration(milliseconds: 50));
    expect(social.pageRequests, [0, 2]);
    expect(find.text('Page 2 of 3'), findsNWidgets(2));
    expect(find.text('Reply 21'), findsOneWidget);
    expect(find.text('Reply 40'), findsOneWidget);
    expect(find.text('Reply 45'), findsNothing);

    await tester.tap(find.byTooltip('Older replies').first);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Page 1 of 3'), findsNWidgets(2));
    expect(find.text('Reply 1'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('Reply 45'), findsNothing);

    // Prev is disabled on page 1: tapping does not refetch.
    final before = social.pageRequests.length;
    await tester.tap(find.byTooltip('Older replies').first);
    await tester.pump(const Duration(milliseconds: 50));
    expect(social.pageRequests.length, before);

    // Next walks forward again to the newest page.
    await tester.tap(find.byTooltip('Newer replies').first);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byTooltip('Newer replies').first);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Page 3 of 3'), findsNWidgets(2));
    expect(find.text('Reply 45'), findsOneWidget);
  });

  testWidgets('OP is a forum card: rank badge, large avatar, no PostCard',
      (tester) async {
    final social = _FakeSocial(replies: [_reply(1, 'First reply')]);
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: _FakeDomains(_detail()),
      postId: 218,
      social: social,
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));

    // The OP is NOT a feed PostCard; it's the forum card.
    expect(find.byType(PostCard), findsNothing);
    expect(find.text('SysOp'), findsOneWidget);
    expect(find.text('Member'), findsOneWidget);
    EnclavdAvatar avatarOf(String urlPart) => tester.widget<EnclavdAvatar>(
        find.byWidgetPredicate(
            (w) => w is EnclavdAvatar && w.url.contains(urlPart)));
    expect(avatarOf('dev.png').size, 54, reason: 'OP avatar is forum-large');
    expect(avatarOf('x.png').size, 48, reason: 'reply avatar is forum-large');
    expect(avatarOf('dev.png').square, isTrue,
        reason: 'forum avatars are squared with rounded corners');
    expect(avatarOf('x.png').square, isTrue);
  });

  testWidgets('reply on another reply quotes it in the composer and on send',
      (tester) async {
    final social = _FakeSocial(replies: [
      _reply(1, 'First reply'), // someone else's
    ]);
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: _FakeDomains(_detail()),
      postId: 218,
      social: social,
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('replyToggle')), findsOneWidget);
    expect(find.text('Delete'), findsNothing);

    await tester.tap(find.byKey(const Key('replyQuote-1')));
    await tester.pump(const Duration(milliseconds: 50));

    // Quote banner names the target above the composer (card + banner = two occurrences).
    expect(find.text('Replying to @Someone'), findsOneWidget);
    expect(find.text('First reply'), findsNWidgets(2));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);

    await tester.enterText(find.byType(TextField), 'Agreed!');
    await tester.tap(find.byTooltip('Send reply'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(social.sent, ['@Someone wrote: "First reply"\n\nAgreed!']);
    expect(social.sentParents, [1]);
    // The sent reply is a new flat card (appended locally): it carries
    // the quote prefix, so it renders as a styled quote card whose
    // "Replying to @Someone" header replaces the banner; the typed text
    // renders as the reply's own content.
    expect(find.byType(CommentQuoteCard), findsOneWidget);
    expect(find.text('Replying to @Someone'), findsOneWidget);
    expect(find.text('Agreed!'), findsOneWidget);
  });

  testWidgets('reply chains render as separate flat cards, all numbered',
      (tester) async {
    final social = _FakeSocial(replies: [
      _reply(1, 'Root reply'),
      _reply(2, 'Child reply', parent: 1),
      _reply(3, 'Grandchild reply', parent: 2),
    ]);
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: _FakeDomains(_detail()),
      postId: 218,
      social: social,
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));

    // Every reply is its own row with its own number; there is no tree,
    // no count toggle and no reply-to hint (quotes carry the context).
    expect(find.text('Root reply'), findsOneWidget);
    expect(find.text('Child reply'), findsOneWidget);
    expect(find.text('Grandchild reply'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('#3'), findsOneWidget);
    expect(find.text('3 Replies'), findsOneWidget);
    expect(find.text('Replying to @Someone'), findsNothing);
    // Quoting still works from any row (its parent id rides along).
    await tester.ensureVisible(find.byKey(const Key('replyQuote-3')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('replyQuote-3')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Replying to @Someone'), findsOneWidget); // banner
  });

  testWidgets('quoting a reply arms its parent id on send',
      (tester) async {
    final social = _FakeSocial(replies: [
      _reply(1, 'Root reply'),
      _reply(2, 'Child reply', parent: 1),
    ]);
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: _FakeDomains(_detail()),
      postId: 218,
      social: social,
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));

    // Reply rows are always visible flat; quoting any row arms its id.
    await tester.tap(find.byKey(const Key('replyQuote-2')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Replying to @Someone'), findsOneWidget); // banner

    await tester.enterText(find.byType(TextField), 'Deep reply');
    await tester.tap(find.byTooltip('Send reply'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(social.sentParents, [2]);
  });

  testWidgets('the quote banner can be dismissed before sending',
      (tester) async {
    final social = _FakeSocial(replies: [_reply(1, 'First reply')]);
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: _FakeDomains(_detail()),
      postId: 218,
      social: social,
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const Key('replyQuote-1')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Replying to @Someone'), findsOneWidget);

    await tester.tap(findFa(FontAwesomeIcons.xmark));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Replying to @Someone'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Just this');
    await tester.tap(find.byTooltip('Send reply'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(social.sent, ['Just this']);
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

/// FaIcon stores FaIconData as plain IconData; finders must compare code points (11.x quirk).
Finder findFa(FaIconData icon) => find.byWidgetPredicate((w) =>
    w is FaIcon && w.icon != null && w.icon!.codePoint == icon.codePoint);
