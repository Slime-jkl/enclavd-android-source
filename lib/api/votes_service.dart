import 'api_client.dart';

/// One community poll — api/v1/votes.php vote row.
///
/// Contract: id, title, description, options (string list), colors (hex
/// '#rrggbb' list), counts (WEIGHTED per option — SUM of each voter's rank
/// voting_power, the site's card math, not raw user counts), total_votes,
/// end_date (DB UTC wall-clock 'YYYY-MM-DD HH:MM:SS'), status
/// ('active'|'completed'|'cancelled'), created_at, creator_id,
/// creator_username, creator_avatar (root-relative), creator_rank,
/// my_option (int|null — the viewer's own choice), my_vote_changed_at
/// (DB string|null — set when the vote was created or last changed).
class Vote {
  const Vote({
    required this.id,
    required this.title,
    required this.description,
    required this.options,
    required this.colors,
    required this.counts,
    required this.totalVotes,
    required this.endDate,
    required this.status,
    required this.createdAt,
    required this.creatorId,
    required this.creatorUsername,
    required this.creatorAvatar,
    required this.creatorRank,
    this.myOption,
    this.myVoteChangedAt,
  });

  final int id;
  final String title;
  final String description;
  final List<String> options;
  final List<String> colors; // hex '#rrggbb', one per option
  final List<int> counts; // weighted per option, aligned with options
  final int totalVotes;
  final String endDate; // DB UTC wall-clock
  final String status;
  final String createdAt;
  final int creatorId;
  final String creatorUsername;
  final String creatorAvatar; // root-relative path
  final String creatorRank;
  final int? myOption;
  final String? myVoteChangedAt;

  /// The server splits polls into active/completed lists by status; a card
  /// renders the read-only variant when it came from the completed list.
  bool get completed => status != 'active';

  /// Percentage share of option [i] (weighted), the site's pct() math.
  double pct(int i) => totalVotes > 0 ? (counts[i] / totalVotes) * 100 : 0;

  /// The card's own vote updated in place from the POST response.
  Vote copyWith({List<int>? counts, int? myOption, String? myVoteChangedAt}) =>
      Vote(
        id: id,
        title: title,
        description: description,
        options: options,
        colors: colors,
        counts: counts ?? this.counts,
        totalVotes: (counts ?? this.counts).fold(0, (a, b) => a + b),
        endDate: endDate,
        status: status,
        createdAt: createdAt,
        creatorId: creatorId,
        creatorUsername: creatorUsername,
        creatorAvatar: creatorAvatar,
        creatorRank: creatorRank,
        myOption: myOption ?? this.myOption,
        myVoteChangedAt: myVoteChangedAt ?? this.myVoteChangedAt,
      );

  factory Vote.fromJson(Map<String, dynamic> json) => Vote(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        options:
            (json['options'] as List?)?.cast<String>() ?? const [],
        colors:
            (json['colors'] as List?)?.cast<String>() ?? const [],
        counts: (json['counts'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const [],
        totalVotes: (json['total_votes'] as num?)?.toInt() ?? 0,
        endDate: json['end_date'] as String? ?? '',
        status: json['status'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        creatorId: (json['creator_id'] as num?)?.toInt() ?? 0,
        creatorUsername: json['creator_username'] as String? ?? '',
        creatorAvatar: json['creator_avatar'] as String? ??
            '/assets/default-avatar.png',
        creatorRank: json['creator_rank'] as String? ?? 'Member',
        myOption: (json['my_option'] as num?)?.toInt(),
        myVoteChangedAt: json['my_vote_changed_at'] as String?,
      );
}

/// One rank's voting power (vote.php's "View Rank Voting Powers" section).
class RankPower {
  const RankPower({
    required this.rank,
    required this.name,
    required this.votingPower,
  });

  final String rank;
  final String name;
  final int votingPower;

  factory RankPower.fromJson(Map<String, dynamic> json) => RankPower(
        rank: json['rank'] as String? ?? '',
        name: json['name'] as String? ?? '',
        votingPower: (json['voting_power'] as num?)?.toInt() ?? 1,
      );
}

/// The full votes payload: both sections, the viewer's voting power and the
/// rank table for the "How Voting Works" info.
class VotesData {
  const VotesData({
    required this.active,
    required this.completed,
    required this.votingPower,
    required this.isAdmin,
    required this.rankPowers,
  });

  final List<Vote> active;
  final List<Vote> completed;
  final int votingPower;
  final bool isAdmin;
  final List<RankPower> rankPowers;

  factory VotesData.fromJson(Map<String, dynamic> json) => VotesData(
        active: (json['active'] as List?)
                ?.map((e) => Vote.fromJson(
                    (e as Map?)?.cast<String, dynamic>() ?? const {}))
                .toList() ??
            const [],
        completed: (json['completed'] as List?)
                ?.map((e) => Vote.fromJson(
                    (e as Map?)?.cast<String, dynamic>() ?? const {}))
                .toList() ??
            const [],
        votingPower: (json['voting_power'] as num?)?.toInt() ?? 0,
        isAdmin: json['is_admin'] as bool? ?? false,
        rankPowers: (json['rank_powers'] as List?)
                ?.map((e) => RankPower.fromJson(
                    (e as Map?)?.cast<String, dynamic>() ?? const {}))
                .toList() ??
            const [],
      );
}

/// Outcome of a vote submit/change: the accepted option + fresh weighted
/// counts (the card updates in place, single round trip — server truth).
class VoteResult {
  const VoteResult({required this.myVote, required this.counts});

  final int myVote;
  final List<int> counts;
}

/// VotesService: the community polls behind the Votes tab.
class VotesService {
  VotesService(this._api);

  final ApiClient _api;

  /// Active + completed polls with the viewer's own votes embedded.
  Future<VotesData> fetch() async {
    final json = await _api.getJson('/api/v1/votes');
    return VotesData.fromJson(json);
  }

  /// Submit (or change) a vote on [featureId]. The server enforces the
  /// feature being active and the option being in range; 409/400 errors
  /// surface as ApiException business messages.
  Future<VoteResult> vote(int featureId, int option) async {
    final json = await _api.postJson('/api/v1/votes', {
      'action': 'vote',
      'feature_id': featureId,
      'selected_option': option,
    });
    return VoteResult(
      myVote: (json['my_vote'] as num?)?.toInt() ?? option,
      counts: (json['counts'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
    );
  }
}
