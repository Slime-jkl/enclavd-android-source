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
}
