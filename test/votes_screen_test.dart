import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/votes_service.dart';
import 'package:enclavd/screens/votes_screen.dart';

/// Fake service with canned payloads (no sockets under flutter test).
class _FakeVotes extends VotesService {
  _FakeVotes(this.data)
      : super(ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  VotesData data;
  int voteCalls = 0;

  @override
  Future<VotesData> fetch() async => data;

  @override
  Future<VoteResult> vote(int featureId, int option) async {
    voteCalls++;
    final inActive = data.active.indexWhere((v) => v.id == featureId);
    final inCompleted = data.completed.indexWhere((v) => v.id == featureId);
    final idx = inActive >= 0 ? inActive : inCompleted;
    final list = inActive >= 0 ? data.active : data.completed;
    final vote = list[idx];
    final newCounts = [...vote.counts]..[option] = vote.counts[option] + 1;
    final updated = vote.copyWith(counts: newCounts, myOption: option);
    final next = [...list]..[idx] = updated;
    data = VotesData(
      active: inActive >= 0 ? next : data.active,
      completed: inActive >= 0 ? data.completed : next,
      votingPower: data.votingPower,
      isAdmin: data.isAdmin,
      rankPowers: data.rankPowers,
    );
    return VoteResult(myVote: option, counts: newCounts);
  }
}

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

Vote _vote({
  int id = 1,
  String title = 'Feed changes',
  String status = 'active',
  List<String> options = const ['Yes', 'No'],
  List<int> counts = const [1, 1],
  int? myOption,
  String? myVoteChangedAt,
}) =>
    Vote(
      id: id,
      title: title,
      description: 'Vote on the feed.',
      options: options,
      colors: const ['#8b5cf6', '#ec4899'],
      counts: counts,
      totalVotes: counts.fold<int>(0, (a, b) => a + b),
      endDate: '2026-09-01 12:00:00',
      status: status,
      createdAt: '2026-08-01 12:00:00',
      creatorId: 1,
      creatorUsername: 'Developer',
      creatorAvatar: '/assets/default-avatar.png',
      creatorRank: 'SysOp',
      myOption: myOption,
      myVoteChangedAt: myVoteChangedAt,
    );

VotesData _data({
  List<Vote> active = const [],
  List<Vote> completed = const [],
  int votingPower = 1,
}) =>
    VotesData(
      active: active,
      completed: completed,
      votingPower: votingPower,
      isAdmin: false,
      rankPowers: const [
        RankPower(rank: 'SysOp', name: 'SysOp', votingPower: 1),
        RankPower(rank: 'Admin', name: 'Admin', votingPower: 1),
      ],
    );

Future<void> _pump(WidgetTester tester, VotesService service) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: VotesScreen(votes: service)),
  ));
  // Skeleton frame → fetch future resolves → content frame.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('renders active + completed sections with cards and counts',
      (tester) async {
    final service = _FakeVotes(_data(
      active: [_vote()],
      completed: [_vote(id: 8, title: 'Old poll', status: 'completed')],
    ));

    await _pump(tester, service);

    expect(find.text('Active Votes'), findsOneWidget);
    expect(find.text('Completed Votes'), findsOneWidget);
    expect(find.text('Feed changes'), findsOneWidget);
    expect(find.text('Old poll'), findsOneWidget);
    // Percentages from the weighted counts (50% each here).
    expect(find.text('50.0%'), findsNWidgets(4));
    // Voting power line.
    expect(find.textContaining('×1'), findsWidgets);
    // The active card offers Submit; the completed one is read-only.
    expect(find.text('Submit Vote'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('empty states show when there are no polls', (tester) async {
    final service = _FakeVotes(_data());

    await _pump(tester, service);

    expect(find.text('No active votes at the moment.'), findsOneWidget);
    expect(find.text('No completed votes yet.'), findsOneWidget);
    expect(find.text('Submit Vote'), findsNothing);
  });

  testWidgets('selecting an option and submitting updates the card',
      (tester) async {
    final service = _FakeVotes(_data(active: [_vote()]));

    await _pump(tester, service);

    // Tap the second option ('No'), then submit.
    await tester.tap(find.byKey(const ValueKey('vote-1-option-1')));
    await tester.pump();
    await tester.tap(find.text('Submit Vote'));
    await tester.pump();
    await tester.pump();

    expect(service.voteCalls, 1);
    // Card now shows the chosen option and the Change Vote affordance.
    expect(find.text('Change Vote'), findsOneWidget);
    expect(find.text('Your current vote'), findsOneWidget);
    // Counts went 1 → 2 for the chosen option: 66.7% / 33.3%.
    expect(find.text('66.7%'), findsOneWidget);
    expect(find.text('33.3%'), findsOneWidget);
  });

  testWidgets('an already-made vote renders highlighted and changeable',
      (tester) async {
    final service = _FakeVotes(_data(
      active: [
        _vote(myOption: 0, myVoteChangedAt: '2026-08-25 10:00:00'),
      ],
    ));

    await _pump(tester, service);

    expect(find.text('Change Vote'), findsOneWidget);
    expect(find.textContaining('Your current vote'), findsOneWidget);
  });

  testWidgets('a completed card never offers a submit button', (tester) async {
    final service = _FakeVotes(_data(
      completed: [_vote(status: 'completed')],
    ));

    await _pump(tester, service);

    expect(find.text('Submit Vote'), findsNothing);
    expect(find.text('Change Vote'), findsNothing);
    expect(find.text('Completed'), findsOneWidget);
    // Read-only: tapping an option row must not submit anything.
    await tester.tap(find.byKey(const ValueKey('vote-1-option-0')));
    await tester.pump();
    expect(service.voteCalls, 0);
  });
}
