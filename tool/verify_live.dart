// Live end-to-end verification against the dev stack (https://localhost).
// CLI tool: stdout reporting is the point, so print is fine here.
// ignore_for_file: avoid_print
//
// Uses the REAL ApiClient/AuthService/FeedService code paths — the same
// classes the app runs — with an in-memory cookie store and a client that
// tolerates the dev stack's self-signed cert. NOT a unit test: it requires
// the dev stack to be up and a dev account (dev@dev.dev / Enclavd2026!).
//
// Run: flutter pub get && dart run tool/verify_live.dart
//
// Exit 0 = the full login → me → feed → next-page flow works with the
// native client's session handling (cookie jar + UA binding).

import 'dart:io';
import 'dart:typed_data';

import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/auth_service.dart';
import 'package:enclavd/api/feed_service.dart';
import 'package:enclavd/api/messages_service.dart';
import 'package:enclavd/api/posts_service.dart';
import 'package:enclavd/api/profile_service.dart';
import 'package:enclavd/api/social_service.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class MemStore implements SessionStore {
  List<SessionCookie> cookies = const [];
  @override
  Future<List<SessionCookie>> load() async => cookies;
  @override
  Future<void> save(List<SessionCookie> c) async => cookies = List.of(c);
  @override
  Future<void> clear() async => cookies = [];
}

Future<void> main() async {
  const base = 'https://localhost';
  final store = MemStore();
  final api = ApiClient(
    store: store,
    apiBaseUrl: base,
    httpClientFactory: () {
      final c = HttpClient();
      c.userAgent = 'EnclavdNative/1.0';
      c.connectionTimeout = const Duration(seconds: 15);
      c.badCertificateCallback = (cert, host, port) => true; // dev self-signed
      return c;
    },
  );
  await api.restoreSession();

  final auth = AuthService(api, apiBaseUrl: base);
  final feed = FeedService(api);
  final social = SocialService(api);
  final profileService = ProfileService(api);
  final postsService = PostsService(api);
  final messages = MessagesService(api);

  var failures = 0;
  void check(String label, bool ok, [String? detail]) {
    print(
        '${ok ? 'PASS' : 'FAIL'}  $label${detail != null ? ' — $detail' : ''}');
    if (!ok) failures++;
  }

  // ── 1. Login (login_token dance + 302 verdict + cookie capture) ────────
  final token = await auth.fetchLoginToken();
  check('GET /login returns a login_token', token != null && token.isNotEmpty);
  check('session cookie sid captured',
      api.sessionCookies.any((c) => c.name == 'sid'));

  final login =
      await auth.login(email: 'dev@dev.dev', password: 'Enclavd2026!');
  check('login succeeds', login.outcome == LoginOutcome.success, login.message);
  check('enclavd_sid session cookie captured',
      api.sessionCookies.any((c) => c.name == 'enclavd_sid'));
  check('jar persisted after login', store.cookies.isNotEmpty);

  // ── 2. /api/v1/me ──────────────────────────────────────────────────────
  final me = await auth.me();
  check('me() returns the user', me != null, me?.username ?? 'null');
  check('me() username matches dev account', me?.username == 'Developer',
      me?.username);

  // ── 3. Feed page 1 + keyset page 2 ─────────────────────────────────────
  final page1 = await feed.firstPage(limit: 3);
  check('feed page 1 returns posts', page1.posts.isNotEmpty,
      '${page1.posts.length} posts, has_more=${page1.hasMore}');
  final p0 = page1.posts.first;
  check(
      'post fields populated',
      p0.username.isNotEmpty && p0.content.isNotEmpty,
      '#${p0.id} by ${p0.username} rank=${p0.rank}');

  if (page1.hasMore && page1.lastScore != null && page1.lastId != null) {
    final page2 = await feed.nextPage(page1, limit: 3);
    check('feed page 2 via keyset returns posts', page2.posts.isNotEmpty,
        '${page2.posts.length} posts');
    check('page 2 has no overlap with page 1',
        !page2.posts.any((p) => p.id == p0.id));
  } else {
    check('feed page 2 via keyset returns posts', true, 'skipped — no more');
  }

  // ── 4. Media URL resolution ────────────────────────────────────────────
  final avatarUrl = resolveMediaUrl(base, avatarPath: p0.profilePictureUrl);
  check('avatar URL is absolute', avatarUrl.startsWith('https://'));
  if (p0.image != null) {
    final imgUrl = resolveMediaUrl(base, galleryName: p0.image);
    check('gallery URL points at /public/gallery/',
        imgUrl.contains('/public/gallery/'), imgUrl);
  }

  // ── 5. Profile — header, own posts (keyset), self-follow guard ─────────
  check('feed post carries author_id', p0.authorId > 0,
      '#${p0.id} → ${p0.authorId}');
  final prof = await profileService.fetchProfile(p0.authorId);
  check('profile GET returns the author', prof.username == p0.username,
      '${prof.username} rank=${prof.rank}');
  check('profile is the dev account (is_own)', prof.isOwn, 'id=${prof.id}');
  check(
      'profile stats populated',
      prof.followerCount >= 0 && prof.followingCount >= 0 && prof.postCount > 0,
      'followers=${prof.followerCount} following=${prof.followingCount} posts=${prof.postCount}');
  check('joined date formats', formatJoinedDate(prof.dateCreated).isNotEmpty,
      formatJoinedDate(prof.dateCreated));

  final up1 = await feed.userPosts(p0.authorId, limit: 3);
  check('user posts page 1 returns posts', up1.posts.isNotEmpty,
      '${up1.posts.length} posts');
  check('user posts are all by the author',
      up1.posts.every((p) => p.authorId == p0.authorId));
  if (up1.hasMore && up1.lastCreatedAt != null) {
    final up2 = await feed.userPosts(p0.authorId,
        limit: 3, lastCreatedAt: up1.lastCreatedAt, lastId: up1.lastId);
    check('user posts page 2 via keyset returns posts', up2.posts.isNotEmpty,
        '${up2.posts.length} posts');
    check('user posts page 2 has no overlap',
        !up2.posts.any((p) => p.id == up1.posts.first.id));
  } else {
    check('user posts page 2 via keyset returns posts', true,
        'skipped — no more');
  }

  // Self-follow must be rejected with 400 (server-side guard).
  var selfFollowBlocked = false;
  try {
    await profileService.toggleFollow(p0.authorId);
  } on ApiException catch (e) {
    selfFollowBlocked = e.status == 400;
  }
  check('self-follow guard rejects with 400', selfFollowBlocked);

  // ── 6. Posts — create (with image) → update → delete roundtrip ─────────
  // A realistic-size JPEG generated in-process (1400×1400, q90) — the
  // multipart create path must carry payloads like a real camera photo
  // (the editor bakes ≤1200px, so this is even bigger than app output).
  final bigJpeg = img.encodeJpg(
    img.fill(img.Image(width: 1400, height: 1400),
        color: img.ColorRgb8(60, 120, 200)),
    quality: 90,
  );
  final postStamp = DateTime.now().millisecondsSinceEpoch;
  final newId = await postsService.createPost(
    content: 'native-app verify post $postStamp #verifytest',
    image: XFile.fromData(Uint8List.fromList(bigJpeg),
        name: 'verify.jpg', mimeType: 'image/jpeg'),
  );
  check('post create returns an id', newId > 0, '#$newId');

  final createdPost = await feed.fetchPost(newId);
  check('created post is ours (is_owner)', createdPost.isOwner,
      '#${createdPost.id}');
  check('created post carries the image', createdPost.image != null,
      createdPost.image ?? 'none');
  final upPage = await feed.userPosts(1, limit: 20);
  check('created post appears in user posts',
      upPage.posts.any((p) => p.id == newId));

  // Pull-to-refresh path: the newer-than delta must surface the new post
  // against an older id sampled from the feed.
  final delta = await feed.newerThan(p0.id, limit: 10);
  check('newer-than delta surfaces the new post',
      delta.posts.any((p) => p.id == newId), '${delta.posts.length} delta');

  final updMsg = await postsService.updatePost(
    postId: newId,
    content: 'native-app verify post $postStamp edited',
    originalContent: 'native-app verify post $postStamp #verifytest',
  );
  check('post update confirms', updMsg.isNotEmpty, updMsg);
  final updated = await feed.fetchPost(newId);
  check('updated content is live', updated.content.contains('edited'));

  await postsService.deletePost(
      postId: newId,
      content: 'native-app verify post $postStamp edited #verifytest');
  var deleted = false;
  try {
    await feed.fetchPost(newId);
  } on ApiException catch (e) {
    deleted = e.status == 404;
  }
  check('deleted post is gone (404)', deleted);

  // Negative: an empty post (no text, no image) must be rejected.
  var emptyBlocked = false;
  try {
    await postsService.createPost(content: '');
  } on ApiException catch (e) {
    emptyBlocked = e.status == 400;
  }
  check('empty post rejected with 400', emptyBlocked);

  // ── 6b. Hashtags + entity decoding — the hashtag page contract ────────
  // A post whose content carries an apostrophe (stored as &#039;), a URL and
  // a unique hashtag. Post.fromJson must decode the entity (the "I&#0139;m"
  // bug), and GET /api/v1/posts?tag=… must surface the post with a total.
  final tagStamp = DateTime.now().millisecondsSinceEpoch;
  final tagName = 'verifytag$tagStamp';
  final htId = await postsService.createPost(
    content: "I'm testing #$tagName https://example.com/x",
  );
  check('hashtag post create returns an id', htId > 0, '#$htId');

  final htPost = await feed.fetchPost(htId);
  check('apostrophe is decoded (no &#039; in content)',
      htPost.content.contains("I'm") && !htPost.content.contains('&#'),
      htPost.content);

  final tagPage = await feed.tagPosts(tagName, limit: 5);
  check('tag page returns the post', tagPage.posts.any((p) => p.id == htId),
      '${tagPage.posts.length} posts, total=${tagPage.total}');
  check('tag page total counts it', (tagPage.total ?? 0) >= 1,
      'total=${tagPage.total}');
  check('tag page posts are newest first', tagPage.posts.first.id == htId,
      '#${tagPage.posts.first.id}');

  // A tag with no posts → empty page, total 0.
  final emptyTag = await feed.tagPosts('notag$tagStamp', limit: 5);
  check('unknown tag returns empty page', emptyTag.posts.isEmpty,
      'total=${emptyTag.total}');

  // Delete it; the tag page must no longer list it.
  await postsService.deletePost(
      postId: htId, content: "I'm testing #$tagName https://example.com/x");
  final tagAfter = await feed.tagPosts(tagName, limit: 5);
  check('deleted post leaves the tag page',
      !tagAfter.posts.any((p) => p.id == htId), '${tagAfter.posts.length} left');

  // ── 7. Likes — toggle ON, verify, toggle OFF (leave state untouched) ───
  // NOTE: the target post may already be liked by the dev user — first
  // toggle flips the current state, second toggle restores it.
  final target = p0;
  final like1 = await social.toggleLike(target.id);
  check('first toggle flips to ${target.userLiked ? 'unliked' : 'liked'}',
      like1.liked != target.userLiked, 'action=${like1.action}');
  // Count must move by exactly ±1 from the sampled value.
  final expected1 = target.likeCount + (target.userLiked ? -1 : 1);
  check('count moves by ±1 after first toggle', like1.likeCount == expected1,
      'count=${like1.likeCount} (expected $expected1)');
  final like2 = await social.toggleLike(target.id);
  check('second toggle restores original state',
      like2.liked == target.userLiked, 'action=${like2.action}');
  // Two toggles return the count to the value sampled from the feed.
  check('like count back to original', like2.likeCount == target.likeCount,
      'count=${like2.likeCount} (orig=${target.likeCount})');

  // ── 7b. Likers list — must match the post's like state ────────────────
  final likers = await social.likers(target.id);
  // The roundtrip restored the original state, so the dev user is listed
  // exactly when the post ended liked.
  check(
      'likers list matches final like state',
      likers.any((l) => l.username == 'Developer') == target.userLiked,
      '${likers.length} likers');
  if (likers.isNotEmpty) {
    check('liker carries raw rank + personality',
        likers.any((l) => l.rank.isNotEmpty && l.personalityType != null));
  }

  // ── 8. Comments — create → list → delete (leave state untouched) ───────
  final before = await social.listComments(target.id);
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final (created, countAfterCreate) =
      await social.createComment(target.id, 'native-app verify $stamp');
  check('comment created', created.id > 0 && created.content.contains('$stamp'),
      '#${created.id}');
  check('comment count reflects create', countAfterCreate == before.length + 1,
      '$countAfterCreate vs ${before.length + 1}');

  final afterCreate = await social.listComments(target.id);
  check('list shows the new comment',
      afterCreate.any((c) => c.id == created.id && c.isOwner));

  final countAfterDelete = await social.deleteComment(created.id, target.id);
  check(
      'comment delete returns previous count',
      countAfterDelete == before.length,
      '$countAfterDelete vs ${before.length}');
  final afterDelete = await social.listComments(target.id);
  check('list no longer has the deleted comment',
      !afterDelete.any((c) => c.id == created.id));

  // ── 8b. Messages — inbox → start → send → history → read state ─────────
  // The dev account already has conversations; the inbox must parse.
  final inbox = await messages.conversations();
  check('conversations() returns the inbox', inbox.isNotEmpty,
      '${inbox.length} conversations');
  final first = inbox.first;
  check('conversation row populated', first.participantId > 0 &&
      first.participantName.isNotEmpty &&
      first.participantAvatar.isNotEmpty, first.participantName);
  check('unread badge parses', first.unreadCount >= 0);

  // start() with user 3 reuses the existing 1-on-1 conversation.
  final convId = await messages.start(3);
  check('start() returns a conversation id', convId > 0, '#$convId');

  final msgStamp = DateTime.now().millisecondsSinceEpoch;
  final sentId = await messages.send(convId, 'live verify $msgStamp');
  check('send() returns a message id', sentId > 0, '#$sentId');

  final history = await messages.messages(convId);
  check('history contains the sent message',
      history.any((m) => m.id == sentId && m.message.contains('$msgStamp')),
      '${history.length} messages');
  final sent = history.firstWhere((m) => m.id == sentId);
  check('own message carries is_read=false', sent.isRead == false,
      'is_read=${sent.isRead}');
  check('sender_name populated', sent.senderName == 'Developer',
      sent.senderName);

  final unread = await messages.unreadCount();
  check('unreadCount() parses', unread >= 0, 'unread=$unread');

  await messages.markRead(convId);
  final afterRead = await messages.unreadCount();
  check('markRead() leaves the count parseable', afterRead >= 0,
      'unread=$afterRead');

  // ── 9. Logout (JSON body + CSRF header via api/v1/auth) ────────────────
  await auth.logout();
  check('logout clears the local jar', store.cookies.isEmpty);
  final afterLogout = await auth.me();
  check('session is dead after logout', afterLogout == null);

  print(failures == 0
      ? '\nALL LIVE CHECKS PASSED'
      : '\n$failures LIVE CHECK(S) FAILED');
  exit(failures == 0 ? 0 : 1);
}
