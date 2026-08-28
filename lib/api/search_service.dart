import 'api_client.dart';

/// Live search over posts, users and comments.
///
/// Contract (api/v1/search.php?format=json - the structured mode added
/// for the native app; the default html mode still serves the site's
/// React SearchBox island): {success, total, results:[...]} where every
/// row carries type (user|post|comment), id, user_id, post_id, username,
/// avatar (root-relative), rank (RAW config name - the app maps it via
/// RankColors), personality_type (raw MBTI string), content (truncated
/// to 100 chars server-side), post_content (comments), date, stats.
/// Users sort first, then posts, then comments.
class SearchService {
  SearchService(this._api);

  final ApiClient _api;

  /// GET /api/v1/search?q=...&format=json - throws on transport/4xx/5xx
  /// (the caller renders an error state); returns [] for no matches.
  Future<List<SearchResult>> search(String query) async {
    final json = await _api.getJson('/api/v1/search', query: {
      'q': query,
      'format': 'json',
    });
    final raw = json['results'] as List<dynamic>? ?? const [];
    return [
      for (final r in raw)
        if (r is Map<String, dynamic>) SearchResult.fromJson(r),
    ];
  }
}

/// One structured search row (api/v1/search.php format=json).
class SearchResult {
  const SearchResult({
    required this.type,
    required this.id,
    required this.userId,
    required this.postId,
    required this.username,
    required this.avatar,
    required this.rank,
    required this.personalityType,
    required this.content,
    required this.postContent,
    required this.date,
    required this.stats,
  });

  final String type; // 'user' | 'post' | 'comment'
  final int id;
  final int userId;
  final int postId; // 0 unless type == 'comment'
  final String username;
  final String avatar; // root-relative
  final String rank; // raw config name: 'SysOp', 'Member', ...
  final String personalityType; // raw MBTI: 'INTJ', '' when unset
  final String content; // post/comment text, or bio for users
  final String postContent; // the comment's parent post text
  final String date;
  final Map<String, dynamic> stats; // users: {posts}, posts: {likes, comments}

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
        type: json['type'] as String? ?? '',
        id: (json['id'] as num?)?.toInt() ?? 0,
        userId: (json['user_id'] as num?)?.toInt() ?? 0,
        postId: (json['post_id'] as num?)?.toInt() ?? 0,
        username: json['username'] as String? ?? '',
        avatar: json['avatar'] as String? ?? '',
        rank: json['rank'] as String? ?? 'Member',
        personalityType: json['personality_type'] as String? ?? '',
        content: json['content'] as String? ?? '',
        postContent: json['post_content'] as String? ?? '',
        date: json['date'] as String? ?? '',
        stats: json['stats'] is Map
            ? Map<String, dynamic>.from(json['stats'] as Map)
            : const {},
      );
}
