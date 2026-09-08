import 'package:enclavd/api/feed_service.dart';
import 'package:enclavd/screens/feed_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// The new-posts pill decision (pillEligiblePosts + feedMaxPostId): the seen
/// threshold is monotonic and delta posts are never inserted (the old refresh
/// hoisted buried posts to the top on every pull).
Post post(int id) => Post(
      id: id,
      content: 'post $id',
      createdAt: '2026-08-27 12:00:00',
      feedScore: 10.0 - id / 100,
      likeCount: 0,
      commentCount: 0,
      userLiked: false,
      warningCount: 0,
      username: 'u$id',
      profilePictureUrl: '/assets/default-avatar.png',
      personalityType: null,
      isActive: 'true',
      rank: 'Member',
      image: null,
    );

void main() {
  group('feedMaxPostId', () {
    test('empty list keeps the floor', () {
      expect(feedMaxPostId(const [], 7), 7);
    });

    test('picks the highest id on screen', () {
      expect(feedMaxPostId([post(3), post(9), post(5)], 0), 9);
    });

    test('never lowers an existing threshold', () {
      expect(feedMaxPostId([post(3)], 9), 9);
    });
  });

  group('pillEligiblePosts', () {
    final ranked = [post(90), post(80), post(70)]; // pure ranked top page
    const seen = 100; // highest id ever displayed

    test('no delta, no pill', () {
      expect(pillEligiblePosts(const [], ranked, seen), isEmpty);
    });

    test('a post already on screen is never offered', () {
      expect(
        pillEligiblePosts([post(90), post(95)], ranked, seen),
        isEmpty,
      );
    });

    test('a post newer than the seen threshold IS offered', () {
      final eligible = pillEligiblePosts([post(500)], ranked, seen);
      expect(eligible, hasLength(1));
      expect(eligible.single.id, 500);
    });

    test('a post at or below the seen threshold is never re-offered '
        '(the oscillation regression)', () {
      // Post 500 was hoisted and clicked once; the monotonic threshold must NOT offer it again.
      expect(
        pillEligiblePosts([post(500)], ranked, 500),
        isEmpty,
      );
      expect(
        pillEligiblePosts([post(499)], ranked, 500),
        isEmpty,
      );
    });

    test('mixed delta: only genuinely new posts are offered', () {
      final delta = [
        post(90), // on screen, skip
        post(99), // below seenMaxId, skip (was shown before)
        post(100), // at threshold, skip
        post(101), // new, off screen, offer
        post(500), // new, off screen, offer
      ];
      final eligible = pillEligiblePosts(delta, ranked, seen);
      expect(eligible.map((p) => p.id), [101, 500]);
    });

    test('offer does not mutate the seen threshold (raised on display, '
        'not on offer)', () {
      // The pill may re-offer an ignored post until the user actually loads it (site behavior).
      final eligible = pillEligiblePosts([post(500)], ranked, seen);
      expect(eligible, hasLength(1));
      expect(feedMaxPostId(ranked, seen), seen); // unchanged by the offer
    });
  });

  group('feedAppendPosts', () {
    test('appends new posts in order', () {
      expect(
        feedAppendPosts([post(1)], [post(2), post(3)]).map((p) => p.id),
        [2, 3],
      );
    });

    test('skips a boundary duplicate re-returned by the cursor', () {
      final current = [post(1), post(2), post(10)];
      final incoming = [post(10), post(11), post(12)];
      expect(
        feedAppendPosts(current, incoming).map((p) => p.id),
        [11, 12],
      );
    });

    test('skips a fully duplicated page but keeps incoming order', () {
      final current = [post(5), post(6)];
      expect(feedAppendPosts(current, [post(6)]), isEmpty);
    });
  });

  group('feedRankCompare', () {
    test('higher score ranks above', () {
      expect(feedRankCompare(scored(1, 4.0), scored(2, 3.0)), isNegative);
      expect(feedRankCompare(scored(2, 3.0), scored(1, 4.0)), isPositive);
    });

    test('equal scores break by higher id (server tie-break)', () {
      expect(feedRankCompare(scored(20, 5.0), scored(10, 5.0)), isNegative);
    });

    test('null score ranks below every real score', () {
      expect(feedRankCompare(scored(1, 1.0), scored(2, null)), isNegative);
      expect(feedRankCompare(scored(2, null), scored(1, 1.0)), isPositive);
    });

    test('both null still tie-break by higher id', () {
      expect(feedRankCompare(scored(9, null), scored(8, null)), isNegative);
    });
  });

  group('feedMergeRanked', () {
    test('empty current adopts the incoming sequence', () {
      expect(
        feedMergeRanked(const [], [scored(30, 3.0), scored(10, 1.0)])
            .map((p) => p.id),
        [30, 10],
      );
    });

    test('new top post lands above the ranked list, not on a fake top',
        () {
      final current = [scored(30, 3.0), scored(20, 2.0), scored(10, 1.0)];
      expect(
        feedMergeRanked(current, [scored(40, 4.0)]).map((p) => p.id),
        [40, 30, 20, 10],
      );
    });

    test('a buried new post slots into the middle', () {
      final current = [scored(30, 3.0), scored(20, 2.0), scored(10, 1.0)];
      expect(
        feedMergeRanked(current, [scored(25, 2.5)]).map((p) => p.id),
        [30, 25, 20, 10],
      );
    });

    test('a below-fold new post appends at the tail', () {
      final current = [scored(30, 3.0), scored(20, 2.0), scored(10, 1.0)];
      expect(
        feedMergeRanked(current, [scored(5, 0.5)]).map((p) => p.id),
        [30, 20, 10, 5],
      );
    });

    test('interleaved batches keep the whole list sorted', () {
      final current = [scored(60, 6.0), scored(40, 4.0), scored(20, 2.0)];
      final incoming = [scored(50, 5.0), scored(30, 3.0), scored(10, 1.0)];
      expect(
        feedMergeRanked(current, incoming).map((p) => p.id),
        [60, 50, 40, 30, 20, 10],
      );
    });

    test('a boundary duplicate re-returned by the cursor is kept once', () {
      final current = [scored(30, 3.0), scored(20, 2.0), scored(10, 1.0)];
      // The extension page re-opens at the old frontier (float cursor
      // drift): it re-returns the tail row 10 before the new rows.
      expect(
        feedMergeRanked(current, [scored(10, 1.0), scored(5, 0.5)])
            .map((p) => p.id),
        [30, 20, 10, 5],
      );
    });

    test('never re-orders the current list when nothing fits above', () {
      final current = [scored(30, 3.0), scored(20, 2.0), scored(10, 1.0)];
      expect(feedMergeRanked(current, const []).map((p) => p.id),
          [30, 20, 10]);
    });
  });
}

/// Explicit score + relative timestamp, independent of the shared helper.
Post scored(int id, double? score) => Post(
      id: id,
      content: 'p$id',
      createdAt: _utcStamp(),
      feedScore: score,
      likeCount: 0,
      commentCount: 0,
      userLiked: false,
      warningCount: 0,
      username: 'u$id',
      profilePictureUrl: '/assets/default-avatar.png',
      personalityType: null,
      isActive: 'true',
      rank: 'Member',
      image: null,
    );

/// 'Y-m-d H:i:s' in UTC, relative to now (fixed dates go stale).
String _utcStamp() {
  final t = DateTime.now().toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
