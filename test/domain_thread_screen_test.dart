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
import 'package:enclavd/utils/db_time.dart';
import 'package:enclavd/widgets/enclavd_avatar.dart';
import 'package:enclavd/widgets/comment_quote_card.dart';
import 'package:enclavd/widgets/post_card.dart'; // PostCard (must be ABSENT)
import 'package:enclavd/widgets/shimmer.dart';
import 'package:enclavd/widgets/thread_connector.dart';

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
    // The server resolves the reply target for its response, so the card
    // it lands on shows the quote without a refetch.
    Comment? target;
    for (final r in replies) {
      if (r.id == parentCommentId) target = r;
    }
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
      parentUsername: target?.username,
      parentExcerpt: target?.content.replaceAll(RegExp(r'\s+'), ' ').trim(),
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

const _opCreatedAt = '2026-08-12 10:32:59';

Map<String, dynamic> _postJson() => {
      'id': 218,
      'author_id': 1,
      'content': 'The OP of the thread',
      'created_at': _opCreatedAt,
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
        {bool own = false, String rank = 'Member', int? parent,
        bool warnings = false, String? parentName, String? parentExcerpt}) =>
    Comment(
      id: id,
      postId: 218,
      userId: own ? 1 : 2,
      username: own ? 'Me' : 'Someone',
      profilePictureUrl: '/public/avatars/x.png',
      personalityType: null,
      nameColor: 'text-gray-400',
      hasWarnings: warnings,
      createdAt: '5m',
      createdAtUtc: '5m', // raw db string the time badge renders
      content: text,
      isOwner: own,
      rank: rank,
      parentCommentId: parent,
      parentUsername: parentName,
      parentExcerpt: parentExcerpt,
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

  testWidgets('a reply quotes the reply it answers', (tester) async {
    final social = _FakeSocial(replies: [
      _reply(1, 'First reply'),
      // The server resolves the target from parent_comment_id, so the row
      // quotes it without carrying any prefix in its own text.
      _reply(2, 'Agreed!',
          parent: 1, parentName: 'Someone', parentExcerpt: 'First reply'),
    ]);
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: _FakeDomains(_detail()),
      postId: 218,
      social: social,
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));

    // 'First reply' appears twice: the root card + the quote card's preview.
    expect(find.text('First reply'), findsNWidgets(2));
    expect(find.text('Agreed!'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.byType(CommentQuoteCard), findsOneWidget);
    expect(find.text('Replying to @Someone'), findsOneWidget);

    // Flat list (locked): the quote card carries the context and the rows
    // stay full-size cards at the same left edge. No tree, no rail.
    expect(find.byType(ThreadElbow), findsNothing);
    expect(find.byType(RailDrop), findsNothing);
    final rootLeft = tester.getTopLeft(find.text('First reply').first).dx;
    final replyLeft = tester.getTopLeft(find.text('Agreed!')).dx;
    expect((replyLeft - rootLeft).abs() < 1.0, isTrue,
        reason: 'replies are not indented into a tree');
  });

  testWidgets('a legacy quoted reply still renders its stored quote',
      (tester) async {
    // Rows written before the reply target became the source of truth keep
    // the '@user wrote: "..."' prefix, which still renders as the card.
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

    expect(find.byType(CommentQuoteCard), findsOneWidget);
    expect(find.text('Replying to @Someone'), findsOneWidget);
    expect(find.text('Agreed!'), findsOneWidget);
    // The prefix never leaks into the body as raw text.
    expect(find.text(quoted), findsNothing);
    expect(find.text('First reply'), findsNWidgets(2));
  });

  testWidgets('a reply whose target sits on another page keeps its quote',
      (tester) async {
    // 21 replies -> the thread opens on page 2 (just row 21). Row 21 answers
    // row 1, which is on page 1: the row still renders (flat list) with the
    // quote the server resolved for it.
    final social = _FakeSocial(replies: [
      for (var n = 1; n <= 20; n++) _reply(n, 'Reply $n'),
      _reply(21, 'Orphan reply',
          parent: 1, parentName: 'Someone', parentExcerpt: 'Reply 1'),
    ]);
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: _FakeDomains(_detail()),
      postId: 218,
      social: social,
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Orphan reply'), findsOneWidget);
    expect(find.text('#21'), findsOneWidget);
    expect(find.byType(CommentQuoteCard), findsOneWidget);
    expect(find.text('Replying to @Someone'), findsOneWidget);
    // The target's own card is on page 1 and is not rendered; its text only
    // shows up as the quote card's excerpt.
    expect(find.text('Reply 1'), findsOneWidget);
    expect(find.text('Reply 20'), findsNothing);
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
    // Rank badge sits ABOVE the username on both the OP and every
    // reply card (the two-line identity block they share).
    expect(tester.getTopLeft(find.text('SysOp')).dy <
            tester.getTopLeft(find.text('Developer')).dy,
        isTrue, reason: 'OP rank badge above its username');
    expect(tester.getTopLeft(find.text('Member')).dy <
            tester.getTopLeft(find.text('Someone')).dy,
        isTrue, reason: 'reply rank badge above its username');
    EnclavdAvatar avatarOf(String urlPart) => tester.widget<EnclavdAvatar>(
        find.byWidgetPredicate(
            (w) => w is EnclavdAvatar && w.url.contains(urlPart)));
    expect(avatarOf('dev.png').size, 54, reason: 'OP avatar is forum-large');
    expect(avatarOf('x.png').size, 48, reason: 'reply avatar is forum-large');
    expect(avatarOf('dev.png').square, isTrue,
        reason: 'forum avatars are squared with rounded corners');
    expect(avatarOf('x.png').square, isTrue);
  });

  testWidgets('active warnings hug the username, not the rank line',
      (tester) async {
    final postJson = _postJson()..['warning_count'] = 2;
    final detail = DomainThreadDetail.fromJson({
      'success': true,
      'post': postJson,
      'breadcrumb': const [
        {'id': 1, 'name': 'General', 'slug': 'general', 'parent': null},
      ],
    });
    final social =
        _FakeSocial(replies: [_reply(1, 'First reply', warnings: true)]);
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: _FakeDomains(detail),
      postId: 218,
      social: social,
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));

    final icons = findFa(FontAwesomeIcons.triangleExclamation);
    expect(icons, findsNWidgets(2)); // OP (icon + count) and the reply

    // Warnings share the username's line (rank line is above it) and
    // start right after the username text on both card kinds.
    final opWarn = tester.getTopLeft(icons.at(0));
    final opName = tester.getTopLeft(find.text('Developer'));
    expect(opWarn.dy >= opName.dy - 1 && opWarn.dy <= opName.dy + 10, isTrue,
        reason: 'OP warnings sit on the username line');
    expect(opWarn.dx >= tester.getTopRight(find.text('Developer')).dx - 1,
        isTrue, reason: 'OP warnings start right of the username');
    final replyWarn = tester.getTopLeft(icons.at(1));
    final replyName = tester.getTopLeft(find.text('Someone'));
    expect(replyWarn.dy >= replyName.dy - 1 &&
            replyWarn.dy <= replyName.dy + 10,
        isTrue, reason: 'reply warnings sit on the username line');
    expect(replyWarn.dx >= tester.getTopRight(find.text('Someone')).dx - 1,
        isTrue, reason: 'reply warnings start right of the username');
  });

  testWidgets('reply body starts under the avatar; time rides the rank line',
      (tester) async {
    final social = _FakeSocial(replies: [_reply(1, 'First reply')]);
    await tester.pumpWidget(wrap(DomainThreadScreen(
      domains: _FakeDomains(_detail()),
      postId: 218,
      social: social,
      posts: _FakePosts(),
    )));
    await tester.pump(const Duration(milliseconds: 50));

    // Body text starts at the card's left edge (under the avatar), not
    // indented under the username column.
    final avatarLeft = tester
        .getTopLeft(find.byWidgetPredicate(
            (w) => w is EnclavdAvatar && w.url.contains('x.png')))
        .dx;
    final body = tester.getTopLeft(find.text('First reply'));
    expect((body.dx - avatarLeft).abs() < 1.0, isTrue,
        reason: 'reply body spans the card under the avatar');

    // Reply time: on the rank badge line, above the username, near the
    // card's right edge.
    final time = tester.getTopLeft(find.text('5m'));
    final badge = tester.getTopLeft(find.text('Member'));
    final name = tester.getTopLeft(find.text('Someone'));
    expect((time.dy - badge.dy).abs() <= 12, isTrue,
        reason: 'reply time shares the rank badge line');
    expect(time.dy < name.dy - 8, isTrue,
        reason: 'reply time is above the username');
    expect(time.dx > 600, isTrue, reason: 'reply time sits top-right');

    // The OP card follows the same layout.
    final opTime = tester.getTopLeft(find.text(relativeTime(_opCreatedAt)));
    final opBadge = tester.getTopLeft(find.text('SysOp'));
    final opName = tester.getTopLeft(find.text('Developer'));
    expect((opTime.dy - opBadge.dy).abs() <= 12, isTrue,
        reason: 'OP time shares the rank badge line');
    expect(opTime.dy < opName.dy - 8, isTrue,
        reason: 'OP time is above the username');
    expect(opTime.dx > 600, isTrue, reason: 'OP time sits top-right');
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

    // Only the typed text is stored: the reply relationship carries the
    // quote, so nothing is prefixed onto it.
    expect(social.sent, ['Agreed!']);
    expect(social.sentParents, [1]);
    // The sent reply lands as a flat card quoting the context the server
    // resolved for it. The composer banner is gone again, so the card's
    // header is the only "Replying to" text.
    expect(find.byType(CommentQuoteCard), findsOneWidget);
    expect(find.text('Replying to @Someone'), findsOneWidget);
    expect(find.text('Agreed!'), findsOneWidget);
  });

  testWidgets('reply chains render as separate flat cards, all numbered',
      (tester) async {
    // Tall viewport: full-width body cards stack high; all three must
    // be built (no lazy disposal) so their texts stay findable.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

    // Every reply is its own full-width card with its own number; the list
    // stays flat (no rail, no count toggle) and these rows carry no quote.
    expect(find.text('Root reply'), findsOneWidget);
    expect(find.text('Child reply'), findsOneWidget);
    expect(find.text('Grandchild reply'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('#3'), findsOneWidget);
    expect(find.text('3 Replies'), findsOneWidget);
    expect(find.byType(ThreadElbow), findsNothing);
    expect(find.byType(RailDrop), findsNothing);
    final left = tester.getTopLeft(find.text('Root reply')).dx;
    expect((tester.getTopLeft(find.text('Child reply')).dx - left).abs() < 1.0,
        isTrue, reason: 'flat replies share the card left edge');
    expect(
        (tester.getTopLeft(find.text('Grandchild reply')).dx - left).abs() < 1.0,
        isTrue, reason: 'a reply to a reply is not indented either');
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
