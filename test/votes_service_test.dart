import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/votes_service.dart';

import 'api_client_test.dart' show Harness;

Map<String, dynamic> _voteJson({
  int id = 20,
  String title = 'App Test Vote',
  String status = 'active',
  List<String> options = const ['Alpha', 'Beta'],
  List<int> counts = const [0, 1],
  int? myOption,
  String? myVoteChangedAt,
}) =>
    {
      'id': id,
      'title': title,
      'description': 'verification',
      'options': options,
      'colors': ['#8b5cf6', '#ec4899'],
      'counts': counts,
      'total_votes': counts.fold<int>(0, (a, b) => a + b),
      'end_date': '2026-09-01 12:16:46',
      'status': status,
      'created_at': '2026-08-25 12:16:46',
      'creator_id': 1,
      'creator_username': 'Developer',
      'creator_avatar': '/assets/default-avatar.png',
      'creator_rank': 'SysOp',
      'my_option': myOption,
      'my_vote_changed_at': myVoteChangedAt,
    };

void main() {
  group('VotesService.fetch', () {
    test('parses the full votes payload', () async {
      final h = await Harness.start((req) async {
        expect(req.uri.path, '/api/v1/votes');
        Harness.respond(
          req,
          body: jsonEncode({
            'success': true,
            'active': [
              _voteJson(myOption: 1, myVoteChangedAt: '2026-08-25 12:17:26'),
            ],
            'completed': [_voteJson(id: 8, title: 'Old poll', status: 'completed')],
            'voting_power': 2,
            'is_admin': true,
            'rank_powers': [
              {'rank': 'SysOp', 'name': 'SysOp', 'voting_power': 1},
              {'rank': 'Admin', 'name': 'Admin', 'voting_power': 1},
            ],
          }),
        );
      });

      final data = await VotesService(h.client).fetch();

      expect(data.active, hasLength(1));
      final v = data.active.first;
      expect(v.id, 20);
      expect(v.title, 'App Test Vote');
      expect(v.description, 'verification');
      expect(v.options, ['Alpha', 'Beta']);
      expect(v.colors, ['#8b5cf6', '#ec4899']);
      expect(v.counts, [0, 1]);
      expect(v.totalVotes, 1);
      expect(v.endDate, '2026-09-01 12:16:46');
      expect(v.status, 'active');
      expect(v.completed, isFalse);
      expect(v.creatorId, 1);
      expect(v.creatorUsername, 'Developer');
      expect(v.creatorRank, 'SysOp');
      expect(v.myOption, 1);
      expect(v.myVoteChangedAt, '2026-08-25 12:17:26');
      expect(v.pct(1), closeTo(100.0, 0.01));
      expect(v.pct(0), closeTo(0.0, 0.01));

      expect(data.completed, hasLength(1));
      expect(data.completed.first.id, 8);
      expect(data.completed.first.completed, isTrue);

      expect(data.votingPower, 2);
      expect(data.isAdmin, isTrue);
      expect(data.rankPowers, hasLength(2));
      expect(data.rankPowers.first.rank, 'SysOp');
      expect(data.rankPowers.first.votingPower, 1);

      await h.close();
    });

    test('defaults when the payload is sparse (old/partial deploy)', () async {
      final h = await Harness.start((req) async {
        Harness.respond(req, body: '{"success":true}');
      });

      final data = await VotesService(h.client).fetch();

      expect(data.active, isEmpty);
      expect(data.completed, isEmpty);
      expect(data.votingPower, 0);
      expect(data.isAdmin, isFalse);
      expect(data.rankPowers, isEmpty);

      await h.close();
    });
  });

  group('VotesService.vote', () {
    test('sends the action with CSRF and parses fresh counts', () async {
      String? postedBody;
      final h = await Harness.start((req) async {
        // postJson fetches the CSRF token from /feed's meta first.
        if (req.uri.path == '/feed') {
          Harness.respond(
              req, body: '<meta name="csrf-token" content="csrf123">');
          return;
        }
        expect(req.uri.path, '/api/v1/votes');
        expect(req.method, 'POST');
        expect(req.headers.value('x-csrf-token'), 'csrf123');
        expect(req.headers.value('content-type'), contains('application/json'));
        postedBody = await utf8.decoder.bind(req).join();
        Harness.respond(
          req,
          body: jsonEncode(
              {'success': true, 'my_vote': 1, 'counts': [0, 1]}),
        );
      });

      final result = await VotesService(h.client).vote(20, 1);

      expect(jsonDecode(postedBody!), {
        'action': 'vote',
        'feature_id': 20,
        'selected_option': 1,
      });
      expect(result.myVote, 1);
      expect(result.counts, [0, 1]);

      await h.close();
    });

    test('server business errors surface as ApiException', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
          return;
        }
        Harness.respond(
            req, status: 409, body: '{"error":"This vote has ended"}');
      });

      await expectLater(
        VotesService(h.client).vote(8, 0),
        throwsA(isA<ApiException>().having(
            (e) => e.message, 'message', contains('This vote has ended'))),
      );

      await h.close();
    });
  });
}
